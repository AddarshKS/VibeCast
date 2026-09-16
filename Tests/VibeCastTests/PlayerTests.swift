import Foundation
import Testing
@testable import VibeCast

struct FixedLyrics: LyricsServing {
    func lyrics(for track: SpotifyTrack) async throws -> Lyrics {
        .text("An open road\nA quiet sky\nThe evening takes its time\n\nA little light\nA passing train\nAnd we are home again")
    }
}

actor HeldLyrics: LyricsServing {
    var requests = 0
    var reply: CheckedContinuation<Lyrics, Never>?
    func lyrics(for track: SpotifyTrack) async throws -> Lyrics {
        requests += 1
        return await withCheckedContinuation { reply = $0 }
    }
    func finish() { reply?.resume(returning: .text("Old song")); reply = nil }
}

@MainActor
struct PlayerTests {
    static let track = SpotifyTrack(uri: "spotify:track:test", name: "Evening Light", artists: [.init(name: "The Test Band")],
                                    album: SpotifyAlbum(images: nil, name: "After Hours"), isPlayable: true, durationMS: 213000)

    @Test func queueUsesOfficialEndpointAndHandlesEpisodesNullsAndDuplicates() async throws {
        let transport = StubTransport([.init(status: 200, json: #"{"queue":[null,{"uri":"spotify:track:one","name":"One","artists":[{"name":"Artist"}]},{"uri":"spotify:episode:two","name":"Two","show":{"name":"Show"}},{"uri":"spotify:track:one","name":"One","artists":[]}]}"#)])
        let client = SpotifyAPIClient(auth: FakeAuthorization(), transport: transport)
        let queue = try await client.queue()
        #expect(queue.count == 3)
        #expect(queue[1].subtitle == "Show")
        #expect(queue[1].spotifyURL?.absoluteString == "https://open.spotify.com/episode/two")
        let requests = await transport.requests
        #expect(requests.first?.httpMethod == "GET")
        #expect(requests.first?.url?.path == "/v1/me/player/queue")
    }

    @Test func lyricsSendOnlySongMetadataAndHandleUnavailableOrInstrumental() async throws {
        let transport = StubTransport([
            .init(status: 200, json: #"{"instrumental":false,"plainLyrics":"Test lyrics"}"#),
            .init(status: 404, json: "{}"),
            .init(status: 200, json: #"{"instrumental":true,"plainLyrics":null}"#)
        ])
        let client = LyricsClient(transport: transport)
        #expect(try await client.lyrics(for: Self.track) == .text("Test lyrics"))
        #expect(try await client.lyrics(for: Self.track) == .unavailable)
        #expect(try await client.lyrics(for: Self.track) == .instrumental)
        let request = try #require(await transport.requests.first)
        #expect(request.url?.host == "lrclib.net")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(Set(query.map(\.name)) == ["track_name", "artist_name", "album_name", "duration"])
        #expect(query.first(where: { $0.name == "duration" })?.value == "213.0")
    }

    @Test func noLyricsLookupWithoutConsentAndLateResponseCannotRestoreClearedData() async throws {
        let held = HeldLyrics()
        let details = PlayerDetailsStore(spotify: FakeSpotify(), lyrics: held)
        await details.loadLyrics(for: Self.track, enabled: false)
        #expect(await held.requests == 0)
        let task = Task { await details.loadLyrics(for: Self.track, enabled: true) }
        while await held.reply == nil { await Task.yield() }
        details.reset()
        await held.finish()
        await task.value
        guard case .idle = details.lyrics else { Issue.record("Late lyrics restored cleared data"); return }
    }

    @Test func disablingLyricsInvalidatesAnInflightLookup() async {
        let held = HeldLyrics()
        let details = PlayerDetailsStore(spotify: FakeSpotify(), lyrics: held)
        let task = Task { await details.loadLyrics(for: Self.track, enabled: true) }
        while await held.reply == nil { await Task.yield() }
        await details.loadLyrics(for: Self.track, enabled: false)
        await held.finish()
        await task.value
        guard case .idle = details.lyrics else { Issue.record("Disabled lyrics reappeared"); return }
    }

    @Test func lyricsPreferenceIsOptInAndPersistent() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = AppSettings(defaults: defaults)
        #expect(!settings.lyricsEnabled)
        settings.lyricsEnabled = true
        #expect(AppSettings(defaults: defaults).lyricsEnabled)
    }

    @Test func reopeningLyricsUsesCurrentSongCacheButRefreshConsentAndResetInvalidateIt() async throws {
        let transport = StubTransport((0..<4).map { _ in .init(status: 200, json: #"{"instrumental":false,"plainLyrics":"Test lyrics"}"#) })
        let details = PlayerDetailsStore(spotify: FakeSpotify(), lyrics: LyricsClient(transport: transport))
        await details.loadLyrics(for: Self.track, enabled: true)
        await details.loadLyrics(for: Self.track, enabled: true)
        #expect(await transport.requests.count == 1)
        await details.loadLyrics(for: Self.track, enabled: true, force: true)
        #expect(await transport.requests.count == 2)
        await details.loadLyrics(for: Self.track, enabled: false)
        await details.loadLyrics(for: Self.track, enabled: true)
        #expect(await transport.requests.count == 3)
        details.reset()
        await details.loadLyrics(for: Self.track, enabled: true)
        #expect(await transport.requests.count == 4)
    }

    @Test func playbackDecodesProgressAndDuration() throws {
        let data = Data(#"{"is_playing":true,"shuffle_state":false,"repeat_state":"off","progress_ms":42000,"item":{"uri":"spotify:track:t","name":"Test","artists":[],"duration_ms":180000,"album":{"name":"Album"}}}"#.utf8)
        let value = try JSONDecoder().decode(SpotifyPlayback.self, from: data)
        #expect(value.progressMS == 42000)
        #expect(value.item?.durationMS == 180000)
        #expect(value.item?.album?.name == "Album")
        let observed = Date()
        #expect(value.elapsedMS(observedAt: observed, now: observed.addingTimeInterval(3)) == 45000)
        #expect(value.elapsedMS(observedAt: observed, now: observed.addingTimeInterval(999)) == 180000)
        #expect(value.elapsedMS(observedAt: observed, now: observed.addingTimeInterval(-10)) == 42000)
    }

    @Test func queueErrorCanRetryAndLateReplyCannotRestoreLoggedOutData() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.queueFailure = true
        await store.playerDetails.refreshQueue()
        guard case .failed = store.playerDetails.queue else { Issue.record("Missing queue failure"); return }
        #expect(store.latestError == nil)
        api.queueFailure = false
        await store.playerDetails.refreshQueue()
        guard case .loaded(let items) = store.playerDetails.queue else { Issue.record("Retry failed"); return }
        #expect(items.isEmpty)
        api.holdQueue = true
        let task = Task { await store.playerDetails.refreshQueue() }
        while api.queueReply == nil { await Task.yield() }
        store.logout()
        api.queueReply?.resume(returning: [])
        await task.value
        guard case .idle = store.playerDetails.queue else { Issue.record("Logged-out queue reappeared"); return }
    }

    @Test func lyricsFailuresAreNotConfusedWithMissingLyrics() async throws {
        let client = LyricsClient(transport: StubTransport([.init(status: 503, json: "{}")]))
        await #expect(throws: UserFacingError.self) { _ = try await client.lyrics(for: Self.track) }
    }

    @Test func episodesDoNotLeaveThePreviousSongOrLyricsOnscreen() throws {
        let data = Data(#"{"is_playing":true,"shuffle_state":false,"repeat_state":"off","item":{"uri":"spotify:episode:e","name":"Episode","type":"episode"}}"#.utf8)
        let value = try JSONDecoder().decode(SpotifyPlayback.self, from: data)
        #expect(value.item == nil)
        #expect(value.isPlaying)
    }
}
