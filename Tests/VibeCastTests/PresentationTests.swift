import AppKit
import SwiftUI
import Testing
@testable import VibeCast

@MainActor
@Suite(.serialized)
struct PresentationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"))
    func dropdownReadingPanelsAndLyricsModeKeepTheirAnchorAndAllocatedHeight() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let screen = try #require(NSScreen.main)
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = SpotifyPlayback(isPlaying: true, item: PlayerTests.track, device: nil,
                                           shuffleState: false, repeatState: "off")
        await store.refreshPlayback()
        let controller = MenuBarController(store: store)
        defer { controller.close() }
        controller.showPopover(anchoredAt: NSRect(x: screen.visibleFrame.maxX - 100,
                                                y: screen.visibleFrame.maxY - 24, width: 36, height: 22))
        try await Task.sleep(for: .milliseconds(150))
        let window = try #require(controller.popover.contentViewController?.view.window)
        let initial = window.frame
        let state = controller.playerPresentation
        for panel in [PlayerPanel.queue, .lyrics, .queue, .lyrics] {
            state.selectPanel(panel)
            // Sample throughout growth, not just its settled frame.
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(8))
                #expect(controller.popover.isShown)
                #expect(abs(window.frame.minX - initial.minX) < 2)
                #expect(abs(window.frame.maxY - initial.maxY) < 2)
                #expect(state.windowHeight == controller.popover.contentSize.height)
            }
            #expect(window.frame.height > initial.height)
            if panel == .lyrics {
                let lyricsFrame = window.frame
                for _ in 0..<2 {
                    withAnimation(.easeInOut(duration: 0.45)) { state.toggleLyricsFocus() }
                    #expect(state.layout == .focusedLyrics)
                    #expect(state.isHeightLocked)
                    for _ in 0..<30 {
                        try await Task.sleep(for: .milliseconds(16))
                        #expect(window.frame == lyricsFrame)
                        #expect(controller.popover.isShown)
                    }
                    withAnimation(.easeInOut(duration: 0.45)) { state.toggleLyricsFocus() }
                    try await Task.sleep(for: .milliseconds(500))
                    #expect(window.frame == lyricsFrame)
                }
            }
            state.selectPanel(nil)
            try await Task.sleep(for: .milliseconds(150))
            #expect(abs(window.frame.height - initial.height) < 2)
        }
        state.selectPanel(.lyrics)
        try await Task.sleep(for: .milliseconds(150))
        state.toggleLyricsFocus()
        try await Task.sleep(for: .milliseconds(150))
        let dropdownHeight = controller.popover.contentSize.height
        let host = controller.popover.contentViewController
        controller.togglePlayerWindow()
        try await Task.sleep(for: .milliseconds(150))
        let player = try #require(controller.playerWindow)
        #expect(player.contentViewController === host)
        #expect(state.layout == .focusedLyrics)
        #expect(player.frame.height == dropdownHeight)
        #expect(!state.isHeightLocked)
        #expect(player.styleMask.contains(.resizable))
        #expect(controller.windowWillResize(player, to: NSSize(width: 700, height: 200)) == NSSize(width: 400, height: 405))
        player.setContentSize(NSSize(width: 400, height: 540))
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.focusedHeight == 540)
        controller.returnToMenuBar()
        try await Task.sleep(for: .milliseconds(150))
        #expect(state.layout == .focusedLyrics)
        #expect(state.focusedHeight == nil)
        #expect(state.isHeightLocked)
        #expect(controller.popover.contentSize.height == dropdownHeight)
        #expect(controller.popover.contentViewController === host)
        #expect(controller.popover.isShown)
        controller.togglePlayerWindow()
        try await Task.sleep(for: .milliseconds(150))
        #expect(state.layout == .focusedLyrics)
        #expect(player.frame.height == dropdownHeight)
        #expect(player.styleMask.contains(.resizable))
        controller.returnToMenuBar()
        try await Task.sleep(for: .milliseconds(150))
        #expect(state.layout == .focusedLyrics)

        store.prompt = "Keep this draft through every presentation"
        for panel in [nil, PlayerPanel.queue, .lyrics, .outputs] {
            state.selectPanel(panel)
            for advanced in [false, true] {
                state.advanced = advanced
                controller.togglePlayerWindow()
                try await Task.sleep(for: .milliseconds(100))
                #expect(player.contentViewController === host)
                #expect(state.panel == panel && state.advanced == advanced)
                controller.returnToMenuBar()
                try await Task.sleep(for: .milliseconds(100))
                #expect(controller.popover.contentViewController === host)
                #expect(state.panel == panel && state.advanced == advanced)
                #expect(store.prompt == "Keep this draft through every presentation")
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"))
    func popoverDismissalHandlesStatusClicksEscapeAndExternalAppsWithoutClosingDetachedPlayer() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let screen = try #require(NSScreen.main)
        let (store, _, _, _, _) = try await StoreTests().fixture()
        let controller = MenuBarController(store: store)
        defer { controller.close() }
        let anchor = NSRect(x: screen.visibleFrame.maxX - 100, y: screen.visibleFrame.maxY - 24, width: 36, height: 22)
        #expect(controller.popover.behavior == .applicationDefined)
        #expect(!controller.isMonitoringPopoverDismissal)
        controller.showPopover(anchoredAt: anchor)
        try await Task.sleep(for: .milliseconds(100))
        #expect(controller.isMonitoringPopoverDismissal)
        let content = try #require(controller.popover.contentViewController?.view.window)
        let inside = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 50, y: 50),
            modifierFlags: [], timestamp: 1, windowNumber: content.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        #expect(controller.handlePopoverEvent(inside) === inside)
        #expect(controller.popover.isShown)

        let button = try #require(controller.statusItem.button)
        let statusWindow = try #require(button.window)
        let statusClick = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: button.frame.origin,
            modifierFlags: [], timestamp: 2, windowNumber: statusWindow.windowNumber, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 1))
        #expect(controller.handlePopoverEvent(statusClick) === statusClick)
        #expect(controller.popover.isShown, "The local monitor must leave the icon toggle to the button.")
        #expect(button.sendAction(button.action, to: button.target))
        #expect(!controller.popover.isShown)
        #expect(!controller.isMonitoringPopoverDismissal)
        #expect(controller.anchorWindow?.isVisible == false)

        // Right-side system status icons use the external-click path without
        // necessarily resigning our application's active state.
        for _ in 0..<3 {
            controller.showPopover(anchoredAt: anchor)
            #expect(controller.isMonitoringPopoverDismissal)
            controller.dismissPopoverForExternalInteraction()
            #expect(!controller.popover.isShown)
            #expect(!controller.isMonitoringPopoverDismissal)
        }
        controller.showPopover(anchoredAt: anchor)
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 3,
            windowNumber: content.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        #expect(controller.handlePopoverEvent(escape) == nil)
        #expect(!controller.popover.isShown)

        controller.showPopover(anchoredAt: anchor)
        let outside = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 4, windowNumber: 0, context: nil,
            eventNumber: 4, clickCount: 1, pressure: 1))
        #expect(controller.handlePopoverEvent(outside) === outside, "Outside clicks must still reach their destination.")
        #expect(!controller.popover.isShown)

        controller.showPopover(anchoredAt: anchor)
        controller.togglePlayerWindow()
        #expect(!controller.isMonitoringPopoverDismissal)
        controller.dismissPopoverForExternalInteraction()
        #expect(controller.playerWindow?.isVisible == true)
        #expect(controller.playerPresentation.isDetached)
        #expect(!controller.isMonitoringPopoverDismissal)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"))
    func resizingRetainsOnscreenAnchorAcrossContentChanges() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let screen = try #require(NSScreen.main)
        // The CLI runner's extra status item can be hidden by a crowded menu bar.
        // Use a real on-screen NSView to exercise the same native resize path.
        let anchorWindow = NSWindow(contentRect: NSRect(x: screen.visibleFrame.maxX - 60,
                                                       y: screen.visibleFrame.maxY - 24, width: 36, height: 22),
                                    styleMask: .borderless, backing: .buffered, defer: false)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 36, height: 22))
        anchorWindow.contentView = anchor
        anchorWindow.orderFrontRegardless()
        let (store, _, _, _, _) = try await StoreTests().fixture()
        let controller = MenuBarController(store: store)
        defer { controller.close(); anchorWindow.orderOut(nil) }
        controller.popover.behavior = .applicationDefined
        controller.showPopover(anchoredAt: anchorWindow.frame)
        try await Task.sleep(for: .milliseconds(150))
        let window = try #require(controller.popover.contentViewController?.view.window)
        let initial = window.frame
        let stableAnchor = try #require(controller.anchorWindow)
        let originalAnchorFrame = stableAnchor.frame
        let originalPositioningRect = controller.popover.positioningRect
        anchorWindow.setFrameOrigin(NSPoint(x: -2000, y: screen.frame.maxY + 200))
        anchorWindow.orderOut(nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(stableAnchor.frame == originalAnchorFrame)
        #expect(controller.popover.positioningRect == originalPositioningRect)
        #expect(abs(window.frame.midX - initial.midX) < 2)
        let compactHeight = controller.popover.contentSize.height
        for _ in 0..<3 {
            store.prompt = String(repeating: "Music for an evening drive. ", count: 12)
            try await Task.sleep(for: .milliseconds(80))
            #expect(controller.popover.contentSize.height > compactHeight)
            #expect(abs(window.frame.maxY - initial.maxY) < 2)
            #expect(abs(window.frame.midX - initial.midX) < 2)
            store.prompt = ""
            try await Task.sleep(for: .milliseconds(80))
            #expect(abs(controller.popover.contentSize.height - compactHeight) < 2)
            #expect(abs(window.frame.maxY - initial.maxY) < 2)
            #expect(abs(window.frame.midX - initial.midX) < 2)
        }
        controller.popover.performClose(nil)
        #expect(!stableAnchor.isVisible)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"))
    func detachedPlayerReusesContentAndReturnsWithoutQuitting() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let screen = try #require(NSScreen.main)
        let (store, _, _, _, _) = try await StoreTests().fixture()
        store.prompt = "Keep this draft"
        let controller = MenuBarController(store: store)
        defer { controller.close() }
        controller.popover.behavior = .applicationDefined
        controller.showPopover(anchoredAt: NSRect(x: screen.visibleFrame.maxX - 100,
                                                y: screen.visibleFrame.maxY - 24, width: 36, height: 22))
        try await Task.sleep(for: .milliseconds(150))
        let host = try #require(controller.popover.contentViewController)
        controller.togglePlayerWindow()
        try await Task.sleep(for: .milliseconds(150))
        let player = try #require(controller.playerWindow)
        #expect(controller.playerPresentation.isDetached)
        #expect(!controller.popover.isShown)
        #expect(controller.anchorWindow?.isVisible == false)
        #expect(controller.popover.contentViewController == nil)
        #expect(player.contentViewController === host)
        #expect(player.level == .normal)
        #expect(player.canBecomeKey && player.canBecomeMain)
        #expect(player.isVisible)
        #expect(!player.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(store.prompt == "Keep this draft")
        let target = NSPoint(x: screen.visibleFrame.midX - 200, y: screen.visibleFrame.midY - 200)
        player.setFrameOrigin(target)
        let moved = player.frame
        player.orderOut(nil)
        controller.togglePopover()
        #expect(player.isVisible)
        #expect(player.frame == moved)
        #expect(!controller.popover.isShown)
        controller.showSettings()
        #expect(player.contentViewController === host)
        #expect(controller.settingsWindow?.isVisible == true)
        controller.settingsWindow?.close()
        player.performClose(nil)
        #expect(!controller.playerPresentation.isDetached)
        #expect(!player.isVisible)
        #expect(controller.popover.isShown)
        #expect(controller.popover.contentViewController === host)
        #expect(store.prompt == "Keep this draft")
        controller.togglePlayerWindow()
        #expect(controller.playerWindow === player)
        #expect(player.contentViewController === host)
        #expect(player.frame.origin == moved.origin)
        controller.togglePlayerWindow()
        #expect(!player.isVisible)
        #expect(controller.popover.isShown)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"))
    func detachedWindowResizesOnlyVerticallyAndRestoresHeightAcrossPanels() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let screen = try #require(NSScreen.main)
        let (store, _, _, _, _) = try await StoreTests().fixture()
        let controller = MenuBarController(store: store)
        defer { controller.close() }
        controller.popover.behavior = .applicationDefined
        controller.showPopover(anchoredAt: NSRect(x: screen.visibleFrame.maxX - 100,
                                                y: screen.visibleFrame.maxY - 24, width: 36, height: 22))
        try await Task.sleep(for: .milliseconds(150))
        controller.togglePlayerWindow()
        try await Task.sleep(for: .milliseconds(150))
        let window = try #require(controller.playerWindow)
        let state = controller.playerPresentation
        #expect(window.styleMask.contains(.resizable))
        #expect(controller.windowWillResize(window, to: NSSize(width: 900, height: 200)) == NSSize(width: 400, height: 405))
        let originalTop = window.frame.maxY
        window.setFrame(NSRect(x: window.frame.minX, y: originalTop - 405, width: 400, height: 405), display: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.standardHeight == 405)
        let customFrame = window.frame
        for panel in [PlayerPanel.queue, .lyrics, .queue, .lyrics] {
            state.selectPanel(panel)
            try await Task.sleep(for: .milliseconds(150))
            #expect(window.frame.height > 405)
            #expect(!window.styleMask.contains(.resizable))
            #expect(window.frame.width == 400)
            #expect(abs(window.frame.maxY - customFrame.maxY) < 2)
            #expect(abs(window.frame.minX - customFrame.minX) < 2)
            #expect(controller.windowWillResize(window, to: NSSize(width: 600, height: 420)) == window.frame.size)
            state.selectPanel(nil)
            try await Task.sleep(for: .milliseconds(150))
            #expect(window.frame.height == 405)
            #expect(window.styleMask.contains(.resizable))
            #expect(controller.windowWillResize(window, to: NSSize(width: 100, height: 200)) == NSSize(width: 400, height: 405))
        }
        state.selectPanel(.lyrics)
        state.toggleLyricsFocus()
        try await Task.sleep(for: .milliseconds(150))
        window.setContentSize(NSSize(width: 400, height: 540))
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.focusedHeight == 540)
        state.toggleLyricsFocus()
        try await Task.sleep(for: .milliseconds(150))
        #expect(window.frame.height > 405)
        #expect(!window.styleMask.contains(.resizable))
        state.selectPanel(nil)
        try await Task.sleep(for: .milliseconds(150))
        #expect(window.frame.height == 405)
        controller.returnToMenuBar()
        try await Task.sleep(for: .milliseconds(150))
        #expect(controller.popover.isShown)
        #expect(state.standardHeight == nil && state.focusedHeight == nil)
        let natural = controller.popover.contentSize.height
        controller.togglePlayerWindow()
        try await Task.sleep(for: .milliseconds(150))
        #expect(window.frame.height == max(405, natural))
    }

    @Test func callbackPagesAreBrandedAndNeverClaimPrematureConnectionSuccess() throws {
        let received = SpotifyCallbackPage.html(state: .received)
        #expect(received.contains("data:image/png;base64,"))
        let logo = try #require(AppResources.bundle.url(forResource: "MenuBarAppIcon", withExtension: "png"))
        #expect(received.contains(try Data(contentsOf: logo).base64EncodedString()))
        #expect(received.contains("Back to the music."))
        #expect(received.contains("finishing your Spotify connection"))
        #expect(!received.contains("{{"))
        #expect(!received.contains("<script"))
        #expect(!received.contains("https://"))
        #expect(SpotifyCallbackPage.html(state: .denied).contains("has not been connected"))
        #expect(SpotifyCallbackPage.html(state: .expired).contains("LINK EXPIRED"))
        #expect(SpotifyCallbackPage.contentSecurityPolicy.contains("default-src 'none'"))
    }

    @Test func playerWindowAndLyricsSyncSymbolsAreAvailable() {
        for name in ["pip.enter", "pip.exit", "arrow.triangle.2.circlepath"] {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                    "Player controls must render their system symbols: \(name)")
        }
    }

    @Test func menuIconUsesTrimmedTransparentTemplateAndPreservesProportions() throws {
        let image = ResourceImage.menuBarSymbol
        #expect(image.isTemplate)
        #expect(image.size.height == 18)
        #expect((17...23).contains(image.size.width))
        let rasters = image.representations.compactMap { $0 as? NSBitmapImageRep }
        #expect(rasters.map(\.pixelsHigh).sorted() == [18, 36])
        for raster in rasters {
            #expect(raster.size == image.size)
            #expect(raster.colorAt(x: 0, y: 0)?.alphaComponent == 0)
            let solidPixels = (0..<raster.pixelsWide).reduce(0) { sum, x in
                sum + (0..<raster.pixelsHigh).filter {
                    (raster.colorAt(x: x, y: $0)?.alphaComponent ?? 0) > 0.95
                }.count
            }
            #expect(solidPixels > raster.pixelsWide, "The small-size logo must have solid ink, not only faint antialiasing.")
        }
        let source = try #require(ResourceImage.named("MenuBarAppIcon")?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let mask = try #require(ResourceImage.templateMask(source))
        #expect(mask.width < source.width)
        #expect(mask.height < source.height)
        let bitmap = NSBitmapImageRep(cgImage: mask)
        #expect(bitmap.colorAt(x: 0, y: 0)?.alphaComponent == 0)
    }

    @Test func credentialPersistenceFailureIsSpecificAndDoesNotEchoSecrets() {
        let message = ChatGPTSession.loginFailure("persist_failed: keyring failure secret-value")
        #expect(message.contains("Keychain"))
        #expect(!message.contains("secret-value"))
    }

    @Test func diagnosticLogIsBoundedAndCanBeCleared() {
        let log = DiagnosticLog()
        for i in 0..<150 { log.record("Test", "Event \(i)") }
        #expect(log.entries.count == 100)
        #expect(log.text.contains("Event 149"))
        #expect(!log.text.contains("Event 49\n"))
        log.clear()
        #expect(log.entries.isEmpty)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"))
    func popoverAndSettingsHaveIndependentStableLifetimes() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let (store, _, _, _, _) = try await StoreTests().fixture()
        let controller = MenuBarController(store: store)
        defer { controller.close() }
        let hosting = try #require(controller.popover.contentViewController as? NSHostingController<MenuBarRootView>)
        #expect(hosting.sizingOptions.isEmpty)
        try await Task.sleep(for: .milliseconds(250))
        let screen = try #require(NSScreen.main)
        let anchor = NSRect(x: screen.visibleFrame.maxX - 100, y: screen.visibleFrame.maxY - 24, width: 36, height: 22)
        controller.showPopover(anchoredAt: anchor)
        try await Task.sleep(for: .milliseconds(150))
        #expect(Bool(controller.popover.isShown))
        let initialFrame = try #require(controller.popover.contentViewController?.view.window?.frame)
        #expect(initialFrame.minX <= anchor.midX && initialFrame.maxX >= anchor.midX)
        let compactHeight = controller.popover.contentSize.height
        store.prompt = String(repeating: "Some soft rock for an evening drive. ", count: 8)
        try await Task.sleep(for: .milliseconds(250))
        #expect(controller.popover.contentSize.height > compactHeight)
        #expect(controller.popover.contentSize.height <= 680)
        let expandedFrame = try #require(controller.popover.contentViewController?.view.window?.frame)
        #expect(abs(expandedFrame.midX - initialFrame.midX) < 2)
        #expect(abs(expandedFrame.maxY - initialFrame.maxY) < 2)
        store.prompt = ""
        try await Task.sleep(for: .milliseconds(250))
        #expect(abs(controller.popover.contentSize.height - compactHeight) < 2)
        let restoredFrame = try #require(controller.popover.contentViewController?.view.window?.frame)
        #expect(abs(restoredFrame.midX - initialFrame.midX) < 2)
        #expect(abs(restoredFrame.maxY - initialFrame.maxY) < 2)
        guard let window = controller.popover.contentViewController?.view.window else {
            Issue.record("Popover did not obtain a window in the test application.")
            return
        }
        // A command-line test runner cannot reliably take foreground activation.
        #expect(window.canBecomeKey)
        // A real mouse event inside the composer must not dismiss the popover.
        for point in [NSPoint(x: 80, y: 60), NSPoint(x: 350, y: 17), NSPoint(x: 350, y: 17)] {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: type, location: point,
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
                NSApp.sendEvent(event)
            }
            #expect(Bool(controller.popover.isShown))
            #expect(abs(window.frame.midX - initialFrame.midX) < 2)
        }
        #expect(controller.popover.isShown)
        store.prompt = "hello"
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(controller.popover.isShown)
        try await Task.sleep(for: .milliseconds(250))
        #expect(abs(window.frame.midX - initialFrame.midX) < 2)
        #expect(abs(window.frame.maxY - initialFrame.maxY) < 2)
        store.prompt = String(repeating: "Another longer request. ", count: 8)
        controller.togglePopover()
        try await Task.sleep(for: .milliseconds(250))
        #expect(!controller.popover.isShown)
        controller.showPopover(anchoredAt: anchor)
        try await Task.sleep(for: .milliseconds(250))
        #expect(controller.popover.isShown)
        #expect(abs(window.frame.midX - initialFrame.midX) < 2)
        controller.showSettings()
        #expect(!controller.popover.isShown)
        #expect(controller.settingsWindow?.isVisible == true)
        let first = controller.settingsWindow
        controller.showSettings()
        #expect(controller.settingsWindow === first)
        #expect(controller.settingsWindow?.canBecomeKey == true)
        #expect(controller.settingsWindow?.styleMask.contains(.titled) == false)
        #expect(controller.settingsWindow?.standardWindowButton(.closeButton) == nil)
        try await Task.sleep(for: .milliseconds(150))
        let settings = try #require(controller.settingsWindow)
        // The unbundled runner cannot reliably activate a window or expose SwiftUI AX children.
        // Check the native close path here; pointer/VoiceOver acceptance is on the bundled app.
        settings.performClose(nil)
        #expect(controller.settingsWindow?.isVisible == false)
    }
}
