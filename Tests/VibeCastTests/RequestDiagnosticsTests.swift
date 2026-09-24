import Foundation
import Testing
@testable import VibeCast

@MainActor
struct RequestDiagnosticsTests {
    @Test func credentialsAreRemovedBeforeLogDisplayAndCopy() {
        let log = DiagnosticLog()
        let input = #"HTTP 403 /me/player; reason=RESTRICTION_VIOLATED Authorization: Bearer bearer-secret; {"access_token":"access-secret","refreshToken":"refresh-secret", "api_key": "key-secret", "password": "two word secret"} code_verifier=verifier-secret https://localhost/callback?code=oauth-secret&state=state-secret user@example.com /Users/private-user/Library"#
        log.record("Spotify", input, isError: true)
        for secret in ["bearer-secret", "access-secret", "refresh-secret", "key-secret", "two word secret", "verifier-secret", "oauth-secret", "state-secret", "user@example.com", "private-user"] {
            #expect(!log.entries[0].message.contains(secret))
            #expect(!log.text.contains(secret))
        }
        #expect(log.text.contains("HTTP 403 /me/player; reason=RESTRICTION_VIOLATED"))
        #expect(log.text.contains("[redacted]"))
        #expect(log.entries[0].isError)
    }

    @Test(arguments: [
        "token='two words secret'", "refresh_token=refresh-secret", "Authorization: Basic dXNlcjpwYXNz",
        "sk-proj-secret123456789", "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signingSecret",
        "https://example.com?access_token=secret-token&key=secret-key",
        #"{"authorization": "Bearer secret-value", "clientSecret": "client-value"}"#
    ])
    func commonCredentialFormatsAreRedacted(input: String) {
        let output = DiagnosticLog.redacted(input)
        #expect(output.contains("[redacted]"))
        #expect(!output.contains("secret"))
        #expect(!output.contains("dXNlcjpwYXNz"))
        #expect(!output.contains("signingSecret"))
        #expect(!output.contains("client-value"))
        #expect(DiagnosticLog.redacted(output) == output)
    }

    @Test(arguments: [#"{"access_token":"truncated-secret"#, "api_key='truncated-secret", "https://user:truncated-secret@example.com"])
    func partialProviderErrorsDoNotExposeCredentials(input: String) {
        let output = DiagnosticLog.redacted(input)
        #expect(!output.contains("truncated-secret"))
        #expect(DiagnosticLog.redacted(output) == output)
    }

    @Test func secretsAreRemovedBeforeLongMessagesAreTruncated() {
        let input = String(repeating: "a", count: 4_080) + " access_token=\"" + String(repeating: "sensitive", count: 1_000) + "\""
        let output = DiagnosticLog.redacted(input)
        #expect(!output.contains("sensitive"))
        #expect(output.contains("[truncated]"))
        #expect(output.count < 4_120)
    }

    @Test func technicalFailureDetailStaysOutOfRequestFeedback() {
        let feedback = RequestErrorPresentation(SpotifyAPIError.requestFailed(503, "upstream failure access_token=secret-value"))
        #expect(feedback.message == "Spotify is temporarily unavailable. Try again shortly.")
        #expect(!feedback.message.contains("503"))
        #expect(feedback.diagnostic.contains("503"))
        #expect(feedback.diagnostic.contains("upstream failure"))
        #expect(!feedback.diagnostic.contains("secret-value"))
        let refusal = RequestErrorPresentation(SpotifyAPIError.playbackRefused(path: "/me/player/previous", reason: .restricted))
        #expect(refusal.message.contains("current playback context"))
        #expect(refusal.diagnostic.contains("reason=RESTRICTION_VIOLATED"))
        #expect(refusal.diagnostic.contains("/me/player/previous"))
    }

    @Test func commonFailuresHaveSpecificRecoveryGuidance() {
        #expect(RequestErrorPresentation(SpotifyAPIError.unauthorized).message.contains("Reconnect"))
        #expect(RequestErrorPresentation(SpotifyAPIError.rateLimited(30)).message.contains("30 seconds"))
        #expect(RequestErrorPresentation(SpotifyAPIError.noAvailableDevices).message.contains("Open Spotify"))
        #expect(RequestErrorPresentation(URLError(.notConnectedToInternet)).message.contains("internet connection"))
        #expect(RequestErrorPresentation(URLError(.timedOut)).message.contains("timed out"))
        #expect(RequestErrorPresentation(CancellationError()).message == "Request cancelled.")
        let uncertain = RequestErrorPresentation(PlaybackConfirmationFailure.uncertainCommand)
        #expect(uncertain.message.contains("uncertain"))
        #expect(uncertain.message.contains("Check Spotify before trying again"))
        #expect(RequestErrorPresentation(PlaylistRecoveryError.missingReadAccess).message.contains("Reconnect Spotify"))
        #expect(RequestErrorPresentation(PlaylistRecoveryError.verificationFailed).message.contains("Keep the unfinished playlist"))
    }

    @Test func decodingAndUnknownFailuresDoNotLeakRawDescriptions() {
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "token=decoder-secret malformed playlist JSON"))
        let decoded = RequestErrorPresentation(decoding, source: .chatGPT)
        #expect(decoded.message.contains("ChatGPT returned an incomplete response"))
        #expect(decoded.diagnostic.contains("malformed playlist JSON"))
        #expect(!decoded.diagnostic.contains("decoder-secret"))
        let error = NSError(domain: "provider", code: 17, userInfo: [NSLocalizedDescriptionKey: "upstream diagnostic api_key=unknown-secret"])
        let unknown = RequestErrorPresentation(error)
        #expect(!unknown.message.contains("upstream diagnostic"))
        #expect(unknown.diagnostic.contains("provider (17)"))
        #expect(!unknown.diagnostic.contains("unknown-secret"))
    }

    @Test func actionableAppErrorsRemainActionableAndSafe() {
        let feedback = RequestErrorPresentation(UserFacingError("Reconnect in Settings. access_token=secret-value"))
        #expect(feedback.message.contains("Reconnect in Settings"))
        #expect(!feedback.message.contains("secret-value"))
        #expect(!feedback.diagnostic.contains("secret-value"))
    }

    @Test func subscriptionSettingsAndConsoleUseTheSameSafeBoundary() async {
        let settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let rpc = DiagnosticsFailureRPC()
        let session = ChatGPTSession(settings: settings, rpc: rpc)
        await session.refresh()
        #expect(session.error?.contains("Reconnect in Settings") == true)
        #expect(session.error?.contains("private-provider-message") == false)
        #expect(session.diagnostics.text.contains("private-provider-message"))
        #expect(!session.diagnostics.text.contains("provider-secret"))
    }

    @Test func cancelledHistoryRetainsStageAndDifferentPresentation() {
        let entry = RequestHistoryItem(prompt: "make a jazz playlist", routeName: "Cast Magic", message: "Request cancelled.", status: .cancelled, stage: "Matching songs")
        #expect(entry.stage == "Matching songs")
        #expect(entry.status.symbol == "stop.circle")
        #expect(RequestHistoryItem.Status.failure.symbol != entry.status.symbol)
    }
}

@MainActor
private final class DiagnosticsFailureRPC: CodexRPC {
    var onNotification: ((String, Data) -> Void)?
    var onTermination: (() -> Void)?
    func start() throws {
        throw NSError(domain: "Provider", code: 17, userInfo: [NSLocalizedDescriptionKey: "private-provider-message token=provider-secret"])
    }
    func request(_ method: String, params: Data, timeout: TimeInterval) async throws -> Data { Data() }
    func notify(_ method: String) throws { }
    func stop() { }
}
