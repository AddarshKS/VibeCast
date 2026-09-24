import Foundation
import Testing
@testable import VibeCast

actor StubTransport: HTTPTransport {
    struct Reply: Sendable {
        let status: Int
        let json: String
        var headers: [String: String] = [:]
    }
    var replies: [Reply]
    var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let reply = replies.removeFirst()
        return (Data(reply.json.utf8), HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                                    httpVersion: nil, headerFields: reply.headers)!)
    }
}

@MainActor
final class MemorySecrets: SecretStoring {
    var values: [String: Data] = [:]
    func read(account: String) throws -> Data? { values[account] }
    func write(_ data: Data, account: String) throws { values[account] = data }
    func remove(account: String) throws { values.removeValue(forKey: account) }
}

@MainActor
final class FakeAuthorization: SpotifyAuthorizing {
    var refreshes = 0
    var token = SpotifyToken(accessToken: "local-test-token", refreshToken: "refresh",
                             scope: "playlist-modify-private", expiresAt: .distantFuture)
    func validAccessToken(forceRefresh: Bool) async throws -> String {
        if forceRefresh { refreshes += 1 }
        return token.accessToken
    }
    func currentToken() throws -> SpotifyToken? { token }
}

@MainActor
final class ServiceTests {
    @Test func playbackDecodesOptionalContextAndConfirmsOnlyTheRequestedPlaylist() async throws {
        let transport = StubTransport([
            .init(status: 200, json: #"{"is_playing":true,"shuffle_state":false,"repeat_state":"off","context":{"type":"playlist","uri":"spotify:playlist:chosen"}}"#),
            .init(status: 200, json: #"{"is_playing":true,"shuffle_state":false,"repeat_state":"off","context":null}"#),
            .init(status: 200, json: #"{"is_playing":true,"shuffle_state":false,"repeat_state":"off"}"#)
        ])
        let api = SpotifyAPIClient(auth: FakeAuthorization(), transport: transport)
        let playlist = SpotifyResolvedPlaylist(uri: "spotify:playlist:chosen", name: "Chosen", ownerName: nil, description: nil)
        let matching = try await api.playback()
        #expect(PlaybackConfirmation.matches(.playResolvedPlaylist(playlist), before: nil, after: matching))
        for _ in 0..<2 {
            let missing = try await api.playback()
            #expect(missing?.context == nil)
            #expect(!PlaybackConfirmation.matches(.playResolvedPlaylist(playlist), before: nil, after: missing))
        }
    }

    @Test func namedTransferUsesPinnedDeviceIDAndPreservesStartPlayback() async throws {
        let transport = StubTransport([
            .init(status: 200, json: #"{"devices":[{"id":"other","name":"Phone","is_active":false},{"id":"selected","name":"Renamed Phone","is_active":false}]}"#),
            .init(status: 204, json: "")
        ])
        let api = SpotifyAPIClient(auth: FakeAuthorization(), transport: transport)
        _ = try await api.execute(.transferPlayback(deviceName: "Phone"), deviceID: "selected")
        let requests = await transport.requests
        #expect(requests.count == 2)
        let data = try #require(requests.last?.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["device_ids"] as? [String] == ["selected"])
        #expect(body["play"] as? Bool == true)
    }

    @Test func disappearedTransferTargetCannotFallBackToAnotherSameNamedDevice() async throws {
        let transport = StubTransport([
            .init(status: 200, json: #"{"devices":[{"id":"other","name":"Phone","is_active":false}]}"#)
        ])
        let api = SpotifyAPIClient(auth: FakeAuthorization(), transport: transport)
        await #expect(throws: SpotifyAPIError.self) {
            _ = try await api.execute(.transferPlayback(deviceName: "Phone"), deviceID: "selected")
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func testCurrentPlaylistEndpointsPrivateAndIdempotentWrite() async throws {
        let transport = StubTransport([
            .init(status: 201, json: #"{"id":"playlistID","uri":"spotify:playlist:playlistID","name":"Night Drive"}"#),
            .init(status: 200, json: #"{"snapshot_id":"saved"}"#)
        ])
        let api = SpotifyAPIClient(auth: FakeAuthorization(), transport: transport)
        let playlist = try await api.createPlaylist(name: "Night Drive", description: "For the road")
        let track = SpotifyResolvedTrack(uri: "spotify:track:0000000000000000000001", title: "Song", artist: "Artist")
        try await api.setPlaylistTracks(playlist, tracks: [track])
        let requests = await transport.requests
        #expect((requests.map { $0.url!.path }) == (["/v1/me/playlists", "/v1/playlists/playlistID/items"]))
        #expect((requests.map(\.httpMethod)) == (["POST", "PUT"]))
        let body = try #require(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
        #expect((body["public"] as? Bool) == (false))
    }

    @Test func test401RefreshOnceAndNeverBlindlyRetryCreation() async throws {
        let auth = FakeAuthorization()
        let transport = StubTransport([
            .init(status: 401, json: "{}"), .init(status: 200, json: #"{"id":"alice"}"#)
        ])
        let api = SpotifyAPIClient(auth: auth, transport: transport)
        _ = try await api.profile()
        #expect((auth.refreshes) == (1))
        let failing = StubTransport([.init(status: 503, json: "{}")])
        let other = SpotifyAPIClient(auth: auth, transport: failing)
        do { _ = try await other.createPlaylist(name: "Test", description: ""); Issue.record("Expected failure") }
        catch {}
        let requests = await failing.requests
        #expect((requests.count) == (1))
    }

    @Test func testSearchHandlesNullEntriesAndClampsLimit() async throws {
        let transport = StubTransport([.init(status: 200, json: #"{"tracks":{"items":[null,{"uri":"spotify:track:a","name":"A","artists":[{"name":"B"}],"is_playable":true}]}}"#)])
        let api = SpotifyAPIClient(auth: FakeAuthorization(), transport: transport)
        let values = try await api.searchTrackCandidates(query: "A", limit: 80)
        #expect((values.count) == (1))
        let requests = await transport.requests
        #expect(requests[0].url!.absoluteString.contains("limit=10"))
    }

    @Test func testCallbackRejectsWrongStateHostAndDuplicateCodes() async throws {
        let valid = URL(string: "http://127.0.0.1:43821/callback?state=abc&code=ok")!
        #expect((try SpotifyAuthService.authorizationCode(url: valid, expectedState: "abc")) == ("ok"))
        #expect(throws: (any Error).self) { _ = try SpotifyAuthService.authorizationCode(url: valid, expectedState: "wrong") }
        #expect(throws: (any Error).self) { _ = try SpotifyAuthService.authorizationCode(url: URL(string: "http://evil.test:43821/callback?state=abc&code=ok")!, expectedState: "abc") }
        #expect(throws: (any Error).self) { _ = try SpotifyAuthService.authorizationCode(url: URL(string: "http://127.0.0.1:43821/callback?state=abc&code=a&code=b")!, expectedState: "abc") }
        #expect(LoopbackLogin.callbackURL(header: "GET /callback?state=abc&code=ok HTTP/1.1\r\nHost: 127.0.0.1:43821\r\n\r\n", state: "abc") != nil)
        #expect(LoopbackLogin.callbackURL(header: "GET /callback?state=wrong&code=ok HTTP/1.1\r\nHost: 127.0.0.1:43821\r\n\r\n", state: "abc") == nil)
    }

    @Test func testRefreshCoalescesAndPreservesScopes() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = AppSettings(defaults: defaults)
        let secrets = MemorySecrets()
        let old = SpotifyToken(accessToken: "expired", refreshToken: "refresh", scope: "playlist-modify-private", expiresAt: .distantPast)
        try secrets.write(JSONEncoder().encode(old), account: "spotify..")
        let transport = StubTransport([.init(status: 200, json: #"{"access_token":"fresh","expires_in":3600}"#)])
        let auth = SpotifyAuthService(settings: settings, secrets: secrets, transport: transport)
        async let first = auth.validAccessToken()
        async let second = auth.validAccessToken()
        let values = try await [first, second]
        #expect((values) == (["fresh", "fresh"]))
        let requests = await transport.requests
        #expect((requests.count) == (1))
        #expect((try auth.currentToken()?.scope) == ("playlist-modify-private"))
        #expect((try auth.currentToken()?.refreshToken) == ("refresh"))
    }

    @Test func testAIRequestContainsOnlyPromptAndHandlesRefusal() async throws {
        let data = try PlaylistPlanner.openAIRequest(prompt: "Soft rock for the evening", model: "test-model")
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((body["input"] as? String) == ("Soft rock for the evening"))
        #expect((body["store"] as? Bool) == (false))
        #expect(body["tools"] == nil)
        #expect(throws: (any Error).self) { _ = try PlaylistPlanner.decodeOpenAIResponse(Data(#"{"status":"incomplete","output":[]}"#.utf8)) }
    }

    @Test func testServiceAddressRejectsCredentialsAndInsecureRemote() async {
        #expect(AppConfig.serviceURL("http://example.com") == nil)
        #expect(AppConfig.serviceURL("https://user:password@example.com") == nil)
        #expect(AppConfig.serviceURL("https://example.com/path?token=secret") == nil)
        #expect(AppConfig.serviceURL("https://service.example.com") != nil)
    }
}
