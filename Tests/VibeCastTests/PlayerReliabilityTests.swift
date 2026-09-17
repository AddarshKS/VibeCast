import Foundation
import Testing
@testable import VibeCast

@MainActor
private final class HeldLoginReceiver: SpotifyLoginReceiving {
    var reply: CheckedContinuation<URL, Error>?
    private var callback: URL?
    func receiveCallback(open authorizationURL: URL, state: String) async throws -> URL {
        var url = URLComponents(string: AppConfig.spotifyRedirectURI)!
        url.queryItems = [.init(name: "state", value: state), .init(name: "code", value: "test-code")]
        callback = url.url
        return try await withCheckedThrowingContinuation { reply = $0 }
    }
    func finish() { reply?.resume(returning: callback!); reply = nil }
    func cancel() { reply?.resume(throwing: CancellationError()); reply = nil }
}

private actor TokenRaceTransport: HTTPTransport {
    private var refreshReply: CheckedContinuation<(Data, HTTPURLResponse), Never>?
    private var refreshURL: URL?
    var isRefreshing: Bool { refreshReply != nil }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("grant_type=refresh_token") {
            refreshURL = request.url
            return await withCheckedContinuation { refreshReply = $0 }
        }
        return response(token: "new-account", url: request.url!)
    }
    func finishRefresh() {
        refreshReply?.resume(returning: response(token: "old-account", url: refreshURL!))
        refreshReply = nil
    }
    private func response(token: String, url: URL) -> (Data, HTTPURLResponse) {
        let data = Data("{\"access_token\":\"\(token)\",\"refresh_token\":\"refresh\",\"expires_in\":3600,\"scope\":\"user-read-playback-state\"}".utf8)
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
struct PlayerReliabilityTests {
    @Test func previousRestrictionIsNotMisreportedAsMissingPremiumAndIsNotRetried() async throws {
        let transport = StubTransport([.init(status: 403, json: #"{"error":{"status":403,"message":"Player command failed: Restriction violated","reason":"UNKNOWN"}}"#)])
        let api = SpotifyAPIClient(auth: FakeAuthorization(), transport: transport)
        do {
            _ = try await api.execute(.previous, deviceID: "mac")
            Issue.record("Expected a playback restriction")
        } catch let error as SpotifyAPIError {
            guard case .playbackRefused(let path, let reason) = error else { Issue.record("Lost Spotify's refusal"); return }
            #expect(path == "/me/player/previous")
            #expect(reason == .restricted)
            #expect(error.localizedDescription.contains("Previous"))
            #expect(!error.localizedDescription.contains("Premium"))
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func knownRefusalsAreSpecificAndUnknownServerContentCannotLeakIntoErrors() {
        for reason in [SpotifyPlaybackRefusal.premiumRequired, .insufficientScope, .noActiveDevice] {
            let data = Data("{\"error\":{\"reason\":\"\(reason.rawValue)\"}}".utf8)
            #expect(SpotifyPlaybackRefusal.decode(data) == reason)
        }
        let unknown = SpotifyPlaybackRefusal.decode(Data(#"{"error":{"message":"sensitive-server-data","reason":"secret-value"}}"#.utf8))
        #expect(unknown == .unspecified)
        #expect(!unknown.message(path: "/me/player/previous").contains("sensitive-server-data"))
        #expect(SpotifyPlaybackRefusal.decode(Data("Forbidden".utf8)) == .unspecified)
    }

    @Test func playbackPollingRecoversAfterAnOfflineStartup() async throws {
        let api = FakeSpotify()
        api.profileError = URLError(.notConnectedToInternet)
        let (store, _, _, _, _) = try await StoreTests().fixture(api: api, accountRetryDelay: 0)
        #expect(!store.authState.isLoggedIn)
        #expect(store.latestError != nil)
        api.profileError = nil
        await store.refreshPlayback()
        #expect(store.authState.isLoggedIn)
        #expect(store.latestError == nil)
        #expect(api.profileReads == 2)
    }

    @Test func permanentAccountFailuresAndLogoutNeverSilentlyReconnect() async throws {
        let api = FakeSpotify()
        api.profileError = SpotifyAPIError.unauthorized
        let (store, _, _, _, _) = try await StoreTests().fixture(api: api, accountRetryDelay: 0)
        api.profileError = nil
        await store.refreshPlayback()
        #expect(!store.authState.isLoggedIn)
        #expect(api.profileReads == 1)

        api.profileError = URLError(.notConnectedToInternet)
        await store.refreshAuthState()
        store.logout()
        api.profileError = nil
        await store.refreshPlayback()
        #expect(!store.authState.isLoggedIn)
        #expect(api.profileReads == 2)
    }

    @Test func accountRetriesRespectBackoffAndCoalesceConcurrentPolls() async throws {
        let api = FakeSpotify()
        api.profileError = SpotifyAPIError.rateLimited(60)
        let (store, _, _, _, _) = try await StoreTests().fixture(api: api, accountRetryDelay: 0)
        api.profileError = nil
        await store.refreshPlayback()
        #expect(api.profileReads == 1)

        api.profileError = URLError(.timedOut)
        await store.refreshAuthState()
        api.profileError = nil
        api.holdProfile = true
        let retry = Task { await store.refreshPlayback() }
        while api.profileReply == nil { await Task.yield() }
        await store.refreshPlayback()
        #expect(api.profileReads == 3)
        api.profileReply?.resume(returning: SpotifyUserProfile(id: "alice", displayName: "Alice"))
        await retry.value
        #expect(store.authState.isLoggedIn)
    }

    @Test(arguments: [false, true])
    func cancelledRestoreKeepsItsRecoveryPending(cancelTask: Bool) async throws {
        let api = FakeSpotify()
        api.profileError = URLError(.notConnectedToInternet)
        let (store, _, _, _, _) = try await StoreTests().fixture(api: api, accountRetryDelay: 0)
        let originalError = store.latestError
        api.profileError = nil
        api.holdProfile = true
        let retry = Task { await store.refreshPlayback() }
        while api.profileReply == nil { await Task.yield() }
        if cancelTask { retry.cancel() }
        api.profileError = URLError(.cancelled)
        api.profileReply?.resume(returning: SpotifyUserProfile(id: "alice", displayName: "Alice"))
        await retry.value
        #expect(!store.authState.isLoggedIn)
        #expect(store.latestError == originalError)
        api.profileError = nil
        api.holdProfile = false
        await store.refreshPlayback()
        #expect(store.authState.isLoggedIn)
        #expect(api.profileReads == 3)
    }

    @Test(arguments: [false, true])
    func oldRefreshCannotReplaceANewSignIn(startDuringSignIn: Bool) async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = AppSettings(defaults: defaults)
        settings.spotifyClientID = String(repeating: "a", count: 32)
        let secrets = MemorySecrets()
        let old = SpotifyToken(accessToken: "expired", refreshToken: "refresh", scope: "", expiresAt: .distantPast)
        let key = "spotify.\(settings.spotifyClientID)."
        try secrets.write(JSONEncoder().encode(old), account: key)
        let transport = TokenRaceTransport()
        let receiver = HeldLoginReceiver()
        let auth = SpotifyAuthService(settings: settings, secrets: secrets, transport: transport, loginReceiver: receiver)

        var login: Task<Void, Error>?
        if startDuringSignIn {
            login = Task { try await auth.login() }
            while receiver.reply == nil { await Task.yield() }
        }
        let refresh = Task { try await auth.validAccessToken() }
        while !(await transport.isRefreshing) { await Task.yield() }
        if login == nil {
            login = Task { try await auth.login() }
            while receiver.reply == nil { await Task.yield() }
        }
        receiver.finish()
        try await login?.value
        await transport.finishRefresh()
        await #expect(throws: CancellationError.self) { _ = try await refresh.value }
        #expect(try auth.currentToken()?.accessToken == "new-account")
        let storedData = try #require(try secrets.read(account: key))
        let stored = try JSONDecoder().decode(SpotifyToken.self, from: storedData)
        #expect(stored.accessToken == "new-account")
    }

    @Test func transportButtonsAddressTheSelectedSpotifyDevice() async throws {
        let actions: [SpotifyAction] = [.pause, .resume, .next, .previous, .shuffle(true), .shuffle(false), .repeatMode(.context)]
        let transport = StubTransport(actions.map { _ in .init(status: 204, json: "") })
        let api = SpotifyAPIClient(auth: FakeAuthorization(), transport: transport)
        for action in actions { _ = try await api.execute(action, deviceID: "chosen-device") }
        let requests = await transport.requests
        #expect(requests.count == actions.count)
        for request in requests {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            #expect(query?.first(where: { $0.name == "device_id" })?.value == "chosen-device")
        }
        #expect(requests[3].url?.path == "/v1/me/player/previous")
        #expect(requests[3].httpMethod == "POST")
        #expect(requests[4].url?.query?.contains("state=true") == true)
        #expect(requests[5].url?.query?.contains("state=false") == true)
    }

    @Test func seekCannotFollowTheSameSongOntoAnotherDevice() async throws {
        let transport = StubTransport([.init(status: 200, json: #"{"is_playing":true,"shuffle_state":false,"repeat_state":"off","device":{"id":"phone","name":"Phone","is_active":true},"item":{"uri":"spotify:track:song","name":"Song","artists":[],"duration_ms":180000}}"#)])
        let api = SpotifyAPIClient(auth: FakeAuthorization(), transport: transport)
        await #expect(throws: UserFacingError.self) {
            _ = try await api.execute(.seek(positionMS: 20000, trackURI: "spotify:track:song"), deviceID: "mac")
        }
        #expect(await transport.requests.count == 1)
    }
}
