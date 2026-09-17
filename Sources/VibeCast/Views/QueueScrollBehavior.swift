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

    mutating func drag(delta: CGFloat, offset: CGFloat, anchor: CGFloat, historyBottom: CGFloat = 0) -> CGFloat? {
        guard anchor > 1 else { return nil }
        if historyRevealed {
            // Browse overflowing history first, then spend the remaining movement
            // on resistance in this same gesture. Do not require a second pull.
            var resistedDelta = delta
            if pull == 0, offset < historyBottom {
                guard delta > 0, offset + delta >= historyBottom else { return nil }
                resistedDelta = offset + delta - historyBottom
            }
            guard pull > 0 || delta > 0 else { return nil }
            pull = max(0, pull + resistedDelta)
            if pull >= Self.revealDistance {
                historyRevealed = false
                pull = 0
                return anchor
            }
            return historyBottom + pull * Self.resistance
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

    mutating func settle(offset: CGFloat, anchor: CGFloat, historyBottom: CGFloat = 0) -> CGFloat? {
        if historyRevealed {
            guard pull > 0 || historyBottom == 0 else { return nil }
            pull = 0
            return historyBottom
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
    var historyTrailingSpace: CGFloat = 0

    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) {
        view.historyTrailingSpace = historyTrailingSpace
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
        var historyTrailingSpace: CGFloat = 0
        private(set) var physics = QueueScrollPhysics()
        private weak var scroll: NSScrollView?
        private var monitor: Any?
        private var layoutObservers: [NSObjectProtocol] = []
        private var lastAnchor: CGFloat?
        private var pendingOffset: CGFloat?
        private var reconciling = false
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
            guard !reconciling, window != nil,
                  let scroll = enclosingScrollView, let document = scroll.documentView else { return }
            reconciling = true
            defer { reconciling = false }
            if self.scroll !== scroll {
                stop()
                self.scroll = scroll
                lastAnchor = nil
                pendingOffset = nil
                needsReset = true
            }
            if layoutObservers.isEmpty { observeLayout(scroll: scroll, document: document) }
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
                settling?.cancel()
                animation?.cancel()
                animationTarget = nil
                pendingOffset = anchor
                applyPendingOffset()
                needsReset = abs(scroll.contentView.bounds.minY - anchor) > 0.5
            } else if let old, abs(anchor - old) > 0.5 {
                // Keep the requested position, not a temporarily clamped clip offset.
                // The marker can move before SwiftUI grows its enclosing document.
                let previous = pendingOffset ?? animationTarget ?? scroll.contentView.bounds.minY
                animation?.cancel()
                animationTarget = nil
                settling?.cancel()
                physics.pull = 0
                pendingOffset = physics.historyRevealed ? min(previous, historyBottom) : max(anchor, previous + anchor - old)
                applyPendingOffset()
            } else if physics.historyRevealed, physics.pull == 0, animationTarget == nil,
                      scroll.contentView.bounds.minY > historyBottom {
                pendingOffset = historyBottom
                applyPendingOffset()
            } else {
                applyPendingOffset()
            }
        }
        private func observeLayout(scroll: NSScrollView, document: NSView) {
            // SwiftUI often moves a representable's wrapper while leaving the
            // marker's own frame unchanged. Observe the whole conversion path.
            var views: [NSView] = [scroll.contentView]
            var ancestor: NSView? = self
            while let view = ancestor {
                views.append(view)
                if view === document { break }
                ancestor = view.superview
            }
            for view in views {
                view.postsFrameChangedNotifications = true
                layoutObservers.append(NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: view, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.reconcileLayout()
                        self?.scheduleLayout()
                    }
                })
            }
        }
        private func applyPendingOffset() {
            guard let pendingOffset, let scroll else { return }
            setOffset(pendingOffset)
            if abs(scroll.contentView.bounds.minY - pendingOffset) < 0.5 { self.pendingOffset = nil }
        }
        private func handle(_ event: NSEvent) -> NSEvent? {
            reconcileLayout()
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
                    if let target = self.physics.settle(offset: scroll.contentView.bounds.minY, anchor: anchor,
                                                       historyBottom: self.historyBottom) { self.animate(to: target) }
                }
            }
            if suppressMomentum {
                if event.momentumPhase.contains(.ended) { suppressMomentum = false }
                return nil
            }
            let delta = -event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
            guard abs(delta) > 0 else { return event }
            if physics.historyRevealed, !event.momentumPhase.isEmpty {
                if scroll.contentView.bounds.minY + delta > historyBottom {
                    setOffset(historyBottom)
                    return nil
                }
                return historyBottom > 0 ? event : nil
            }
            if !physics.historyRevealed, !event.momentumPhase.isEmpty,
               scroll.contentView.bounds.minY + delta < anchor {
                // Momentum from browsing Up Next is not a deliberate history reveal.
                if physics.pull == 0 { setOffset(anchor) }
                return nil
            }
            if applySectionDrag(delta: delta) { return nil }
            animation?.cancel()
            animationTarget = nil
            return event
        }
        // Resolve section gestures against the current measured header, not a row count.
        func applySectionDrag(delta: CGFloat) -> Bool {
            guard let scroll, let anchor = lastAnchor, pendingOffset == nil else { return false }
            let wasRevealed = physics.historyRevealed
            if let target = physics.drag(delta: delta, offset: scroll.contentView.bounds.minY, anchor: anchor,
                                         historyBottom: historyBottom) {
                animation?.cancel()
                animationTarget = nil
                if wasRevealed != physics.historyRevealed {
                    suppressMomentum = true
                    animate(to: target)
                } else { setOffset(target) }
                return true
            }
            return false
        }
        var historyBottom: CGFloat {
            // The divider and gap before Next Up are not history rows. Counting
            // them as overflow introduced an unnecessary scroll step in mini mode.
            max(0, (lastAnchor ?? 0) - historyTrailingSpace - (scroll?.contentView.bounds.height ?? 0))
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
            layoutObservers.forEach(NotificationCenter.default.removeObserver)
            layoutObservers.removeAll()
            settling?.cancel()
            animation?.cancel()
            animationTarget = nil
        }
    }
}
