import AppKit
import SwiftUI

struct QueueScrollPhysics {
    static let revealDistance: CGFloat = 90
    static let resistance: CGFloat = 0.30
    static let snapDistance: CGFloat = 36
    var historyRevealed = false
    var pull: CGFloat = 0
    private(set) var waitingForNewGesture = false

    mutating func beginGesture() { waitingForNewGesture = false }

    mutating func drag(delta: CGFloat, offset: CGFloat, anchor: CGFloat) -> CGFloat? {
        guard anchor > 1 else { return nil }
        if historyRevealed {
            guard pull > 0 || delta > 0 else { return nil }
            pull = max(0, pull + delta)
            if pull >= Self.revealDistance {
                historyRevealed = false
                pull = 0
                return anchor
            }
            return pull * Self.resistance
        }
        // A gesture browsing the list stops at its header. A fresh pull reveals history.
        if waitingForNewGesture, delta < 0 { return offset + delta <= anchor ? anchor : nil }
        if pull == 0, offset > anchor + 0.5, offset + delta <= anchor {
            waitingForNewGesture = true
            return anchor
        }
        guard pull > 0 || offset + delta < anchor else { return nil }
        pull = max(0, pull - delta)
        if pull >= Self.revealDistance {
            historyRevealed = true
            pull = 0
            return 0
        }
        return anchor - pull * Self.resistance
    }

    mutating func settle(offset: CGFloat, anchor: CGFloat) -> CGFloat? {
        if historyRevealed {
            pull = 0
            return 0
        }
        if pull > 0 || abs(offset - anchor) <= Self.snapDistance {
            historyRevealed = false
            pull = 0
            return anchor
        }
        return nil
    }
}

// A marker on Up Next supplies its real document position. Section changes use a
// resisted pull; browsing within Up Next keeps native AppKit scrolling and momentum.
struct QueueScrollBehavior: NSViewRepresentable {
    var resetRevision: Int
    var activation: Int
    var historyCount: Int

    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) {
        if view.revision != resetRevision || view.activation != activation {
            view.needsReset = true
            view.revision = resetRevision
            view.activation = activation
        }
        view.scheduleLayout()
    }
    static func dismantleNSView(_ view: Marker, coordinator: ()) { view.stop() }

    final class Marker: NSView {
        var revision = -1
        var activation = -1
        var needsReset = true
        private(set) var physics = QueueScrollPhysics()
        private weak var scroll: NSScrollView?
        private var monitor: Any?
        private var lastAnchor: CGFloat?
        private var scheduled = false
        private var settling: Task<Void, Never>?
        private var animation: Task<Void, Never>?
        private var animationTarget: CGFloat?
        private var suppressMomentum = false
        private var lastWheelTime: TimeInterval = 0

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func layout() {
            super.layout()
            reconcileLayout()
            // The enclosing document can finish sizing after its child marker.
            scheduleLayout()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            if window != nil { scheduleLayout() }
        }
        func scheduleLayout() {
            guard !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scheduled = false
                self.reconcileLayout()
            }
        }
        func reconcileLayout() {
            guard window != nil, let scroll = enclosingScrollView, let document = scroll.documentView else { return }
            if self.scroll !== scroll { self.scroll = scroll; lastAnchor = nil; needsReset = true }
            if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    guard let self else { return event }
                    return self.handle(event)
                }
            }
            let anchor = max(0, convert(bounds, to: document).minY)
            let old = lastAnchor
            lastAnchor = anchor
            if needsReset {
                physics = QueueScrollPhysics()
                suppressMomentum = false
                animation?.cancel()
                animationTarget = nil
                setOffset(anchor)
                needsReset = abs(scroll.contentView.bounds.minY - anchor) > 0.5
            } else if let old, abs(anchor - old) > 0.5, !physics.historyRevealed {
                // Growing history must not push a stationary Up Next viewport into history.
                animation?.cancel()
                animationTarget = nil
                physics.pull = 0
                setOffset(max(anchor, scroll.contentView.bounds.minY + anchor - old))
            }
        }
        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let scroll, event.window === window,
                  scroll.bounds.contains(scroll.convert(event.locationInWindow, from: nil)),
                  let anchor = lastAnchor else { return event }
            settling?.cancel()
            let ended = event.phase.contains(.ended) || event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended)
            let discrete = event.phase.isEmpty && event.momentumPhase.isEmpty
            if event.phase.contains(.began) || (discrete && event.timestamp - lastWheelTime > 0.16) {
                suppressMomentum = false
                if let animationTarget { setOffset(animationTarget) }
                animation?.cancel()
                animationTarget = nil
                physics.beginGesture()
            }
            lastWheelTime = event.timestamp
            if ended || discrete {
                settling = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
                    guard let self, !self.suppressMomentum, let scroll = self.scroll, let anchor = self.lastAnchor else { return }
                    if let target = self.physics.settle(offset: scroll.contentView.bounds.minY, anchor: anchor) { self.animate(to: target) }
                }
            }
            if suppressMomentum {
                if event.momentumPhase.contains(.ended) { suppressMomentum = false }
                return nil
            }
            let delta = -event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
            guard abs(delta) > 0 else { return event }
            if physics.historyRevealed, !event.momentumPhase.isEmpty { return nil }
            if !physics.historyRevealed, !event.momentumPhase.isEmpty,
               scroll.contentView.bounds.minY + delta < anchor {
                // Momentum from browsing Up Next is not a deliberate history reveal.
                if physics.pull == 0 { setOffset(anchor) }
                return nil
            }
            if physics.pull == 0, scroll.contentView.bounds.minY < anchor - QueueScrollPhysics.snapDistance {
                physics.historyRevealed = true
            }
            let wasRevealed = physics.historyRevealed
            if let target = physics.drag(delta: delta, offset: scroll.contentView.bounds.minY, anchor: anchor) {
                animation?.cancel()
                if wasRevealed != physics.historyRevealed {
                    suppressMomentum = true
                    animate(to: target)
                } else { setOffset(target) }
                return nil
            }
            animation?.cancel()
            return event
        }
        private func setOffset(_ value: CGFloat) {
            guard let scroll, let document = scroll.documentView else { return }
            let limit = max(0, document.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(limit, max(0, value))))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        private func animate(to target: CGFloat) {
            animation?.cancel()
            animationTarget = nil
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let start = scroll?.contentView.bounds.minY else {
                setOffset(target); return
            }
            animationTarget = target
            animation = Task { [weak self] in
                let began = Date()
                while !Task.isCancelled {
                    let progress = min(1, Date().timeIntervalSince(began) / 0.26)
                    let eased = 1 - pow(1 - progress, 3)
                    self?.setOffset(start + (target - start) * eased)
                    if progress >= 1 { self?.animationTarget = nil; return }
                    do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                }
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            settling?.cancel()
            animation?.cancel()
            animationTarget = nil
        }
    }
}
