import SwiftUI
import Testing
@testable import VibeCast

struct ImmersiveMiniplayerTests {
    @Test func exitTargetExcludesControlsAndEntireWindowButtonCorner() {
        let path = ImmersiveArtworkExitArea().path(in: CGRect(x: 0, y: 0, width: 340, height: 212))
        #expect(path.contains(CGPoint(x: 150, y: 20)))
        #expect(path.contains(CGPoint(x: 150, y: 210)))
        #expect(!path.contains(CGPoint(x: 150, y: 220)))
        #expect(!path.contains(CGPoint(x: 150, y: 275)))
        for x in stride(from: 289.0, through: 339, by: 5) {
            for y in stride(from: 1.0, through: 51, by: 5) {
                #expect(!path.contains(CGPoint(x: x, y: y)))
            }
        }
        #expect(path.contains(CGPoint(x: 300, y: 60)))
    }

    @Test func detachedDragGripCannotExitTheMiniplayer() {
        let path = ImmersiveArtworkExitArea(reservesDragHandle: true).path(in: CGRect(x: 0, y: 0, width: 340, height: 212))
        for x in stride(from: 145.0, through: 195, by: 5) {
            for y in stride(from: 1.0, through: 29, by: 5) {
                #expect(!path.contains(CGPoint(x: x, y: y)))
            }
        }
        #expect(path.contains(CGPoint(x: 170, y: 40)))
        #expect(path.contains(CGPoint(x: 40, y: 20)))
    }

    @MainActor @Test(arguments: [PlayerPanel.lyrics, .queue])
    func miniDetailsAreIndependentOfNormalPanelsAndSurviveContainerChanges(panel: PlayerPanel) {
        let state = PlayerPresentation()
        state.windowHeight = 340
        state.toggleMiniplayer()
        state.toggleMiniplayerPanel(panel)
        #expect(state.miniplayerPanel == panel && !state.isReading)
        #expect(state.panel == nil)
        #expect(state.layout == .miniplayer)
        #expect(state.miniplayerDetailHeight == 340)
        state.isDetached = true
        state.resetWindowSize()
        #expect(state.miniplayerPanel == panel && state.isHeightLocked)
        #expect(state.miniplayerDetailHeight == 340)
        state.toggleMiniplayerPanel(panel)
        #expect(state.miniplayer && state.miniplayerPanel == nil)
        state.toggleMiniplayer()
        state.selectPanel(.lyrics)
        #expect(state.layout == .lyrics && state.miniplayerPanel == nil)
        #expect(state.layout == .lyrics && !state.isHeightLocked)
        state.toggleMiniplayer()
        #expect(!state.isReading && state.miniplayerPanel == nil)
    }

    @MainActor @Test func miniQueueActivationDoesNotChangeNormalQueueAndCannotOpenOutsideMini() {
        let state = PlayerPresentation()
        state.toggleMiniplayerPanel(.queue)
        #expect(state.miniplayerPanel == nil && state.miniplayerQueueActivation == 0)
        state.selectPanel(.queue)
        let normalActivation = state.queueActivation
        state.toggleMiniplayer()
        state.toggleMiniplayerPanel(.outputs)
        #expect(state.miniplayerPanel == nil)
        state.toggleMiniplayerPanel(.queue)
        #expect(state.miniplayerQueueActivation == 1 && state.queueActivation == normalActivation)
        state.isDetached = true
        state.resetWindowSize()
        #expect(state.miniplayerQueueActivation == 1)
        state.toggleMiniplayerPanel(.queue)
        state.toggleMiniplayerPanel(.queue)
        #expect(state.miniplayerQueueActivation == 2)
        state.toggleMiniplayerPanel(.lyrics)
        #expect(state.miniplayerPanel == .lyrics)
        state.toggleAdvanced()
        #expect(state.miniplayerPanel == nil && !state.miniplayer)
    }
}
