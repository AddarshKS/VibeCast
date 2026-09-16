import Foundation
import Testing
@testable import VibeCast

@MainActor
struct SeekTests {
    private let playback = #"{"is_playing":true,"shuffle_state":false,"repeat_state":"off","progress_ms":5000,"device":{"id":"mac","name":"Mac","is_active":true,"is_restricted":false},"item":{"uri":"spotify:track:song","name":"Song","artists":[],"duration_ms":180000}}"#

    @Test func seekUsesTimestampAndActiveDeviceWithoutReplacingContext() async throws {
        let transport = StubTransport([.init(status: 200, json: playback), .init(status: 204, json: "")])
        let client = SpotifyAPIClient(auth: FakeAuthorization(), transport: transport)
        _ = try await client.execute(.seek(positionMS: 45000, trackURI: "spotify:track:song"))
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[1].httpMethod == "PUT")
        #expect(requests[1].url?.path == "/v1/me/player/seek")
        let query = URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.contains(URLQueryItem(name: "position_ms", value: "45000")) == true)
        #expect(query?.contains(URLQueryItem(name: "device_id", value: "mac")) == true)
        #expect(requests[1].httpBody == nil)
    }

    @Test func staleLyricsAndOutOfRangeTimesNeverSeekOrSkip() async throws {
        for (position, uri) in [(-1, "spotify:track:song"), (180000, "spotify:track:song"),
                                (Int.max, "spotify:track:song"), (1000, "spotify:track:old")] {
            let transport = StubTransport([.init(status: 200, json: playback)])
            let client = SpotifyAPIClient(auth: FakeAuthorization(), transport: transport)
            await #expect(throws: UserFacingError.self) { _ = try await client.execute(.seek(positionMS: position, trackURI: uri)) }
            #expect(await transport.requests.count == 1)
        }
    }

    @Test func unavailablePlaybackNeverSeeks() async throws {
        let transport = StubTransport([.init(status: 204, json: "")])
        let client = SpotifyAPIClient(auth: FakeAuthorization(), transport: transport)
        await #expect(throws: UserFacingError.self) { _ = try await client.execute(.seek(positionMS: 1000, trackURI: "spotify:track:song")) }
        #expect(await transport.requests.count == 1)
    }

    @Test func pausedSeekDoesNotResumeAndRestrictedSeekDoesNotWrite() async throws {
        let paused = playback.replacingOccurrences(of: #""is_playing":true"#, with: #""is_playing":false"#)
        let transport = StubTransport([.init(status: 200, json: paused), .init(status: 204, json: "")])
        let client = SpotifyAPIClient(auth: FakeAuthorization(), transport: transport)
        _ = try await client.execute(.seek(positionMS: 1000, trackURI: "spotify:track:song"))
        #expect(await transport.requests.map { $0.url!.path } == ["/v1/me/player", "/v1/me/player/seek"])
        let restricted = playback.replacingOccurrences(of: #""is_restricted":false"#, with: #""is_restricted":true"#)
        let blocked = StubTransport([.init(status: 200, json: restricted)])
        let blockedClient = SpotifyAPIClient(auth: FakeAuthorization(), transport: blocked)
        await #expect(throws: UserFacingError.self) { _ = try await blockedClient.execute(.seek(positionMS: 1000, trackURI: "spotify:track:song")) }
        #expect(await blocked.requests.count == 1)
    }

    @Test func queueAdvanceOnlyUsesNextOnPinnedDevice() async throws {
        let transport = StubTransport([.init(status: 204, json: "")])
        let client = SpotifyAPIClient(auth: FakeAuthorization(), transport: transport)
        _ = try await client.execute(.advanceQueue(trackURI: "spotify:track:chosen", deviceID: "mac"))
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests[0].httpMethod == "POST")
        #expect(requests[0].url?.path == "/v1/me/player/next")
        #expect(requests[0].httpBody == nil)
        #expect(requests[0].url?.query == "device_id=mac")
    }
}
