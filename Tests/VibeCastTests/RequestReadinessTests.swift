import Foundation
import Testing
@testable import VibeCast

@MainActor
struct RequestReadinessTests {
    @Test(arguments: ["consent", "planner", "scope", "cancel"])
    func magicPreflightKeepsTheRecommendation(reason: String) async throws {
        let (store, api, planner, _, _) = try await StoreTests().fixture(
            scopes: reason == "scope" ? "playlist-modify-private" : "playlist-modify-private playlist-read-private")
        store.prompt = "find a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        let id = try #require(store.pendingPlaylistRecommendation?.id)
        store.prompt = "my new draft"
        if reason == "consent" { store.settings.aiConsent = false }
        if reason == "planner" { planner.error = UserFacingError("No allowance left") }
        if reason == "cancel" { planner.hold = true }
        store.castMagic(from: id)
        if reason == "cancel" {
            let completion = Task { await store.waitUntilIdle() }
            while planner.reply == nil { await Task.yield() }
            store.cancel()
            planner.reply?.resume()
            await completion.value
        } else { await store.waitUntilIdle() }
        #expect(store.pendingPlaylistRecommendation?.id == id)
        #expect(store.prompt == "my new draft")
        #expect(api.creations == 0)
        #expect(store.pendingPlaylistCreation == nil)
        #expect(store.requestHistory.first?.status == (reason == "cancel" ? .cancelled : .failure))
        if reason == "scope" { #expect(planner.prompts.isEmpty) }
        // The original Sure action is still usable after a failed Magic attempt.
        store.acceptPlaylistRecommendation(id: id)
        await store.waitUntilIdle()
        #expect(api.actions == [.playResolvedPlaylist(api.found)])
    }

    @Test func uncertainCreationIsPersistedBeforeWriteAndRecoveredAfterRelaunch() async throws {
        let (store, api, _, _, defaults) = try await StoreTests().fixture()
        api.creationError = URLError(.timedOut)
        api.onCreate = {
            #expect((try? PlaylistRecoveryStore(defaults: defaults).load(accountID: "alice"))?.attempt != nil)
            #expect(store.pendingPlaylistCreation != nil)
        }
        store.prompt = "make a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        let attempt = try #require(store.pendingPlaylistCreation)
        #expect(api.creations == 1)
        #expect(api.creationDescriptions == [attempt.spotifyDescription])
        #expect(store.latestError?.contains("Check Spotify") == true)
        #expect(store.latestResult == nil)
        #expect(api.writes == 0)
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(api.creations == 1)

        let (restarted, _, _, _, _) = try await StoreTests().fixture(defaults: defaults, api: api)
        #expect(restarted.pendingPlaylistCreation?.id == attempt.id)
        // An empty lookup is not permission to issue another create POST.
        restarted.recoverPlaylistCreation()
        await restarted.waitUntilIdle()
        #expect(restarted.pendingPlaylistCreation?.id == attempt.id)
        #expect(api.creations == 1)
        api.recoveryValue = api.found
        restarted.recoverPlaylistCreation()
        await restarted.waitUntilIdle()
        #expect(api.creations == 1)
        #expect(api.writes == 1)
        #expect(api.writtenTracks == attempt.tracks)
        #expect(api.verificationReads == 1)
        #expect(restarted.pendingPlaylistCreation == nil)
        #expect(restarted.unfinishedPlaylist == nil)
        #expect(restarted.latestResult?.source == .makePlaylist)
        #expect(try PlaylistRecoveryStore(defaults: defaults).load(accountID: "alice") == nil)
    }

    @Test func definiteCreationRejectionRestoresRecommendation() async throws {
        let (store, api, _, _, defaults) = try await StoreTests().fixture()
        store.prompt = "find a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        let id = try #require(store.pendingPlaylistRecommendation?.id)
        api.creationError = SpotifyAPIError.refused(path: "/me/playlists", message: "")
        store.castMagic(from: id)
        await store.waitUntilIdle()
        #expect(store.pendingPlaylistRecommendation?.id == id)
        #expect(store.pendingPlaylistCreation == nil)
        #expect(try PlaylistRecoveryStore(defaults: defaults).load(accountID: "alice") == nil)
        #expect(api.writes == 0)
    }

    @Test func verificationFailureRetainsDraftAndExplicitFinishReusesPlaylist() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.verificationError = PlaylistRecoveryError.verificationFailed
        store.prompt = "make a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        let draft = try #require(store.unfinishedPlaylist)
        #expect(store.latestResult == nil)
        #expect(store.lastRequestStage == "Verify private playlist and song order")
        #expect(store.requestHistory.first?.stage == store.lastRequestStage)
        api.verificationError = nil
        store.finishPlaylist()
        await store.waitUntilIdle()
        #expect(api.creations == 1)
        #expect(api.writes == 2)
        #expect(api.writtenTracks == draft.tracks)
        #expect(store.unfinishedPlaylist == nil)
        #expect(store.latestResult?.playlist == draft.playlist)
    }

    @Test func cancelledCreateCannotOverwriteLaterRequestAndRemainsRecoverable() async throws {
        let (store, api, _, _, defaults) = try await StoreTests().fixture()
        api.holdCreation = true
        store.prompt = "make a soft rock playlist"
        store.submitPrompt()
        let completion = Task { await store.waitUntilIdle() }
        while api.creationReply == nil { await Task.yield() }
        let attempt = try #require(store.pendingPlaylistCreation)
        store.cancel()
        store.prompt = "hello"
        store.submitPrompt()
        await store.waitUntilIdle()
        let reply = store.latestResult
        api.creationReply?.resume(returning: api.found)
        await completion.value
        #expect(store.latestResult == reply)
        #expect(store.unfinishedPlaylist == nil)
        #expect(store.pendingPlaylistCreation?.id == attempt.id)
        #expect(try PlaylistRecoveryStore(defaults: defaults).load(accountID: "alice")?.attempt?.id == attempt.id)
        #expect(api.writes == 0)
        #expect(store.requestHistory.contains { $0.status == .cancelled && $0.stage == "Create private playlist" })
    }

    @Test func cancelledPopulationKeepsDraftAndDoesNotEraseLaterFeedback() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.holdWrite = true
        store.prompt = "make a soft rock playlist"
        store.submitPrompt()
        let completion = Task { await store.waitUntilIdle() }
        while api.writeReply == nil { await Task.yield() }
        store.cancel()
        store.prompt = "hello"
        store.submitPrompt()
        await store.waitUntilIdle()
        let reply = store.latestResult
        api.writeReply?.resume()
        await completion.value
        #expect(store.latestResult == reply)
        #expect(store.unfinishedPlaylist != nil)
        #expect(api.verificationReads == 0)
        #expect(store.requestHistory.count == 2)
    }

    @Test func dismissingFeedbackPreservesNewDraftChoiceRecoveryAndEvidence() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        store.prompt = "find a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        let id = try #require(store.pendingPlaylistRecommendation?.id)
        api.failWrite = true
        store.prompt = "make a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        let history = store.requestHistory
        let stage = store.lastRequestStage
        store.prompt = "a fresh draft"
        store.clear()
        #expect(store.prompt == "a fresh draft")
        #expect(store.latestError == nil)
        #expect(store.requestState == .idle)
        #expect(store.pendingPlaylistRecommendation?.id == id)
        #expect(store.unfinishedPlaylist != nil)
        #expect(store.requestHistory == history)
        #expect(store.lastRequestStage == stage)
        #expect(!store.returnToSuggestionsIfIdle(at: store.lastInteractionAt.addingTimeInterval(120)))
    }

    @Test func stoppingRecoveryIsLocalAndLateCreationCannotRestoreIt() async throws {
        let (store, api, _, _, defaults) = try await StoreTests().fixture()
        api.holdCreation = true
        store.prompt = "make a soft rock playlist"
        store.submitPrompt()
        let completion = Task { await store.waitUntilIdle() }
        while api.creationReply == nil { await Task.yield() }
        store.cancel()
        store.abandonPlaylistRecovery(id: try #require(store.playlistRecoveryID))
        api.creationReply?.resume(returning: api.found)
        await completion.value
        #expect(store.pendingPlaylistCreation == nil)
        #expect(store.unfinishedPlaylist == nil)
        #expect(try PlaylistRecoveryStore(defaults: defaults).load(accountID: "alice") == nil)
        #expect(api.creations == 1 && api.writes == 0)
        #expect(store.diagnostics.text.contains("Recovery stopped by user"))
    }

    @Test func accountChangesCannotRecoverAnotherUsersAttempt() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let attempt = PlaylistCreationAttempt(accountID: "bob", name: "Private", description: "",
                                              tracks: [.init(uri: "spotify:track:0000000000000000000001", title: "Song", artist: "Artist")])
        defaults.set(try JSONEncoder().encode(attempt), forKey: "pendingPlaylistCreation")
        let (store, api, _, _, _) = try await StoreTests().fixture(defaults: defaults)
        store.recoverPlaylistCreation()
        #expect(store.pendingPlaylistCreation == nil)
        #expect(api.recoveryReads == 0)
        #expect(defaults.data(forKey: "pendingPlaylistCreation") == nil)
        #expect(try PlaylistRecoveryStore(defaults: defaults).load(accountID: "bob")?.attempt == attempt)
        api.profileValue = .init(id: "bob", displayName: "Bob")
        await store.refreshAuthState()
        #expect(store.pendingPlaylistCreation == attempt)
        store.logout()
        #expect(store.pendingPlaylistCreation == nil)
        let (reconnected, _, _, _, _) = try await StoreTests().fixture(defaults: defaults, api: api)
        #expect(reconnected.pendingPlaylistCreation == attempt)
    }

    @Test func contextualConversationStillRequiresPlaylistConfirmation() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        store.prompt = "I'm tired"
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(store.latestResult?.source == .conversation)
        store.prompt = "an artist"
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(store.latestResult?.title == "Which artist?")
        api.playlistCandidates = [.init(uri: "spotify:playlist:artist", name: "This Is Martin Garrix", ownerName: "Spotify", description: nil)]
        store.prompt = "Martin Garrix"
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(store.pendingPlaylistRecommendation?.playlist.name == "This Is Martin Garrix")
        #expect(store.lastRequestPrompt == "Martin Garrix")
        #expect(api.actions.isEmpty)
    }

    @Test func queueClarificationAndUncertainWriteNeverBecomePlaybackOrBlindRetry() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.trackCandidates = []
        store.prompt = "please queue Hello"
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(store.latestError?.contains("Who performs") == true)
        let song = SpotifyResolvedTrack(uri: "spotify:track:0000000000000000000001", title: "Hello", artist: "Adele")
        api.trackCandidates = [song]
        api.actionError = URLError(.networkConnectionLost)
        store.prompt = "Adele"
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(api.actions == [.queueResolvedTrack(song)])
        #expect(store.latestError?.contains("Check your queue") == true)
        #expect(store.latestResult == nil)
    }

    @Test func staleStopRecoveryConfirmationCannotDiscardNewerWork() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.creationError = URLError(.timedOut)
        store.prompt = "make a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        let oldID = try #require(store.playlistRecoveryID)
        store.abandonPlaylistRecovery(id: oldID)
        store.prompt = "make a jazz playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        let newID = try #require(store.playlistRecoveryID)
        #expect(oldID != newID)
        store.abandonPlaylistRecovery(id: oldID)
        #expect(store.playlistRecoveryID == newID)
    }

    @Test func dismissValidationErrorClearsOnlyTheSubmittedDraft() async throws {
        let (store, _, _, _, _) = try await StoreTests().fixture()
        store.prompt = String(repeating: "x", count: AppConfig.maximumPromptLength + 1)
        store.submitPrompt()
        store.clear()
        #expect(store.prompt.isEmpty)
        store.logout()
        store.prompt = "play some jazz"
        store.submitPrompt()
        store.prompt = "a newer draft"
        store.clear()
        #expect(store.prompt == "a newer draft")
    }

    @Test(arguments: [false, true], [false, true])
    func lateNotificationCannotSurviveLogoutOrOverwriteNewerFeedback(logout: Bool, denied: Bool) async throws {
        let (store, _, _, notifications, _) = try await StoreTests().fixture()
        notifications.hold = true
        notifications.denied = denied
        store.prompt = "find a soft rock playlist"
        store.submitPrompt()
        let completion = Task { await store.waitUntilIdle() }
        while notifications.reply == nil { await Task.yield() }
        let id = try #require(store.pendingPlaylistRecommendation?.id)
        if logout { store.logout() } else { store.cancel() }
        store.prompt = "hello"
        store.submitPrompt()
        await store.waitUntilIdle()
        let newResult = store.latestResult
        notifications.reply?.resume()
        await completion.value
        #expect(store.latestResult == newResult)
        #expect(store.notificationNotice == nil)
        #expect(store.latestError == nil)
        #expect(notifications.delivered.isEmpty)
        #expect(notifications.removed.contains(id))
        if logout { #expect(store.pendingPlaylistRecommendation == nil) }
    }

    @Test func validationFailuresAreRecordedAndCancelledHistoryDoesNotDuplicate() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        store.prompt = String(repeating: "x", count: AppConfig.maximumPromptLength + 1)
        store.submitPrompt()
        #expect(store.requestHistory.first?.status == .failure)
        #expect(store.requestHistory.first?.stage == "Understanding request")
        api.searchDelay = true
        store.prompt = "find a soft rock playlist"
        store.submitPrompt()
        let completion = Task { await store.waitUntilIdle() }
        await Task.yield()
        store.cancel()
        store.cancel()
        await completion.value
        #expect(store.requestHistory.filter { $0.status == .cancelled }.count == 1)
        #expect(store.lastRequestOutcome == "Cancelled")
        #expect(store.requestState == .idle)
    }
}
