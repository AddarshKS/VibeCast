import AppKit
import SwiftUI

// Keep native text editing, but do not automatically focus the first field in a new host window.
struct ComposerFocusBoundary: NSViewRepresentable {
    var focused: FocusState<Bool>.Binding

    func makeNSView(context: Context) -> FocusView {
        let view = FocusView()
        view.clearFocus = { focused.wrappedValue = false }
        return view
    }
    func updateNSView(_ view: FocusView, context: Context) {
        view.clearFocus = { focused.wrappedValue = false }
    }
    static func dismantleNSView(_ view: FocusView, coordinator: ()) { view.stop() }

    final class FocusView: NSView {
        var clearFocus: () -> Void = {}
        private var monitor: Any?
        private var resignObserver: NSObjectProtocol?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, self.window === window else { return }
                self.clearFocus()
                window?.makeFirstResponder(window)
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                if !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                    self.clearFocus()
                    self.window?.makeFirstResponder(self.window)
                }
                return event
            }
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.clearFocus() }
                }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
            monitor = nil
            resignObserver = nil
        }
    }
}
