import Foundation
import Testing
@testable import VibeCast

@MainActor
struct TimedPlayerTests {
    @Test func timestampsHandleFractionsMultipleTagsOffsetsAndInstrumentalGaps() throws {
        let lyrics = try #require(TimedLyrics(lrc: "[ar:Artist]\n[offset:100]\n[00:01.5][00:05.250]First\n[00:03.00]\n[00:08.01]Last\n[00:05.250]Translation\ninvalid"))
        #expect(lyrics.lines.map(\.timeMS) == [1400, 2900, 5150, 7910])
        #expect(lyrics.lines[1].text.isEmpty)
        #expect(lyrics.lines[2].text == "First\nTranslation")
        #expect(lyrics.activeLine(at: 0) == nil)
        #expect(lyrics.activeLine(at: 1400) == 1400)
        #expect(lyrics.activeLine(at: 5100) == 2900)
        #expect(lyrics.activeLine(at: 6000) == 5150)
        #expect(lyrics.activeLine(at: 2000) == 1400)
        #expect(lyrics.activeLine(at: 9000) == 7910)
    }

    @Test func invalidTimestampsAndUntrustedOffsetsAreSafe() {
        #expect(TimedLyrics(lrc: "[00:99.00]Invalid") == nil)
        #expect(TimedLyrics(lrc: "[00:01.00]\n[00:02.00]") == nil)
        #expect(TimedLyrics(lrc: "[offset:-9223372036854775808]\n[00:01.00]Safe")?.lines.first?.timeMS == 1000)
        #expect(TimedLyrics(lrc: "[00:01.00]One\n[00:01.00]One")?.lines.count == 1)
    }

    @Test func providerPrefersTimingAndFallsBackWhenItIsMalformed() async throws {
        let transport = StubTransport([
            .init(status: 200, json: #"{"instrumental":false,"plainLyrics":"Plain","syncedLyrics":"[00:01.00]Timed"}"#),
            .init(status: 200, json: #"{"instrumental":false,"plainLyrics":"Plain","syncedLyrics":"bad"}"#)
        ])
        let provider = LyricsClient(transport: transport)
        guard case .synced(let result) = try await provider.lyrics(for: PlayerTests.track) else {
            Issue.record("Expected timed lyrics"); return
        }
        #expect(result.lines.first?.text == "Timed")
        #expect(try await provider.lyrics(for: PlayerTests.track) == .text("Plain"))
    }

    @Test func pausedClockDoesNotAdvanceAndMissingPositionDoesNotInventProgress() {
        let now = Date()
        let paused = SpotifyPlayback(isPlaying: false, item: PlayerTests.track, device: nil,
                                      shuffleState: false, repeatState: "off", progressMS: 3000)
        #expect(paused.elapsedMS(observedAt: now, now: now.addingTimeInterval(10)) == 3000)
        let unknown = SpotifyPlayback(isPlaying: true, item: PlayerTests.track, device: nil,
                                       shuffleState: false, repeatState: "off")
        #expect(unknown.elapsedMS(observedAt: now, now: now.addingTimeInterval(10)) == 0)
    }

    @Test func deviceTransferUsesExactIDAndPreservesPlaybackState() async throws {
        let transport = StubTransport([
            .init(status: 200, json: #"{"devices":[{"id":"one","name":"Speaker","is_active":true},{"id":"two","name":"Speaker","is_active":false}]}"#),
            .init(status: 204, json: "")
        ])
        let client = SpotifyAPIClient(auth: FakeAuthorization(), transport: transport)
        _ = try await client.execute(.transferToDevice(SpotifyDevice(id: "two", name: "Speaker", isActive: false, isRestricted: false)))
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[1].url?.path == "/v1/me/player")
        let body = try #require(JSONSerialization.jsonObject(with: requests[1].httpBody!) as? [String: Any])
        #expect(body["device_ids"] as? [String] == ["two"])
        #expect(body["play"] as? Bool == false)
    }

    @Test func disappearedAndRestrictedDevicesCannotBeTransferred() async throws {
        for json in [#"{"devices":[]}"#, #"{"devices":[{"id":"two","name":"Speaker","is_active":false,"is_restricted":true}]}"#] {
            let transport = StubTransport([.init(status: 200, json: json)])
            let client = SpotifyAPIClient(auth: FakeAuthorization(), transport: transport)
            await #expect(throws: SpotifyAPIError.self) {
                _ = try await client.execute(.transferToDevice(SpotifyDevice(id: "two", name: "Speaker", isActive: false, isRestricted: false)))
            }
            #expect(await transport.requests.count == 1)
        }
    }

    @Test func contentSizingGrowsShrinksAndCapsToScreen() {
        #expect(PanelSizing.bodyHeight(content: 30, top: 230, bottom: 90, maximum: 680) == 30)
        #expect(PanelSizing.bodyHeight(content: 900, top: 230, bottom: 90, maximum: 680) == 360)
        #expect(PanelSizing.bodyHeight(content: 900, top: 230, bottom: 90, maximum: 500) == 180)
        #expect(PanelSizing.bodyHeight(content: 0, top: 230, bottom: 90, maximum: 680) == 0)
    }
}
