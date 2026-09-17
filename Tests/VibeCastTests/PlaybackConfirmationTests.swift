import Foundation
import Testing
@testable import VibeCast

@MainActor
struct PlaybackConfirmationTests {
    private func state(shuffle: Bool = false, uri: String = "spotify:track:old", progress: Int = 12000) -> SpotifyPlayback {
        SpotifyPlayback(isPlaying: true,
                        item: SpotifyTrack(uri: uri, name: "Song", artists: [], album: nil, isPlayable: true),
                        device: nil, shuffleState: shuffle, repeatState: "off", progressMS: progress)
    }

    @Test func delayedStateKeepsControlsPendingAndBurstSendsOneCommand() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = state()
        await store.refreshPlayback()
        api.holdPlayback = true
        store.control(.shuffle(true))
        while api.playbackReply == nil { await Task.yield() }
        for _ in 0..<20 { store.control(.next); store.control(.shuffle(true)) }
        #expect(store.pendingPlayerAction == .shuffle(true))
        #expect(store.isBusy)
        #expect(store.playback?.shuffleState == false)
        api.holdPlayback = false
        api.playbackReply?.resume(returning: state())
        await store.waitUntilIdle()
        #expect(api.actions == [.shuffle(true)])
        #expect(store.playback?.shuffleState == true)
        #expect(store.latestError == nil)
        #expect(store.pendingPlayerAction == nil)
    }

    @Test func unconfirmedSkipFailsWithoutResending() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = state()
        api.applyControls = false
        await store.refreshPlayback()
        let reads = api.playbackReads
        store.control(.next)
        await store.waitUntilIdle()
        #expect(api.actions == [.next])
        #expect(api.playbackReads - reads == 6)
        #expect(store.latestError?.contains("hasn't confirmed") == true)
        #expect(!store.isBusy)
    }

    @Test func oldPollingResponseCannotOverwriteConfirmedControl() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = state()
        api.holdPlayback = true
        let refresh = Task { await store.refreshPlayback() }
        while api.playbackReply == nil { await Task.yield() }
        api.holdPlayback = false
        store.control(.shuffle(true))
        await store.waitUntilIdle()
        api.playbackReply?.resume(returning: state())
        await refresh.value
        #expect(store.playback?.shuffleState == true)
    }

    @Test func cancelledConfirmationCannotChangeStateAfterLogout() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.holdPlayback = true
        store.control(.shuffle(true))
        let completion = Task { await store.waitUntilIdle() }
        while api.playbackReply == nil { await Task.yield() }
        store.logout()
        api.playbackReply?.resume(returning: state(shuffle: true))
        await completion.value
        #expect(store.playback == nil)
        #expect(store.pendingPlayerAction == nil)
        #expect(!store.isBusy)
    }

    @Test func selectedQueueSongAdvancesWithoutReplacingPlayback() async throws {
        let item = try JSONDecoder().decode(SpotifyQueueItem.self, from: Data(#"{"uri":"spotify:track:chosen","name":"Chosen","artists":[{"name":"Artist"}]}"#.utf8))
        let other = try JSONDecoder().decode(SpotifyQueueItem.self, from: Data(#"{"uri":"spotify:track:first","name":"First"}"#.utf8))
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = SpotifyPlayback(isPlaying: true, item: PlayerTests.track,
            device: SpotifyDevice(id: "mac", name: "Mac", isActive: true, isRestricted: false), shuffleState: false, repeatState: "off")
        api.queueValue = [other, item]
        store.playQueueItem(at: 1, in: api.queueValue)
        store.playQueueItem(at: 1, in: api.queueValue)
        await store.waitUntilIdle()
        #expect(api.actions == [.advanceQueue(trackURI: other.uri, deviceID: "mac"), .advanceQueue(trackURI: item.uri, deviceID: "mac")])
        #expect(store.playback?.item?.uri == item.uri)
        #expect(store.latestError == nil)
        guard case .loaded(let queue) = store.playerDetails.queue else { Issue.record("Queue not refreshed"); return }
        #expect(queue.isEmpty)
        #expect(store.pendingQueueIndex == nil)
    }

    @Test func changedQueueDoesNotSendAnyPlaybackCommands() async throws {
        let item = try JSONDecoder().decode(SpotifyQueueItem.self, from: Data(#"{"uri":"spotify:track:chosen","name":"Chosen"}"#.utf8))
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = SpotifyPlayback(isPlaying: true, item: PlayerTests.track,
            device: SpotifyDevice(id: "mac", name: "Mac", isActive: true, isRestricted: false), shuffleState: false, repeatState: "off")
        store.playQueueItem(at: 0, in: [item])
        await store.waitUntilIdle()
        #expect(api.actions.isEmpty)
        #expect(store.latestError?.contains("queue or player changed") == true)
    }

    @Test func uncertainQueueStepStopsWithoutSkippingAgain() async throws {
        let items = try JSONDecoder().decode([SpotifyQueueItem].self, from: Data(#"[{"uri":"spotify:track:first","name":"First"},{"uri":"spotify:track:chosen","name":"Chosen"}]"#.utf8))
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = SpotifyPlayback(isPlaying: true, item: PlayerTests.track,
            device: SpotifyDevice(id: "mac", name: "Mac", isActive: true, isRestricted: false), shuffleState: false, repeatState: "off")
        api.queueValue = items
        api.applyControls = false
        store.playQueueItem(at: 1, in: items)
        await store.waitUntilIdle()
        #expect(api.actions == [.advanceQueue(trackURI: items[0].uri, deviceID: "mac")])
        #expect(store.latestError != nil)
        #expect(store.pendingQueueIndex == nil)
    }

    @Test func repeatedQueueTrackIsRejectedBeforeAnySkip() async throws {
        let item = try JSONDecoder().decode(SpotifyQueueItem.self, from: Data(#"{"uri":"spotify:track:chosen","name":"Chosen"}"#.utf8))
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = SpotifyPlayback(isPlaying: true, item: PlayerTests.track,
            device: SpotifyDevice(id: "mac", name: "Mac", isActive: true, isRestricted: false), shuffleState: false, repeatState: "off")
        api.queueValue = [item, item]
        store.playQueueItem(at: 1, in: api.queueValue)
        await store.waitUntilIdle()
        #expect(api.actions.isEmpty)
        #expect(store.latestError?.contains("repeated song") == true)
    }

    @Test func seekingRequiresCorrectSongAndObservedPosition() {
        let action = SpotifyAction.seek(positionMS: 40000, trackURI: "spotify:track:old")
        #expect(PlaybackConfirmation.matches(action, before: state(), after: state(progress: 41000)))
        #expect(!PlaybackConfirmation.matches(action, before: state(), after: state(progress: 12000)))
        #expect(!PlaybackConfirmation.matches(action, before: state(), after: state(uri: "spotify:track:new", progress: 40000)))
    }

    @Test func cancellingQueueBeforeFirstStepSendsNothing() async throws {
        let item = try JSONDecoder().decode(SpotifyQueueItem.self, from: Data(#"{"uri":"spotify:track:chosen","name":"Chosen"}"#.utf8))
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.holdPlayback = true
        store.playQueueItem(at: 0, in: [item])
        let completion = Task { await store.waitUntilIdle() }
        while api.playbackReply == nil { await Task.yield() }
        store.cancel()
        api.playbackReply?.resume(returning: state())
        await completion.value
        #expect(api.actions.isEmpty)
        #expect(store.pendingQueueIndex == nil)
        #expect(!store.showsRequestProgress)
    }

    @Test func queueRejectsUnavailableEpisodesAndMalformedURIs() throws {
        for json in [
            #"{"uri":"spotify:episode:abc","name":"Episode"}"#,
            #"{"uri":"spotify:track:abc","name":"Blocked","is_playable":false}"#,
            #"{"uri":"spotify:track:bad/uri","name":"Invalid"}"#
        ] {
            let item = try JSONDecoder().decode(SpotifyQueueItem.self, from: Data(json.utf8))
            #expect(item.playableTrack == nil)
        }
    }

    @Test func skipConfirmationRequiresTrackChangeOrRestart() {
        #expect(!PlaybackConfirmation.matches(.next, before: state(), after: state()))
        #expect(PlaybackConfirmation.matches(.next, before: state(), after: state(uri: "spotify:track:new")))
        #expect(PlaybackConfirmation.matches(.previous, before: state(), after: state(progress: 0)))
        #expect(!PlaybackConfirmation.matches(.next, before: state(), after: nil))
    }
}
