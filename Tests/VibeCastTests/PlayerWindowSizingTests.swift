import Testing
@testable import VibeCast

@MainActor
struct PlayerWindowSizingTests {
    @Test func lyricsModePulsesOnlyBeforeEntering() throws {
        for active in [false, true] {
            for hintHovered in [false, true] {
                let button = LyricsModeButton(active: active, hintHovered: hintHovered, action: {})
                let control = try #require(button.body as? PlayerIconButton)
                #expect(control.active == active)
                #expect(control.pulsesOnHover == !active)
                #expect(control.externallyHovered == hintHovered)
            }
        }
    }

    @Test func queueActivationChangesOnlyWhenOpeningTheQueue() {
        let state = PlayerPresentation()
        state.selectPanel(.queue)
        let first = state.queueActivation
        state.isDetached = true
        state.selectPanel(.queue)
        #expect(state.queueActivation == first)
        state.selectPanel(nil)
        state.selectPanel(.queue)
        #expect(state.queueActivation == first + 1)
        state.panel = .lyrics
        state.panel = .queue
        #expect(state.queueActivation == first + 2)
    }

    @Test func compactControlsAndLyricsHeaderFit() {
        let density = PlayerPresentation.density
        #expect(PlayerPresentation.width == 340)
        let row = density.width - 2 * density.inset - 24
        #expect(6 * density.buttonSize + 38 + 6 * 4 <= row)
        #expect(density.buttonSize >= 28)
        #expect(density.lyricsReserve == 46)
    }

    @Test func onlyDetachedFocusedLyricsAcceptsManualResizing() {
        let state = PlayerPresentation()
        for detached in [false, true] {
            state.isDetached = detached
            for panel in [nil, PlayerPanel.queue, .lyrics, .outputs] {
                state.selectPanel(panel)
                #expect(state.isHeightLocked)
                state.recordResize(500)
                #expect(state.focusedHeight == nil)
                #expect(state.desiredHeight(natural: 350) == 350)
                #expect(state.desiredHeight(natural: 480) == 480)
            }
            state.toggleMiniplayer()
            #expect(state.isHeightLocked)
            state.recordResize(500)
            #expect(state.focusedHeight == nil)
            state.selectPanel(.lyrics)
            state.toggleLyricsFocus()
            #expect(state.isHeightLocked == !detached)
            state.recordResize(500)
            #expect(state.focusedHeight == (detached ? 500 : nil))
            state.resetWindowSize()
        }
    }

    @Test func lyricsSizeIsRememberedOnlyUntilRedocking() {
        let state = PlayerPresentation()
        state.isDetached = true
        state.selectPanel(.lyrics)
        state.windowHeight = 540
        state.toggleLyricsFocus()
        #expect(state.desiredHeight(natural: 540) == 540)
        state.recordResize(620)
        state.toggleLyricsFocus()
        #expect(state.desiredHeight(natural: 540) == 540)
        state.toggleLyricsFocus()
        #expect(state.desiredHeight(natural: 540) == 620)
        state.isDetached = false
        state.resetWindowSize()
        #expect(state.lyricsFocused)
        #expect(state.focusedHeight == nil)
        #expect(state.desiredHeight(natural: 540) == 540)
    }

    @Test func composerExistsOnlyOnLandingAndDeveloperView() {
        let state = PlayerPresentation()
        #expect(state.showsComposer)
        for panel in [PlayerPanel.queue, .lyrics, .outputs] {
            state.selectPanel(panel)
            #expect(!state.showsComposer)
        }
        state.toggleMiniplayer()
        #expect(!state.showsComposer)
        state.toggleAdvanced()
        #expect(state.advanced && state.showsComposer && !state.miniplayer)
        state.toggleAdvanced()
        #expect(state.panel == nil && state.showsComposer)
    }

    @Test func miniplayerSurvivesContainerChangesAndPanelActionsExitIt() {
        let state = PlayerPresentation()
        state.selectPanel(.lyrics)
        state.toggleLyricsFocus()
        state.toggleMiniplayer()
        #expect(state.layout == .miniplayer && !state.lyricsFocused && state.panel == nil)
        for detached in [true, false, true] {
            state.isDetached = detached
            state.resetWindowSize()
            #expect(state.layout == .miniplayer)
            #expect(state.isHeightLocked)
        }
        for panel in [PlayerPanel.queue, .lyrics, .outputs] {
            state.selectPanel(panel)
            #expect(!state.miniplayer && state.panel == panel)
            state.toggleMiniplayer()
        }
        state.toggleMiniplayer()
        #expect(state.layout == .standard && state.panel == nil)
    }

    @Test func focusedHeightIsClampedToScreenAndMinimum() {
        let state = PlayerPresentation()
        state.isDetached = true
        state.selectPanel(.lyrics)
        state.toggleLyricsFocus()
        state.recordResize(100)
        #expect(state.desiredHeight(natural: 500) == 344)
        state.recordResize(10000)
        #expect(state.desiredHeight(natural: 500) == 680)
        state.maximumHeight = 550
        #expect(state.desiredHeight(natural: 500) == 550)
        state.maximumHeight = 300
        #expect(state.desiredHeight(natural: 500) == 300)
    }
}
