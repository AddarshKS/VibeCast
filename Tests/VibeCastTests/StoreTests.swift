import Foundation
import Testing
@testable import VibeCast

@MainActor
final class FakeSpotify: SpotifyServing {
    var actions: [SpotifyAction] = []
    var actionDeviceIDs: [String?] = []
    var creations = 0
    var writes = 0
    var failWrite = false
    var noTracks = false
    var searchDelay = false
    var failAction = false
    var holdProfile = false
    var profileError: (any Error)?
    var profileReads = 0
    var profileReply: CheckedContinuation<SpotifyUserProfile, Never>?
    var holdCreation = false
    var creationReply: CheckedContinuation<SpotifyResolvedPlaylist, Never>?
    let found = SpotifyResolvedPlaylist(uri: "spotify:playlist:found", name: "Soft Rock", ownerName: "Spotify", description: nil)
    func profile() async throws -> SpotifyUserProfile {
        profileReads += 1
        if let profileError { throw profileError }
        if holdProfile {
            let profile = await withCheckedContinuation { profileReply = $0 }
            if let profileError { throw profileError }
            return profile
        }
        return SpotifyUserProfile(id: "alice", displayName: "Alice")
    }
    var playbackValue: SpotifyPlayback?
    var applyControls = true
    var playbackResponses: [SpotifyPlayback?] = []
    var holdPlayback = false
    var playbackReply: CheckedContinuation<SpotifyPlayback?, Never>?
    var playbackReads = 0
    var queueValue: [SpotifyQueueItem] = []
    var queueReads = 0
    var previousItems: [SpotifyTrack] = []
    var deviceValues: [SpotifyDevice] = []
    func devices() async throws -> [SpotifyDevice] { deviceValues }
    var queueFailure = false
    var holdQueue = false
    var queueReply: CheckedContinuation<[SpotifyQueueItem], Never>?
    func playback() async throws -> SpotifyPlayback? {
        playbackReads += 1
        if holdPlayback { return await withCheckedContinuation { playbackReply = $0 } }
        if !playbackResponses.isEmpty { return playbackResponses.removeFirst() }
        return playbackValue
    }
    func queue() async throws -> [SpotifyQueueItem] {
        queueReads += 1
        if holdQueue { return await withCheckedContinuation { queueReply = $0 } }
        if queueFailure { throw UserFacingError("Queue unavailable") }
        return queueValue
    }
    func execute(_ action: SpotifyAction, deviceID: String? = nil) async throws -> VibeCastResult {
        actions.append(action)
        actionDeviceIDs.append(deviceID)
        if failAction { throw UserFacingError("Spotify control failed") }
        if applyControls {
            let old = playbackValue
            var playing = old?.isPlaying ?? true
            var shuffle = old?.shuffleState ?? false
            var repeatMode = old?.repeatState ?? "off"
            var item = old?.item
            var device = old?.device
            var position = 0
            switch action {
            case .shuffle(let value): shuffle = value
            case .repeatMode(let value): repeatMode = value.rawValue
            case .pause: playing = false
            case .resume: playing = true
            case .next, .previous:
                item = SpotifyTrack(uri: "spotify:track:step\(actions.count)", name: "Next", artists: [], album: nil, isPlayable: true)
            case .playResolvedTrack(let track):
                playing = true
                item = SpotifyTrack(uri: track.uri, name: track.title, artists: [SpotifyArtist(name: track.artist)], album: nil, isPlayable: true)
            case .transferToDevice(let value): device = value
            case .seek(let value, _): position = value
            case .advanceQueue:
                if !queueValue.isEmpty {
                    let next = queueValue.removeFirst()
                    item = SpotifyTrack(uri: next.uri, name: next.name, artists: next.artists ?? [], album: next.album, isPlayable: true)
                }
            case .rewindQueue:
                if !previousItems.isEmpty { item = previousItems.removeLast() }
            default: break
            }
            playbackValue = SpotifyPlayback(isPlaying: playing, item: item, device: device,
                                            shuffleState: shuffle, repeatState: repeatMode, progressMS: position)
        }
        return VibeCastResult(title: "Playing", source: .spotifyAPI)
    }
    func searchPlaylistCandidates(query: String, limit: Int) async throws -> [SpotifyResolvedPlaylist] {
        if searchDelay { try await Task.sleep(for: .seconds(2)) }
        return [found]
    }
    func searchTrackCandidates(query: String, limit: Int) async throws -> [SpotifyResolvedTrack] {
        if noTracks { return [] }
        guard let i = (1...12).first(where: { query == TrackIntent(title: "Song \($0)", artist: "Artist").searchQuery }) else { return [] }
        return [SpotifyResolvedTrack(uri: "spotify:track:" + String(format: "%022d", i), title: "Song \(i)", artist: "Artist")]
    }
    func createPlaylist(name: String, description: String) async throws -> SpotifyResolvedPlaylist {
        creations += 1
        if holdCreation { return await withCheckedContinuation { creationReply = $0 } }
        return found
    }
    func setPlaylistTracks(_ playlist: SpotifyResolvedPlaylist, tracks: [SpotifyResolvedTrack]) async throws {
        writes += 1
        if failWrite { throw UserFacingError("Connection interrupted") }
    }
}

@MainActor
final class FakePlanner: PlaylistPlanning {
    var prompts: [String] = []
    func plan(for prompt: String) async throws -> PlaylistPlan {
        prompts.append(prompt)
        return PlaylistPlan(name: "Test Mix", description: "An evening", tracks: (1...12).map {
            TrackIntent(title: "Song \($0)", artist: "Artist")
        })
    }
}

@MainActor
final class FakeNotifications: Notifying {
    var delivered: [UUID] = []
    var denied = false
    func recommend(_ recommendation: PendingPlaylistRecommendation) async throws {
        if denied { throw UserFacingError("Notifications disabled") }
        delivered.append(recommendation.id)
    }
    func remove(_ id: UUID) {}
    func clear() {}
}

@MainActor
final class StoreTests {
    func fixture(defaults: UserDefaults? = nil, api: FakeSpotify? = nil, lyrics: any LyricsServing = FixedLyrics(),
                 accountRetryDelay: TimeInterval = 30) async throws
        -> (VibeCastStore, FakeSpotify, FakePlanner, FakeNotifications, UserDefaults) {
        let defaults = defaults ?? UserDefaults(suiteName: UUID().uuidString)!
        let settings = AppSettings(defaults: defaults)
        settings.aiConsent = true
        let secrets = MemorySecrets()
        let token = SpotifyToken(accessToken: "fake", refreshToken: "fake", scope: "playlist-modify-private", expiresAt: .distantFuture)
        try secrets.write(JSONEncoder().encode(token), account: "spotify..")
        let api = api ?? FakeSpotify()
        let planner = FakePlanner()
        let notifications = FakeNotifications()
        let codex = FakeCodexRPC()
        codex.signedIn = false
        let chatGPT = ChatGPTSession(settings: settings, rpc: codex)
        let store = VibeCastStore(settings: settings, secrets: secrets, spotify: api, planner: planner,
                                  notifications: notifications, defaults: defaults, startAutomatically: false, chatGPT: chatGPT,
                                  controlConfirmationDelay: .zero, lyrics: lyrics, accountRetryDelay: accountRetryDelay)
        await store.refreshAuthState()
        return (store, api, planner, notifications, defaults)
    }

    @Test func testFindNeverAutoplaysAndSureExecutesOnlyOnce() async throws {
        let (store, api, _, notifications, _) = try await fixture()
        store.prompt = "find me a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        let pending = try #require(store.pendingPlaylistRecommendation)
        #expect(api.actions.isEmpty)
        #expect((notifications.delivered) == ([pending.id]))
        store.acceptPlaylistRecommendation(id: pending.id)
        store.acceptPlaylistRecommendation(id: pending.id)
        await store.waitUntilIdle()
        store.acceptPlaylistRecommendation(id: pending.id)
        await store.waitUntilIdle()
        #expect((api.actions.count) == (1))
    }

    @Test func testMagicPreservesOriginalPromptAndCreatesPrivatePlaylistFlow() async throws {
        let (store, api, planner, _, _) = try await fixture()
        store.prompt = "find me a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        let id = try #require(store.pendingPlaylistRecommendation?.id)
        store.prompt = "an unrelated new prompt"
        store.castMagic(from: id)
        await store.waitUntilIdle()
        #expect((planner.prompts) == (["find me a soft rock playlist"]))
        #expect((api.creations) == (1))
        #expect((api.writes) == (1))
        #expect(store.pendingPlaylistRecommendation == nil)
        #expect(store.latestError == nil)
    }

    @Test func testNotificationsDeniedStillLeavesInAppRecommendation() async throws {
        let (store, api, _, notifications, _) = try await fixture()
        notifications.denied = true
        store.prompt = "find me a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(store.pendingPlaylistRecommendation != nil)
        #expect(store.notificationNotice != nil)
        #expect(api.actions.isEmpty)
    }

    @Test func testDraftSurvivesRestartAndRetriesWithoutAnotherCreate() async throws {
        let (store, api, _, _, defaults) = try await fixture()
        api.failWrite = true
        store.prompt = "make a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(store.unfinishedPlaylist != nil)
        #expect((api.creations) == (1))
        api.failWrite = false
        let (restarted, _, _, _, _) = try await fixture(defaults: defaults, api: api)
        restarted.finishPlaylist()
        await restarted.waitUntilIdle()
        #expect((api.creations) == (1))
        #expect((api.writes) == (2))
        #expect(restarted.unfinishedPlaylist == nil)
    }

    @Test func testEmptyMatchesDoNotCreateAndClearOldSuccess() async throws {
        let (store, api, _, _, _) = try await fixture()
        api.noTracks = true
        store.prompt = "make a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect((api.creations) == (0))
        #expect(store.latestResult == nil)
        #expect(store.latestError != nil)
    }

    @Test func testCancellationPreventsStaleRecommendation() async throws {
        let (store, api, _, _, _) = try await fixture()
        api.searchDelay = true
        store.prompt = "find me a soft rock playlist"
        store.submitPrompt()
        await Task.yield()
        store.cancel()
        try await Task.sleep(for: .milliseconds(30))
        #expect(!(store.isBusy))
        #expect(store.pendingPlaylistRecommendation == nil)
        #expect(store.latestResult == nil)
    }

    @Test func testPendingRestoresAfterRelaunchAndLogoutPurgesIt() async throws {
        let (store, _, _, _, defaults) = try await fixture()
        store.prompt = "find me a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        let id = try #require(store.pendingPlaylistRecommendation?.id)
        let (restarted, api, _, _, _) = try await fixture(defaults: defaults)
        restarted.acceptPlaylistRecommendation(id: id)
        await restarted.waitUntilIdle()
        #expect((api.actions.count) == (1))
        restarted.logout()
        #expect(restarted.pendingPlaylistRecommendation == nil)
        #expect(RecommendationStore(defaults: defaults).load().isEmpty)
    }

    @Test func testLateProfileCannotSignBackInAfterLogout() async throws {
        let (store, api, _, _, _) = try await fixture()
        api.holdProfile = true
        let refresh = Task { await store.refreshAuthState() }
        while api.profileReply == nil { await Task.yield() }
        store.logout()
        api.profileReply?.resume(returning: SpotifyUserProfile(id: "alice", displayName: "Alice"))
        await refresh.value
        #expect(store.authState == .loggedOut)
    }

    @Test func testExpiredRecoveryDataIsRemovedOnStartup() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let api = FakeSpotify()
        var recommendation = PendingPlaylistRecommendation(accountID: "alice", originalPrompt: "drive",
                                                           playlist: api.found, searchPhrase: "drive")
        recommendation.createdAt = Date().addingTimeInterval(-3601)
        RecommendationStore(defaults: defaults).save([recommendation])
        var draft = PlaylistDraft(accountID: "alice", playlist: api.found, tracks: [])
        draft.createdAt = Date().addingTimeInterval(-86401)
        defaults.set(try JSONEncoder().encode(draft), forKey: "unfinishedPlaylist")
        let store = VibeCastStore(secrets: MemorySecrets(), spotify: api, planner: FakePlanner(),
                                 notifications: FakeNotifications(), defaults: defaults, startAutomatically: false)
        #expect(store.unfinishedPlaylist == nil)
        #expect(defaults.data(forKey: "unfinishedPlaylist") == nil)
        #expect(defaults.data(forKey: "pendingRecommendations.v2") == nil)
    }

    @Test func testLateCreationCannotRestorePrivateStateAfterLogout() async throws {
        let (store, api, _, _, defaults) = try await fixture()
        api.holdCreation = true
        store.prompt = "make a soft rock playlist"
        store.submitPrompt()
        let completion = Task { await store.waitUntilIdle() }
        while api.creationReply == nil { await Task.yield() }
        store.logout()
        api.creationReply?.resume(returning: api.found)
        await completion.value
        #expect(store.authState == .loggedOut)
        #expect(store.unfinishedPlaylist == nil)
        #expect(defaults.data(forKey: "unfinishedPlaylist") == nil)
        #expect(api.writes == 0)
    }

    @Test func testDisconnectedRequestCannotShowPreviousResolution() async throws {
        let (store, _, _, _, _) = try await fixture()
        store.prompt = "find a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(store.lastResolvedItem != nil)
        store.logout()
        store.prompt = "play some EDM songs"
        store.submitPrompt()
        #expect(store.lastRouteName == "Find playlist")
        #expect(store.lastResolvedItem == nil)
        #expect(store.lastSpotifyAction == nil)
        #expect(store.latestError == "Connect Spotify to get started.")
    }
}
