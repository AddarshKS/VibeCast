import AppKit
import Testing
@testable import VibeCast

@MainActor
extension PresentationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"))
    func forwardedStatusClicksLeaveDismissalToTheButton() async throws {
        let (controller, anchor) = try await statusToggleFixture()
        defer { controller.close() }
        for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown] {
            controller.showPopover(anchoredAt: anchor)
            let event = try #require(NSEvent.mouseEvent(with: type,
                location: NSPoint(x: anchor.midX, y: anchor.midY), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1))
            #expect(controller.handlePopoverEvent(event) === event)
            #expect(controller.popover.isShown, "A forwarded status click must not close before the button toggles.")
            controller.togglePopover()
            #expect(!controller.popover.isShown)
            #expect(!controller.isMonitoringPopoverDismissal)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"))
    func globalClicksAndDeactivationCannotDoubleHandleTheStatusButton() async throws {
        let (controller, anchor) = try await statusToggleFixture()
        defer { controller.close() }
        let center = NSPoint(x: anchor.midX, y: anchor.midY)
        for type in [NSEvent.EventType.leftMouseDown, .rightMouseDown] {
            controller.showPopover(anchoredAt: anchor)
            let event = try #require(NSEvent.mouseEvent(with: type, location: center,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            controller.handleGlobalPopoverClick(event)
            controller.handleApplicationDeactivation(mouseLocation: center, pressedMouseButtons: type == .leftMouseDown ? 1 : 2)
            try await Task.sleep(for: .milliseconds(30))
            #expect(controller.popover.isShown)
            controller.togglePopover()
            #expect(!controller.popover.isShown)
        }
        controller.showPopover(anchoredAt: anchor)
        let otherIcon = try #require(NSEvent.mouseEvent(with: .leftMouseDown,
            location: NSPoint(x: anchor.maxX + 12, y: anchor.midY), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
            eventNumber: 2, clickCount: 1, pressure: 1))
        controller.handleGlobalPopoverClick(otherIcon)
        #expect(!controller.popover.isShown, "Other menu-bar icons must still dismiss the dropdown.")
        #expect(!controller.isMonitoringPopoverDismissal)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"))
    func forwardedStatusClickInAnotherWindowUsesScreenCoordinates() async throws {
        let (controller, anchor) = try await statusToggleFixture()
        let proxy = NSWindow(contentRect: anchor, styleMask: .borderless, backing: .buffered, defer: false)
        proxy.isReleasedWhenClosed = false
        proxy.orderFront(nil)
        defer { controller.close(); proxy.close() }
        controller.showPopover(anchoredAt: anchor)
        let center = NSPoint(x: anchor.midX, y: anchor.midY)
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown,
            location: proxy.convertPoint(fromScreen: center), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: proxy.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        #expect(event.window === proxy)
        #expect(controller.handlePopoverEvent(event) === event)
        #expect(controller.popover.isShown)
        controller.togglePopover()
        #expect(!controller.popover.isShown)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"))
    func delayedDeactivationCannotDismissAReopenedOrDetachedPlayer() async throws {
        let (controller, anchor) = try await statusToggleFixture()
        defer { controller.close() }
        let center = NSPoint(x: anchor.midX, y: anchor.midY)
        controller.showPopover(anchoredAt: anchor)
        controller.handleApplicationDeactivation(mouseLocation: .zero, pressedMouseButtons: 0)
        #expect(controller.popover.isShown, "Allow the current icon action to finish before handling activation loss.")
        controller.togglePopover()
        #expect(!controller.popover.isShown)
        controller.showPopover(anchoredAt: anchor)
        try await Task.sleep(for: .milliseconds(30))
        #expect(controller.popover.isShown, "An old activation callback cannot close a later opening.")

        // Merely hovering the icon cannot block Cmd-Tab or other activation loss.
        controller.handleApplicationDeactivation(mouseLocation: center, pressedMouseButtons: 0)
        try await Task.sleep(for: .milliseconds(30))
        #expect(!controller.popover.isShown)

        controller.showPopover(anchoredAt: anchor)
        controller.handleApplicationDeactivation(mouseLocation: .zero, pressedMouseButtons: 0)
        controller.togglePlayerWindow()
        try await Task.sleep(for: .milliseconds(30))
        #expect(controller.playerWindow?.isVisible == true)
        #expect(controller.playerPresentation.isDetached)
        controller.togglePopover()
        #expect(controller.playerWindow?.isVisible == true, "A detached player is raised, not hidden, by the icon.")
    }

    private func statusToggleFixture() async throws -> (MenuBarController, NSRect) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let (store, _, _, _, _) = try await StoreTests().fixture()
        let controller = MenuBarController(store: store, usesNativeStatusTracking: false)
        let button = try #require(controller.statusItem.button)
        let window = try #require(button.window)
        let actual = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = try #require(NSScreen.main)
        let anchor = NSScreen.screens.contains(where: { $0.frame.intersects(actual) }) ? actual :
            NSRect(x: screen.visibleFrame.maxX - 100, y: screen.frame.maxY - 24, width: 24, height: 22)
        return (controller, anchor)
    }
}
