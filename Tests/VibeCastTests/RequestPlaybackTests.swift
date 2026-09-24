import Foundation
import Testing
@testable import VibeCast

@MainActor
struct RequestPlaybackTests {
    private let song = SpotifyResolvedTrack(uri: "spotify:track:0000000000000000000001", title: "Peace of Blood", artist: "Citadelle")
    private let mac = SpotifyDevice(id: "mac", name: "Mac", isActive: true, isRestricted: false)

    private func state(playing: Bool = true, track: SpotifyResolvedTrack? = nil,
                       device: SpotifyDevice? = nil, context: SpotifyPlayback.Context? = nil,
                       shuffle: Bool = false, repeatMode: String = "off") -> SpotifyPlayback {
        SpotifyPlayback(isPlaying: playing,
                        item: track.map { SpotifyTrack(uri: $0.uri, name: $0.title, artists: [.init(name: $0.artist)], album: nil, isPlayable: true) } ?? PlayerTests.track,
                        device: device ?? mac, shuffleState: shuffle, repeatState: repeatMode,
                        progressMS: 12000, context: context)
    }

    @Test(arguments: ["pause", "resume", "next", "previous", "shuffle on", "shuffle off", "repeat on", "repeat off", "repeat current song"])
    func typedControlsWaitForObservedStateAndDispatchOnce(prompt: String) async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        let before = state(playing: prompt != "resume", shuffle: prompt == "shuffle off",
                           repeatMode: prompt == "repeat off" ? "context" : "off")
        api.playbackValue = before
        api.onExecute = { _ in api.holdPlayback = true }
        store.prompt = prompt
        store.submitPrompt()
        while api.playbackReply == nil { await Task.yield() }
        #expect(store.isBusy && store.showsRequestProgress && !store.isPlayerControl)
        #expect(store.latestResult == nil)
        #expect(store.requestHistory.isEmpty)
        let reads = api.playbackReads
        await store.refreshPlayback()
        #expect(api.playbackReads == reads)
        store.submitPrompt()
        store.control(.next)
        api.holdPlayback = false
        api.playbackReply?.resume(returning: before)
        await store.waitUntilIdle()
        let expected = try #require(DirectCommandClassifier().action(for: prompt))
        #expect(api.actions == [expected])
        #expect(api.actionDeviceIDs == ["mac"])
        #expect(store.latestError == nil)
        #expect(store.latestResult != nil)
        #expect(store.requestHistory.count == 1)
        #expect(store.requestHistory.first?.prompt == prompt)
        #expect(store.diagnostics.text.contains("Confirming playback"))
        #expect(store.diagnostics.text.contains("Confirmed:"))
    }

    @Test(arguments: ["Play Peace of Blood by Citadelle", "play Peace of Blood", "play \"Peace of Blood\""])
    func exactSongsResolveOnceAndConfirmTheMatchingURI(prompt: String) async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.trackCandidates = [song]
        api.playbackValue = state()
        api.onExecute = { _ in api.holdPlayback = true }
        store.prompt = prompt
        store.submitPrompt()
        while api.playbackReply == nil { await Task.yield() }
        #expect(store.latestResult == nil)
        #expect(store.lastResolvedItem == song.displayName)
        api.holdPlayback = false
        api.playbackReply?.resume(returning: state())
        await store.waitUntilIdle()
        #expect(api.trackQueries.count == 1)
        #expect(api.actions == [.playResolvedTrack(song)])
        #expect(api.actionDeviceIDs == ["mac"])
        #expect(store.playback?.item?.uri == song.uri)
        #expect(store.latestResult?.resolvedItem == song.displayName)
        #expect(store.latestError == nil)
    }

    @Test(arguments: ["wrong track", "wrong device", "paused", "no playback"])
    func unmatchedSongPlaybackNeverReportsSuccess(outcome: String) async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.trackCandidates = [song]
        api.playbackValue = state()
        api.applyControls = false
        api.onExecute = { _ in
            switch outcome {
            case "wrong track": api.playbackValue = state()
            case "wrong device": api.playbackValue = state(track: song, device: .init(id: "phone", name: "Phone", isActive: true, isRestricted: false))
            case "paused": api.playbackValue = state(playing: false, track: song)
            default: api.playbackValue = nil
            }
        }
        store.prompt = "Play Peace of Blood by Citadelle"
        store.submitPrompt()
        let reads = api.playbackReads
        await store.waitUntilIdle()
        #expect(api.playbackReads - reads == 7) // One baseline read, six confirmation reads.
        #expect(api.actions == [.playResolvedTrack(song)])
        #expect(store.latestResult == nil)
        #expect(store.latestError?.contains("hasn't confirmed") == true)
        #expect(store.requestHistory.first?.status == .failure)
        #expect(store.lastResolvedItem == song.displayName)
        #expect(!store.returnToSuggestionsIfIdle(at: store.lastInteractionAt.addingTimeInterval(120)))
    }

    @Test func noMatchAndNoDeviceSendNoPlaybackCommand() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.trackCandidates = []
        store.prompt = "play Peace of Blood by Citadelle"
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(store.latestError?.contains("No matching song") == true)
        #expect(api.actions.isEmpty)
        api.trackCandidates = [song]
        api.deviceValues = []
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(store.latestError?.contains("Open Spotify") == true)
        #expect(api.actions.isEmpty)
        #expect(store.latestResult == nil)
    }

    @Test func startsOnAnAvailableDeviceWhenThereIsNoCurrentPlayback() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.trackCandidates = [song]
        store.prompt = "play Peace of Blood"
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(api.actionDeviceIDs == ["mac"])
        #expect(store.playback?.device?.id == "mac")
        #expect(store.latestError == nil)
    }

    @Test(arguments: [false, true])
    func namedTransfersConfirmTheSelectedIDRatherThanAnotherSameNamedDevice(wrongDevice: Bool) async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        let phone = SpotifyDevice(id: "phone", name: "Phone", isActive: false, isRestricted: false)
        let other = SpotifyDevice(id: "other", name: "Phone", isActive: false, isRestricted: false)
        api.deviceValues = [mac, phone, other]
        api.playbackValue = state()
        api.onExecute = { _ in api.playbackValue = state(device: wrongDevice ? other : phone) }
        store.prompt = "play on Phone"
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(api.actionDeviceIDs == ["phone"])
        #expect(api.actions == [.transferPlayback(deviceName: "Phone")])
        #expect((store.latestError != nil) == wrongDevice)
        #expect((store.latestResult != nil) == !wrongDevice)
    }

    @Test(arguments: [false, true])
    func sureConfirmsPlaylistContextThroughEitherEntryPoint(notification: Bool) async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        store.prompt = "find a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        let id = try #require(store.pendingPlaylistRecommendation?.id)
        #expect(api.actions.isEmpty)
        api.playbackValue = state(context: .init(type: "playlist", uri: "spotify:playlist:other"))
        api.onExecute = { _ in api.holdPlayback = true }
        store.prompt = "a new draft"
        if notification { await store.handleNotification(NotificationService.playAction, id: id) }
        else { store.acceptPlaylistRecommendation(id: id) }
        while api.playbackReply == nil { await Task.yield() }
        #expect(store.latestResult == nil)
        #expect(store.showsRequestProgress)
        store.acceptPlaylistRecommendation(id: id)
        await store.handleNotification(NotificationService.playAction, id: id)
        api.holdPlayback = false
        // Same song and device, but the wrong playlist must not confirm Sure.
        api.playbackReply?.resume(returning: state(context: .init(type: "playlist", uri: "spotify:playlist:other")))
        await store.waitUntilIdle()
        #expect(api.actions == [.playResolvedPlaylist(api.found)])
        #expect(store.latestError == nil)
        #expect(store.latestResult?.playlist == api.found)
        #expect(store.playback?.context?.uri == api.found.uri)
        #expect(store.requestHistory.first?.prompt == "find a soft rock playlist")
        #expect(store.prompt == "a new draft")
    }

    @Test(arguments: ["wrong context", "missing context", "paused", "wrong device", "read failure", "lost write reply", "server error"])
    func uncertainSureCannotReplayAfterFailureOrRelaunch(outcome: String) async throws {
        let (store, api, _, _, defaults) = try await StoreTests().fixture()
        store.prompt = "find a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        let id = try #require(store.pendingPlaylistRecommendation?.id)
        api.playbackValue = state()
        api.applyControls = false
        api.onExecute = { _ in
            let context = SpotifyPlayback.Context(type: "playlist", uri: api.found.uri)
            switch outcome {
            case "wrong context": api.playbackValue = state(context: .init(type: "playlist", uri: "spotify:playlist:other"))
            case "paused": api.playbackValue = state(playing: false, context: context)
            case "wrong device": api.playbackValue = state(device: .init(id: "phone", name: "Phone", isActive: true, isRestricted: false), context: context)
            case "read failure": api.playbackError = URLError(.notConnectedToInternet)
            default: break
            }
        }
        if outcome == "lost write reply" {
            api.actionError = URLError(.timedOut, userInfo: [NSURLErrorFailingURLStringErrorKey: "https://secret-token@example.test"])
        } else if outcome == "server error" { api.actionError = SpotifyAPIError.requestFailed(503, "/me/player/play") }
        await store.handleNotification(NotificationService.playAction, id: id)
        await store.waitUntilIdle()
        #expect(store.latestResult == nil)
        #expect(store.latestError?.contains("Check Spotify") == true)
        #expect(store.pendingPlaylistRecommendation == nil)
        #expect(store.requestHistory.first?.status == .failure)
        #expect(!store.diagnostics.text.contains("secret-token"))
        #expect(!store.diagnostics.text.contains("Completed: Playing"))
        await store.handleNotification(NotificationService.playAction, id: id)
        await store.waitUntilIdle()
        api.playbackError = nil
        let (restarted, _, _, _, _) = try await StoreTests().fixture(defaults: defaults, api: api)
        await restarted.handleNotification(NotificationService.playAction, id: id)
        await restarted.waitUntilIdle()
        #expect(api.actions.count == 1)
        #expect(restarted.pendingPlaylistRecommendation == nil)
    }

    @Test func definitiveRefusalAllowsAnExplicitSureRetry() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        store.prompt = "find a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        let id = try #require(store.pendingPlaylistRecommendation?.id)
        api.actionError = SpotifyAPIError.rateLimited(30)
        store.acceptPlaylistRecommendation(id: id)
        await store.waitUntilIdle()
        #expect(store.pendingPlaylistRecommendation?.id == id)
        #expect(store.latestError?.contains("30 seconds") == true)
        #expect(api.actions.count == 1)
        api.actionError = nil
        store.acceptPlaylistRecommendation(id: id)
        await store.waitUntilIdle()
        #expect(api.actions.count == 2)
        #expect(store.latestError == nil)
        #expect(store.latestResult != nil)
    }

    @Test(arguments: [false, true])
    func cancelledRequestCannotPublishLateConfirmation(logout: Bool) async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = state()
        api.onExecute = { _ in api.holdPlayback = true }
        store.prompt = "shuffle on"
        store.submitPrompt()
        let completion = Task { await store.waitUntilIdle() }
        while api.playbackReply == nil { await Task.yield() }
        let reply = api.playbackReply
        api.holdPlayback = false
        if logout { store.logout() }
        else {
            store.cancel()
            store.prompt = "hello"
            store.submitPrompt()
            await store.waitUntilIdle()
        }
        let history = store.requestHistory.count
        reply?.resume(returning: state(shuffle: true))
        await completion.value
        #expect(!store.isBusy)
        #expect(store.requestHistory.count == history)
        #expect(store.latestError == nil)
        if logout { #expect(store.playback == nil); #expect(store.latestResult == nil) }
        else { #expect(store.latestResult?.source == .conversation) }
    }

    @Test func cancellationDuringPreflightSendsNothingAndPollingCanResume() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.holdPlayback = true
        store.prompt = "pause"
        store.submitPrompt()
        let completion = Task { await store.waitUntilIdle() }
        while api.playbackReply == nil { await Task.yield() }
        store.cancel()
        api.holdPlayback = false
        api.playbackReply?.resume(returning: state())
        await completion.value
        #expect(api.actions.isEmpty)
        api.playbackValue = state()
        await store.refreshPlayback()
        #expect(store.playback?.device?.id == "mac")
    }

    @Test func oldPollingResponseCannotOverwriteConfirmedRequest() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = state()
        api.holdPlayback = true
        let refresh = Task { await store.refreshPlayback() }
        while api.playbackReply == nil { await Task.yield() }
        let reply = api.playbackReply
        api.holdPlayback = false
        store.prompt = "shuffle on"
        store.submitPrompt()
        await store.waitUntilIdle()
        reply?.resume(returning: state())
        await refresh.value
        #expect(store.playback?.shuffleState == true)
        #expect(store.latestError == nil)
    }

    @Test(arguments: ["queue Peace of Blood", "queue Peace of Blood by Citadelle"])
    func queueRequestsDoNotWaitForTheQueuedSongToPlay(prompt: String) async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.trackCandidates = [song]
        api.applyControls = false
        api.playbackValue = state()
        store.prompt = prompt
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(api.actions == [.queueResolvedTrack(song)])
        #expect(store.latestResult?.title.hasPrefix("Queued") == true)
        #expect(store.latestError == nil)
    }

    @Test func notificationMagicStillUsesOriginalBriefWithoutStartingPlayback() async throws {
        let (store, api, planner, _, _) = try await StoreTests().fixture()
        store.prompt = "find a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        let id = try #require(store.pendingPlaylistRecommendation?.id)
        store.prompt = "my new draft"
        await store.handleNotification(NotificationService.magicAction, id: id)
        await store.waitUntilIdle()
        #expect(planner.prompts == ["find a soft rock playlist"])
        #expect(store.prompt == "my new draft")
        #expect(api.actions.isEmpty)
        #expect(api.creations == 1 && api.writes == 1)
    }

    @Test(arguments: ["play some EDM songs", "late night driving", "play songs by Ed Sheeran", "what should I play?", "damn I'm tired"])
    func recommendationsAndChatNeverStartPlayback(prompt: String) async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playlistCandidates = [.init(uri: "spotify:playlist:match", name: "EDM Late Night Driving This Is Ed Sheeran", ownerName: nil, description: nil)]
        store.prompt = prompt
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(api.actions.isEmpty)
        #expect(store.latestError == nil)
        if prompt == "what should I play?" || prompt == "damn I'm tired" {
            #expect(store.latestResult?.source == .conversation)
        } else { #expect(store.pendingPlaylistRecommendation != nil) }
    }
}
