import Foundation
import Testing
@testable import VibeCast

@MainActor
struct PlayerFeedbackTests {
    @Test(arguments: [false, true], [false, true])
    func dismissRestoresSuggestionsImmediatelyAndPreservesDraftAndHistory(newDraft: Bool, deniedNotification: Bool) async throws {
        let (store, api, planner, notifications, _) = try await StoreTests().fixture()
        notifications.denied = deniedNotification
        store.prompt = "find me a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(store.pendingPlaylistRecommendation != nil)
        let historyCount = store.requestHistory.count
        if newDraft { store.prompt = "something I am still typing" }
        store.dismissRecommendation()
        #expect(store.pendingPlaylistRecommendation == nil)
        #expect(store.requestState == .idle)
        #expect(store.latestResult == nil)
        #expect(store.notificationNotice == nil)
        #expect(store.prompt == (newDraft ? "something I am still typing" : ""))
        #expect(store.requestHistory.count == historyCount)
        #expect(api.actions.isEmpty)
        #expect(planner.prompts.isEmpty)
        store.dismissRecommendation()
        #expect(store.requestState == .idle)
    }

    @Test(arguments: [false, true])
    func dismissOldRecommendationKeepsNewRequestFeedback(stillRunning: Bool) async throws {
        let (store, _, _, _, _) = try await StoreTests().fixture()
        store.prompt = "find me a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        store.prompt = "hello"
        store.submitPrompt()
        if !stillRunning { await store.waitUntilIdle() }
        let state = store.requestState
        store.dismissRecommendation()
        #expect(store.requestState == state)
        await store.waitUntilIdle()
        #expect(store.latestResult?.source == .conversation)
        #expect(store.requestState != .idle)
    }

    @Test(arguments: [false, true])
    func acceptingRecommendationKeepsFeedbackUntilIdleTimeout(magic: Bool) async throws {
        let (store, _, _, _, _) = try await StoreTests().fixture()
        store.prompt = "find me a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        let id = try #require(store.pendingPlaylistRecommendation?.id)
        if magic { store.castMagic(from: id) }
        else { store.acceptPlaylistRecommendation(id: id) }
        await store.waitUntilIdle()
        #expect(store.latestResult != nil)
        #expect(store.requestState != .idle)
        let completion = store.lastInteractionAt
        #expect(!store.returnToSuggestionsIfIdle(at: completion.addingTimeInterval(59)))
        #expect(store.returnToSuggestionsIfIdle(at: completion.addingTimeInterval(60)))
    }

    @Test func readingPanelsKeepSameDefaultHeightAndFitTheScreen() {
        let state = PlayerPresentation()
        for panel in [PlayerPanel.lyrics, .queue] {
            state.selectPanel(panel)
            #expect(state.desiredHeight(natural: PlayerPresentation.readingHeight) == 544)
        }
        state.maximumHeight = 500
        #expect(state.desiredHeight(natural: PlayerPresentation.readingHeight) == 500)
    }

    @Test func buttonsAreQuietButKeepDeveloperHistory() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        store.control(.next)
        #expect(store.isBusy)
        #expect(!store.showsRequestProgress)
        #expect(store.latestResult == nil)
        #expect(store.requestState == .idle)
        await store.waitUntilIdle()
        #expect(api.actions.count == 1)
        #expect(store.latestResult == nil)
        #expect(store.requestState == .idle)
        #expect(!store.isPlayerControl)
        #expect(store.requestHistory.count == 1)
    }

    @Test func typedCommandsStillReplyAndButtonsPreserveThatReply() async throws {
        let (store, _, _, _, _) = try await StoreTests().fixture()
        store.prompt = "pause"
        store.submitPrompt()
        #expect(store.showsRequestProgress)
        await store.waitUntilIdle()
        let reply = try #require(store.latestResult)
        let state = store.requestState
        store.control(.shuffle(true))
        #expect(!store.showsRequestProgress)
        #expect(store.latestResult == reply)
        await store.waitUntilIdle()
        #expect(store.latestResult == reply)
        #expect(store.requestState == state)
    }

    @Test func buttonErrorsRemainVisibleAndRecoveryIsQuiet() async throws {
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.failAction = true
        store.control(.next)
        await store.waitUntilIdle()
        #expect(store.latestError == "Spotify control failed")
        #expect(!store.returnToSuggestionsIfIdle(at: store.lastInteractionAt.addingTimeInterval(120)))
        api.failAction = false
        store.control(.next)
        await store.waitUntilIdle()
        #expect(store.latestError == nil)
        #expect(store.latestResult == nil)
        #expect(store.requestState == .idle)
    }

    @Test func idleResetWaitsOneMinuteFromLastInteractionAndKeepsHistory() async throws {
        let (store, _, _, _, _) = try await StoreTests().fixture()
        store.prompt = "hello"
        store.submitPrompt()
        await store.waitUntilIdle()
        let completed = store.lastInteractionAt
        #expect(!store.returnToSuggestionsIfIdle(at: completed.addingTimeInterval(59)))
        store.noteInteraction(at: completed.addingTimeInterval(40))
        #expect(!store.returnToSuggestionsIfIdle(at: completed.addingTimeInterval(60)))
        #expect(store.returnToSuggestionsIfIdle(at: completed.addingTimeInterval(100)))
        #expect(store.latestResult == nil)
        #expect(store.requestState == .idle)
        #expect(store.prompt.isEmpty)
        #expect(!store.requestHistory.isEmpty)
        #expect(!store.returnToSuggestionsIfIdle(at: completed.addingTimeInterval(200)))
    }

    @Test func idleResetPreservesDraftsBusyWorkAndPlaylistChoices() async throws {
        let (store, _, _, _, _) = try await StoreTests().fixture()
        store.prompt = "hello"
        store.submitPrompt()
        #expect(!store.returnToSuggestionsIfIdle(at: store.lastInteractionAt.addingTimeInterval(120)))
        await store.waitUntilIdle()
        store.prompt = "my unfinished request"
        #expect(!store.returnToSuggestionsIfIdle(at: store.lastInteractionAt.addingTimeInterval(120)))
        #expect(store.prompt == "my unfinished request")
        store.prompt = "find me a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        let recommendation = try #require(store.pendingPlaylistRecommendation)
        #expect(!store.returnToSuggestionsIfIdle(at: store.lastInteractionAt.addingTimeInterval(120)))
        #expect(store.pendingPlaylistRecommendation?.id == recommendation.id)
    }
}
