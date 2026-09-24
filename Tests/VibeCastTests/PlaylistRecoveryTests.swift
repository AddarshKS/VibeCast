import Foundation
import Testing
@testable import VibeCast

@MainActor
struct PlaylistRecoveryTests {
    private let first = SpotifyResolvedTrack(uri: "spotify:track:0000000000000000000001", title: "First", artist: "Artist")
    private let second = SpotifyResolvedTrack(uri: "spotify:track:0000000000000000000002", title: "Second", artist: "Artist")
    private let playlist = SpotifyResolvedPlaylist(uri: "spotify:playlist:created", name: "Night Drive", ownerName: nil, description: nil)

    private func attempt() -> PlaylistCreationAttempt {
        .init(accountID: "alice", name: "Night Drive", description: "For the road", tracks: [first, second])
    }

    private func authorization() -> FakeAuthorization {
        let auth = FakeAuthorization()
        auth.token = SpotifyToken(accessToken: "local-test-token", refreshToken: nil,
                                  scope: "playlist-modify-private playlist-read-private", expiresAt: .distantFuture)
        return auth
    }

    private func json(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }

    private func metadata(id: String = "created", owner: String = "alice", isPublic: Bool = false,
                          description: String = "For the road", snapshot: String = "saved") -> [String: Any] {
        ["id": id, "uri": "spotify:playlist:\(id)", "name": "Night Drive", "owner": ["id": owner],
         "public": isPublic, "description": description, "snapshot_id": snapshot]
    }

    private func page(items: [[String: Any]], offset: Int = 0, total: Int? = nil, next: Bool = false) throws -> String {
        try json(["items": items, "offset": offset, "total": total ?? items.count,
                  "next": next ? "https://untrusted.invalid/never-follow-this" as Any : NSNull()])
    }

    @Test func journalRoundTripsAndPreservesUniqueMarkerWithinSpotifyLimit() throws {
        let value = PlaylistCreationAttempt(accountID: "alice", name: "Night Drive",
                                            description: String(repeating: "A", count: 500), tracks: [first, second],
                                            createdAt: .distantPast)
        let copy = try JSONDecoder().decode(PlaylistCreationAttempt.self, from: JSONEncoder().encode(value))
        #expect(copy == value)
        #expect(copy.tracks == [first, second])
        #expect(value.spotifyDescription.count == 300)
        #expect(value.matches(description: value.spotifyDescription))
        #expect(!value.matches(description: value.spotifyDescription + " copied"))
        #expect(!value.matches(description: attempt().spotifyDescription))
    }

    @Test func lookupPaginatesOwnPlaylistsAndNeverPostsOrFollowsNextURL() async throws {
        let value = attempt()
        let transport = StubTransport([
            .init(status: 200, json: #"{"id":"alice"}"#),
            .init(status: 200, json: try page(items: [metadata(id: "followed", owner: "bob", description: value.spotifyDescription)], total: 2, next: true)),
            .init(status: 200, json: try page(items: [metadata(description: value.spotifyDescription)], offset: 1, total: 2)),
            .init(status: 200, json: #"{"id":"alice"}"#)
        ])
        let api = SpotifyAPIClient(auth: authorization(), transport: transport)
        let found = try await api.findCreatedPlaylist(for: value)
        #expect(found?.uri == playlist.uri)
        let requests = await transport.requests
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.url?.host == "api.spotify.com" })
        #expect(requests.map { $0.url!.path } == ["/v1/me", "/v1/me/playlists", "/v1/me/playlists", "/v1/me"])
        #expect(URLComponents(url: requests[2].url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(.init(name: "offset", value: "1")) == true)
    }

    @Test func noMatchStaysReadOnlyAndNeverMatchesANameAlone() async throws {
        let transport = StubTransport([
            .init(status: 200, json: #"{"id":"alice"}"#),
            .init(status: 200, json: try page(items: [metadata()])),
            .init(status: 200, json: #"{"id":"alice"}"#)
        ])
        let api = SpotifyAPIClient(auth: authorization(), transport: transport)
        #expect(try await api.findCreatedPlaylist(for: attempt()) == nil)
        #expect(await transport.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func duplicateOwnedMarkersAreNotChosenArbitrarily() async throws {
        let value = attempt()
        let transport = StubTransport([
            .init(status: 200, json: #"{"id":"alice"}"#),
            .init(status: 200, json: try page(items: [metadata(description: value.spotifyDescription), metadata(id: "duplicate", description: value.spotifyDescription)]))
        ])
        let api = SpotifyAPIClient(auth: authorization(), transport: transport)
        await #expect(throws: PlaylistRecoveryError.ambiguousCreation) { _ = try await api.findCreatedPlaylist(for: value) }
        #expect(await transport.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func incompletePaginationDoesNotClaimThatNoPlaylistExists() async throws {
        let transport = StubTransport([
            .init(status: 200, json: #"{"id":"alice"}"#),
            .init(status: 200, json: try page(items: [], total: 1))
        ])
        let api = SpotifyAPIClient(auth: authorization(), transport: transport)
        await #expect(throws: PlaylistRecoveryError.incompleteLookup) { _ = try await api.findCreatedPlaylist(for: attempt()) }
    }

    @Test func lookupRequiresReadScopeAndTheOriginalAccount() async throws {
        let missingScope = StubTransport([])
        let oldAuth = FakeAuthorization()
        oldAuth.token = SpotifyToken(accessToken: "old-test-token", refreshToken: nil, scope: "playlist-modify-private", expiresAt: .distantFuture)
        let firstAPI = SpotifyAPIClient(auth: oldAuth, transport: missingScope)
        await #expect(throws: PlaylistRecoveryError.missingReadAccess) { _ = try await firstAPI.findCreatedPlaylist(for: attempt()) }
        #expect(await missingScope.requests.isEmpty)

        let differentAccount = StubTransport([.init(status: 200, json: #"{"id":"bob"}"#)])
        let secondAPI = SpotifyAPIClient(auth: authorization(), transport: differentAccount)
        await #expect(throws: PlaylistRecoveryError.accountChanged) { _ = try await secondAPI.findCreatedPlaylist(for: attempt()) }
        #expect(await differentAccount.requests.count == 1)
    }

    @Test func readbackConfirmsOrderAcrossPagesAndSupportsRelinkedTracks() async throws {
        let metadataJSON = try json(metadata())
        let transport = StubTransport([
            .init(status: 200, json: #"{"id":"alice"}"#),
            .init(status: 200, json: metadataJSON),
            .init(status: 200, json: try page(items: [["item": ["uri": first.uri]]], total: 2, next: true)),
            .init(status: 200, json: try page(items: [["track": ["uri": "spotify:track:relinked", "linked_from": ["uri": second.uri]]]], offset: 1, total: 2)),
            .init(status: 200, json: metadataJSON),
            .init(status: 200, json: #"{"id":"alice"}"#)
        ])
        let api = SpotifyAPIClient(auth: authorization(), transport: transport)
        try await api.verifyPlaylist(playlist, tracks: [first, second], accountID: "alice")
        let requests = await transport.requests
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.url?.host == "api.spotify.com" })
        #expect(requests[2].url?.path == "/v1/playlists/created/items")
        #expect(URLComponents(url: requests[3].url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(.init(name: "offset", value: "1")) == true)
    }

    @Test(arguments: ["order", "missing", "null", "public", "owner", "snapshot", "changedAccount"])
    func readbackNeverReportsSuccessForMismatches(scenario: String) async throws {
        let initial = metadata(owner: scenario == "owner" ? "bob" : "alice", isPublic: scenario == "public")
        var items: [[String: Any]] = [["item": ["uri": first.uri]], ["item": ["uri": second.uri]]]
        if scenario == "order" { items.reverse() }
        if scenario == "missing" { items.removeLast() }
        if scenario == "null" { items[0] = ["item": NSNull(), "track": ["uri": first.uri]] }
        let transport = StubTransport([
            .init(status: 200, json: #"{"id":"alice"}"#),
            .init(status: 200, json: try json(initial)),
            .init(status: 200, json: try page(items: items)),
            .init(status: 200, json: try json(metadata(snapshot: scenario == "snapshot" ? "changed" : "saved"))),
            .init(status: 200, json: scenario == "changedAccount" ? #"{"id":"bob"}"# : #"{"id":"alice"}"#)
        ])
        let api = SpotifyAPIClient(auth: authorization(), transport: transport)
        await #expect(throws: PlaylistRecoveryError.self) {
            try await api.verifyPlaylist(playlist, tracks: [first, second], accountID: "alice")
        }
        #expect(await transport.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    @Test func uncertainCreationDoesNotAutomaticallyRetryAPost() async throws {
        let value = attempt()
        let transport = StubTransport([.init(status: 503, json: "{}")])
        let api = SpotifyAPIClient(auth: authorization(), transport: transport)
        await #expect(throws: SpotifyAPIError.self) { _ = try await api.createPlaylist(name: value.name, description: value.spotifyDescription) }
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests[0].httpMethod == "POST")
        let body = try #require(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
        #expect(body["description"] as? String == value.spotifyDescription)
        #expect(body["public"] as? Bool == false)
    }
}
