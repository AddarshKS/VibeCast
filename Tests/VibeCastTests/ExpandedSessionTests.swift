import AppKit
import SwiftUI
import Testing
@testable import VibeCast

extension PresentationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"),
          arguments: [false, true])
    func nativeStatusReclickClosesWithoutSystemEndCallback(globalDelivery: Bool) async throws {
        guard #available(macOS 27.0, *) else { return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let (store, _, _, _, _) = try await StoreTests().fixture()
        let controller = MenuBarController(store: store)
        defer { controller.close() }
        let session = try #require(controller.expandedSession)
        let button = try #require(controller.statusItem.button)
        let window = try #require(button.window)
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let tracking = ExpandedSessionStub()
        tracking.onCancel = { [weak controller, weak session] in
            guard let controller else { return }
            session?.statusItemDidEndExpandedInterfaceSession(controller.statusItem, animated: false)
        }
        for iteration in 1...3 {
            session.statusItem(controller.statusItem, didBegin: tracking)
            #expect(controller.popover.isShown)
            for (type, flags) in [(NSEvent.EventType.rightMouseDown, NSEvent.ModifierFlags()),
                                  (.leftMouseDown, .control)] {
                let contextClick = try #require(NSEvent.mouseEvent(with: type,
                    location: NSPoint(x: rect.midX, y: rect.midY), modifierFlags: flags,
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                    eventNumber: iteration, clickCount: 1, pressure: 1))
                controller.handleGlobalPopoverClick(contextClick)
                #expect(controller.handlePopoverEvent(contextClick) === contextClick)
                #expect(controller.popover.isShown, "Contextual clicks must be left to the menu handler.")
            }
            let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown,
                location: NSPoint(x: rect.midX, y: rect.midY), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                eventNumber: iteration, clickCount: 1, pressure: 1))
            // Observed on macOS 27: the system delivers the click globally but
            // does not end the expanded session. Do not fabricate an end callback.
            if globalDelivery { controller.handleGlobalPopoverClick(click) }
            else { #expect(controller.handlePopoverEvent(click) == nil) }
            #expect(!controller.popover.isShown)
            #expect(!session.isActive)
            #expect(tracking.cancellations == iteration)
            #expect(!controller.isMonitoringPopoverDismissal)
            #expect(controller.anchorWindow?.isVisible == false)
            // A late system dismissal must be harmless, not a second toggle.
            session.statusItemDidEndExpandedInterfaceSession(controller.statusItem, animated: true)
            #expect(!controller.popover.isShown)
        }
        controller.showPopover(anchoredAt: rect)
        controller.togglePlayerWindow()
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown,
            location: NSPoint(x: rect.midX, y: rect.midY), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
            eventNumber: 4, clickCount: 1, pressure: 1))
        controller.handleGlobalPopoverClick(click)
        #expect(controller.playerWindow?.isVisible == true)
        controller.returnToMenuBar()
        #expect(controller.popover.isShown)
        controller.handleGlobalPopoverClick(click)
        #expect(!controller.popover.isShown, "Redocked dropdowns also close on the first icon click.")
        #expect(tracking.cancellations == 3, "Redocking has no active native session to cancel twice.")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"))
    func statusItemSessionCallbacksOpenCloseAndCancelOnDetach() async throws {
        guard #available(macOS 27.0, *) else { return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let (store, _, _, _, _) = try await StoreTests().fixture()
        let controller = MenuBarController(store: store)
        defer { controller.close() }
        let session = try #require(controller.expandedSession)
        let button = try #require(controller.statusItem.button)
        #expect(button.menu == nil)
        #expect(controller.statusItem.menu == nil)
        #expect(!session.isActive)
        let tracking = ExpandedSessionStub()
        tracking.onCancel = { [weak session, weak controller] in
            guard let controller else { return }
            session?.statusItemDidEndExpandedInterfaceSession(controller.statusItem, animated: false)
        }
        session.statusItem(controller.statusItem, didBegin: tracking)
        try await Task.sleep(for: .milliseconds(250))
        #expect(session.isActive)
        #expect(controller.popover.isShown)
        session.statusItemDidEndExpandedInterfaceSession(controller.statusItem, animated: true)
        try await Task.sleep(for: .milliseconds(250))
        #expect(!session.isActive)
        #expect(!controller.popover.isShown)
        #expect(tracking.cancellations == 0, "System dismissal must not recursively cancel an ended session.")

        session.statusItem(controller.statusItem, didBegin: tracking)
        controller.popover.performClose(nil)
        #expect(tracking.cancellations == 1)
        #expect(!session.isActive)

        session.statusItem(controller.statusItem, didBegin: tracking)
        controller.togglePlayerWindow()
        #expect(tracking.cancellations == 2)
        #expect(!session.isActive)
        #expect(controller.playerPresentation.isDetached)
        #expect(controller.playerWindow?.isVisible == true)
        session.statusItem(controller.statusItem, didBegin: tracking)
        #expect(tracking.cancellations == 3, "Recalling a detached window must immediately release menu tracking.")
        #expect(!session.isActive)
        controller.returnToMenuBar()
        session.statusItem(controller.statusItem, didBegin: tracking)
        #expect(!controller.popover.isShown, "The first icon click must close a programmatically redocked dropdown.")
        #expect(tracking.cancellations == 4)
        session.statusItem(controller.statusItem, didBegin: tracking)
        controller.close()
        #expect(tracking.cancellations == 5)
        #expect(!session.isActive)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"))
    func seekBarDoesNotGlowWhenPopoverOpensWithoutPointerInteraction() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = SpotifyPlayback(isPlaying: false, item: PlayerTests.track,
            device: SpotifyDevice(id: "test", name: "This Mac", isActive: true, isRestricted: false),
            shuffleState: false, repeatState: "off", progressMS: 74000)
        await store.refreshPlayback()
        let host = NSHostingController(rootView: PlaybackSeekBar(store: store).padding(12).preferredColorScheme(.dark))
        let popover = NSPopover()
        popover.contentViewController = host
        popover.contentSize = NSSize(width: 300, height: 65)
        popover.animates = false
        let screen = try #require(NSScreen.main)
        let anchor = NSPanel(contentRect: NSRect(x: screen.visibleFrame.minX + 40,
            y: screen.visibleFrame.midY, width: 30, height: 24),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let anchorView = NSView(frame: NSRect(x: 0, y: 0, width: 30, height: 24))
        anchor.contentView = anchorView
        anchor.orderFrontRegardless()
        defer { popover.close(); anchor.orderOut(nil) }
        for _ in 0..<2 {
            popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
            host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
            var tealPixels = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.greenComponent > color.redComponent + 0.15 && color.blueComponent > color.redComponent + 0.15 {
                        tealPixels += 1
                    }
                }
            }
            #expect(tealPixels == 0, "An idle seek bar must not look hovered just because its popover opened.")
            popover.close()
        }
    }
}

@MainActor
private final class ExpandedSessionStub: NSObject {
    var cancellations = 0
    var onCancel: () -> Void = {}
    @objc func cancel() { cancellations += 1; onCancel() }
}
