import Testing
@testable import VibeCast

@MainActor
struct PlayerWindowSizingTests {
    @Test(arguments: [PlayerPanel.queue, .lyrics])
    func readingPanelTemporarilyOverridesSizeAndRestoresTheStandardHeight(panel: PlayerPanel) {
        let state = PlayerPresentation()
        state.isDetached = true
        #expect(state.desiredHeight(natural: 480) == 480)
        state.recordResize(405)
        state.selectPanel(panel)
        #expect(state.isHeightLocked)
        #expect(state.desiredHeight(natural: 670) == 670)
        state.recordResize(500)
        state.selectPanel(nil)
        #expect(state.desiredHeight(natural: 480) == 405)
        state.resetWindowSize()
        state.selectPanel(panel)
        #expect(state.desiredHeight(natural: 670) == 670)
        state.selectPanel(nil)
        #expect(state.desiredHeight(natural: 480) == 480)
    }

    @Test func focusedLyricsKeepsItsOwnHeightAndPanelButtonsExitIt() {
        let state = PlayerPresentation()
        state.isDetached = true
        state.recordResize(430)
        state.selectPanel(.lyrics)
        state.windowHeight = state.desiredHeight(natural: 670)
        state.toggleLyricsFocus()
        #expect(state.layout == .focusedLyrics)
        #expect(!state.isHeightLocked)
        #expect(state.desiredHeight(natural: 670) == 670)
        state.recordResize(600)
        state.toggleLyricsFocus()
        #expect(state.layout == .lyrics)
        #expect(state.isHeightLocked)
        #expect(state.desiredHeight(natural: 670) == 670)
        #expect(state.standardHeight == 430)
        state.toggleLyricsFocus()
        #expect(state.desiredHeight(natural: 670) == 600)
        state.selectPanel(.queue)
        #expect(!state.lyricsFocused)
        #expect(state.layout == .queue)
        state.selectPanel(.lyrics)
        state.toggleLyricsFocus()
        state.selectPanel(.lyrics)
        #expect(!state.lyricsFocused)
        #expect(state.panel == .lyrics)
    }

    @Test func returningToMenuBarResetsOnlySizesAndPreservesLyricsMode() {
        let state = PlayerPresentation()
        state.selectPanel(.lyrics)
        state.toggleLyricsFocus()
        #expect(state.lyricsFocused)
        #expect(state.layout == .focusedLyrics)
        #expect(state.isHeightLocked)
        state.recordResize(600)
        #expect(state.focusedHeight == nil)
        state.isDetached = true
        state.selectPanel(nil)
        state.recordResize(470)
        state.selectPanel(.lyrics)
        state.toggleLyricsFocus()
        state.recordResize(630)
        state.isDetached = false
        state.resetWindowSize()
        #expect(state.standardHeight == nil)
        #expect(state.focusedHeight == nil)
        #expect(state.windowHeight == nil)
        #expect(state.lyricsFocused)
        #expect(state.layout == .focusedLyrics)
        #expect(state.isHeightLocked)
        state.isDetached = true
        #expect(state.desiredHeight(natural: 480) == 480)
        state.selectPanel(.queue)
        state.toggleLyricsFocus()
        #expect(state.layout == .queue)
    }

    @Test func windowSizeResetDoesNotResetPanelsOrDeveloperView() {
        let state = PlayerPresentation()
        for panel in [nil, PlayerPanel.queue, .lyrics, .outputs] {
            for advanced in [false, true] {
                state.selectPanel(panel)
                state.advanced = advanced
                for detached in [true, false] {
                    state.isDetached = detached
                    state.resetWindowSize()
                    #expect(state.panel == panel)
                    #expect(state.advanced == advanced)
                }
            }
        }
    }

    @Test func heightsStayInsideDisplayAndShareTheMinimum() {
        let state = PlayerPresentation()
        state.isDetached = true
        for focused in [false, true] {
            state.selectPanel(focused ? .lyrics : nil)
            if focused { state.toggleLyricsFocus() }
            state.recordResize(100)
            #expect(state.desiredHeight(natural: 500) == 405)
            state.recordResize(10000)
            #expect(state.desiredHeight(natural: 500) == 680)
            state.maximumHeight = 550
            #expect(state.desiredHeight(natural: 500) == 550)
            state.maximumHeight = 680
        }
    }
}
