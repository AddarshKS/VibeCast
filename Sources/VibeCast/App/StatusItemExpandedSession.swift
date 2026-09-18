import AppKit
import OSLog

// Public macOS 27 AppKit API, bridged through Objective-C because our stable
// Swift build uses the macOS 26.5 SDK. Keep selectors identical to NSStatusItem.h;
// older systems retain the existing target/action path without emulating menu tracking.
@MainActor
final class StatusItemExpandedSession: NSObject {
    private weak var item: NSStatusItem?
    private var session: NSObject?
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}

    var isActive: Bool { session != nil }

    func install(on item: NSStatusItem) -> Bool {
        guard #available(macOS 27.0, *), item.responds(to: Self.delegateSetter) else { return false }
        self.item = item
        item.perform(Self.delegateSetter, with: self)
        return true
    }

    func cancel() {
        let current = session
        session = nil
        current?.perform(NSSelectorFromString("cancel"))
    }

    func uninstall() {
        cancel()
        item?.perform(Self.delegateSetter, with: nil)
        item = nil
    }

    @objc(statusItem:didBeginExpandedInterfaceSession:)
    func statusItem(_ item: NSStatusItem, didBegin session: NSObject) {
        guard item === self.item else { return }
        Self.log.debug("begin event=\(NSApp.currentEvent?.type.rawValue ?? 0) time=\(NSApp.currentEvent?.timestamp ?? 0) buttons=\(NSEvent.pressedMouseButtons)")
        self.session = session
        onBegin()
    }

    @objc(statusItemDidEndExpandedInterfaceSession:animated:)
    func statusItemDidEndExpandedInterfaceSession(_ item: NSStatusItem, animated: Bool) {
        guard item === self.item else { return }
        Self.log.debug("end event=\(NSApp.currentEvent?.type.rawValue ?? 0) time=\(NSApp.currentEvent?.timestamp ?? 0) buttons=\(NSEvent.pressedMouseButtons)")
        session = nil
        onEnd()
    }

    private static let delegateSetter = NSSelectorFromString("setExpandedInterfaceDelegate:")
    static let log = Logger(subsystem: "app.vibecast.mac.development", category: "status-tracking")
}
