import AppKit
import Testing
@testable import VibeCast

extension PresentationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"))
    func dropdownUsesNonactivatingPanelAndDetachedPlayerStaysOnItsSpace() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let screen = try #require(NSScreen.main)
        let (store, _, _, _, _) = try await StoreTests().fixture()
        let controller = MenuBarController(store: store)
        defer { controller.close() }
        let previousApp = NSWorkspace.shared.frontmostApplication?.processIdentifier
        controller.showPopover(anchoredAt: NSRect(x: screen.visibleFrame.maxX - 100,
                                                y: screen.visibleFrame.maxY - 24, width: 36, height: 22))
        try await Task.sleep(for: .milliseconds(150))
        let panel = try #require(controller.popover.contentViewController?.view.window as? NSPanel)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.becomesKeyOnlyIfNeeded)
        #expect(panel.acceptsMouseMovedEvents)
        #expect(panel.canBecomeKey, "Clicking the composer must still allow keyboard input.")
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == previousApp)
        let host = try #require(controller.popover.contentViewController?.view)
        let composerPoint = host.convert(NSPoint(x: 70, y: host.bounds.maxY - 35), to: nil)
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: composerPoint,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let hitPoint = host.convert(NSPoint(x: 70, y: host.bounds.maxY - 35), to: host.superview)
        let composer = try #require(host.hitTest(hitPoint))
        #expect(composer.acceptsFirstMouse(for: down), "The composer must accept its initial click.")
        #expect(composer.needsPanelToBecomeKey, "The composer must be able to request keyboard focus.")
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == previousApp)
        controller.togglePlayerWindow()
        try await Task.sleep(for: .milliseconds(150))
        let player = try #require(controller.playerWindow)
        #expect(player.canBecomeMain && player.canBecomeKey)
        #expect(player.level == .normal)
        #expect(!player.collectionBehavior.contains(.moveToActiveSpace))
        #expect(!player.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(!player.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(player.collectionBehavior.contains(.managed))
        let frame = player.frame
        controller.togglePopover()
        try await Task.sleep(for: .milliseconds(150))
        #expect(player.frame == frame, "Reopening a detached player must not reposition it.")
        controller.returnToMenuBar()
        try await Task.sleep(for: .milliseconds(150))
        let restored = try #require(controller.popover.contentViewController?.view.window as? NSPanel)
        #expect(restored.styleMask.contains(.nonactivatingPanel))
        #expect(restored.becomesKeyOnlyIfNeeded)
        #expect(restored.acceptsMouseMovedEvents)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"))
    func switchingExternalAppsDismissesOnlyTheDropdown() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let screen = try #require(NSScreen.main)
        let (store, _, _, _, _) = try await StoreTests().fixture()
        let controller = MenuBarController(store: store)
        defer { controller.close() }
        let otherApp = try #require(NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && $0.processIdentifier != NSWorkspace.shared.frontmostApplication?.processIdentifier
                && $0.activationPolicy == .regular
        })
        let anchor = NSRect(x: screen.visibleFrame.maxX - 100, y: screen.visibleFrame.maxY - 24, width: 36, height: 22)
        let center = NSWorkspace.shared.notificationCenter
        controller.showPopover(anchoredAt: anchor)
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        #expect(controller.popover.isShown)
        if let currentApp = NSWorkspace.shared.frontmostApplication {
            center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                        userInfo: [NSWorkspace.applicationUserInfoKey: currentApp])
            #expect(controller.popover.isShown, "A delayed notification for the already-active app is not an app switch.")
        }
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: [NSWorkspace.applicationUserInfoKey: otherApp])
        #expect(!controller.popover.isShown)
        #expect(!controller.isMonitoringPopoverDismissal)
        controller.showPopover(anchoredAt: anchor)
        controller.togglePlayerWindow()
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: [NSWorkspace.applicationUserInfoKey: otherApp])
        #expect(controller.playerWindow?.isVisible == true)
        #expect(controller.playerPresentation.isDetached)
    }
}
