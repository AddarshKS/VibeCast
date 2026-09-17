import AppKit
import Testing
@testable import VibeCast

struct QueueScrollTests {
    @Test func shortWindowsContinueIntoResistanceWithoutASecondGesture() {
        var physics = QueueScrollPhysics(historyRevealed: true)
        #expect(physics.drag(delta: 40, offset: 0, anchor: 300, historyBottom: 150) == nil)
        #expect(physics.settle(offset: 40, anchor: 300, historyBottom: 150) == nil)
        #expect(physics.drag(delta: 150, offset: 40, anchor: 300, historyBottom: 150) == 162)
        #expect(!physics.waitingForNewGesture)
        #expect(physics.drag(delta: 50, offset: 162, anchor: 300, historyBottom: 150) == 300)
        #expect(!physics.historyRevealed)
    }

    @Test(arguments: [0.0, 0.5, 20, 150]) func historyReturnKeepsTheOriginalPullThreshold(overflow: Double) {
        let overflow = CGFloat(overflow)
        var physics = QueueScrollPhysics(historyRevealed: true)
        #expect(physics.drag(delta: overflow + 40, offset: 0, anchor: 300, historyBottom: overflow) == overflow + 12)
        #expect(physics.settle(offset: overflow + 12, anchor: 300, historyBottom: overflow) == overflow)
        #expect(physics.historyRevealed)
        #expect(physics.drag(delta: 100, offset: overflow, anchor: 300, historyBottom: overflow) == 300)
        #expect(!physics.historyRevealed)
    }

    @MainActor
    @Test func growingReadingWindowKeepsHistoryWithinItsSection() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 150),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        let document = FlippedQueueDocument(frame: NSRect(x: 0, y: 0, width: 340, height: 900))
        let marker = QueueScrollBehavior.Marker(frame: NSRect(x: 0, y: 300, width: 300, height: 28))
        window.contentView = scroll
        scroll.documentView = document
        document.addSubview(marker)
        defer { marker.stop(); window.contentView = nil }
        marker.reconcileLayout()
        #expect(marker.applySectionDrag(delta: -100))
        try await waitForQueueOffset(scroll, target: 0)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 120))
        window.setContentSize(NSSize(width: 340, height: 250))
        scroll.layoutSubtreeIfNeeded()
        marker.reconcileLayout()
        try await Task.sleep(for: .milliseconds(30))
        #expect(marker.physics.historyRevealed)
        #expect(abs(scroll.contentView.bounds.minY - 50) < 1)
        window.setContentSize(NSSize(width: 340, height: 400))
        scroll.layoutSubtreeIfNeeded()
        marker.reconcileLayout()
        try await Task.sleep(for: .milliseconds(30))
        #expect(abs(scroll.contentView.bounds.minY) < 1)
        #expect(marker.physics.historyRevealed)
    }

    @MainActor
    @Test(arguments: 1...5)
    func historyGrowthWaitsForDocumentToReachItsNewSize(count: Int) async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        let document = FlippedQueueDocument(frame: scroll.bounds)
        let marker = QueueScrollBehavior.Marker(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
        window.contentView = scroll
        scroll.documentView = document
        document.addSubview(marker)
        defer { marker.stop(); window.contentView = nil }
        marker.reconcileLayout()
        // SwiftUI can move the header before the scroll document grows. The first
        // scroll request is clamped; subsequent layout must still finish that move.
        for row in 1...count {
            let anchor = CGFloat(36 + row * 47)
            marker.setFrameOrigin(NSPoint(x: 0, y: anchor))
            marker.reconcileLayout()
            document.setFrameSize(NSSize(width: 340, height: 300 + anchor))
            try await Task.sleep(for: .milliseconds(25))
            #expect(abs(scroll.contentView.bounds.minY - anchor) < 0.5,
                    "Growing history to \(row) rows must finish positioning Up Next after document growth.")
            #expect(!marker.physics.historyRevealed)
        }
    }

    @MainActor
    @Test(arguments: 1...5)
    func growthPreservesBrowsingAndRetargetsBothSnapDirections(count: Int) async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        var anchor = CGFloat(36 + count * 47)
        let document = FlippedQueueDocument(frame: NSRect(x: 0, y: 0, width: 340, height: anchor + 800))
        let marker = QueueScrollBehavior.Marker(frame: NSRect(x: 0, y: anchor, width: 300, height: 28))
        window.contentView = scroll
        scroll.documentView = document
        document.addSubview(marker)
        defer { marker.stop(); window.contentView = nil }
        marker.reconcileLayout()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: anchor + 120))
        let growth: CGFloat = count < 5 ? 47 : 0
        anchor += growth
        marker.setFrameOrigin(NSPoint(x: 0, y: anchor))
        document.setFrameSize(NSSize(width: 340, height: anchor + 800))
        try await Task.sleep(for: .milliseconds(25))
        #expect(abs(scroll.contentView.bounds.minY - anchor - 120) < 0.5)

        scroll.contentView.scroll(to: NSPoint(x: 0, y: anchor))
        #expect(marker.applySectionDrag(delta: -100))
        try await waitForQueueOffset(scroll, target: 0)
        #expect(marker.physics.historyRevealed)
        #expect(abs(scroll.contentView.bounds.minY) < 0.5)
        // A song finishing while history is intentionally open must not close it.
        anchor += count < 4 ? 47 : 0
        marker.setFrameOrigin(NSPoint(x: 0, y: anchor))
        document.setFrameSize(NSSize(width: 340, height: anchor + 800))
        try await Task.sleep(for: .milliseconds(25))
        #expect(marker.physics.historyRevealed)
        #expect(abs(scroll.contentView.bounds.minY) < 0.5)
        #expect(marker.applySectionDrag(delta: 40))
        #expect(abs(scroll.contentView.bounds.minY - 12) < 0.5)
        #expect(marker.applySectionDrag(delta: 60))
        try await waitForQueueOffset(scroll, target: anchor)
        #expect(!marker.physics.historyRevealed)
        #expect(abs(scroll.contentView.bounds.minY - anchor) < 0.5)

        // A refresh during a snap cancels that snap instead of reopening history later.
        #expect(marker.applySectionDrag(delta: -100))
        try await Task.sleep(for: .milliseconds(30))
        marker.needsReset = true
        marker.reconcileLayout()
        try await Task.sleep(for: .milliseconds(300))
        #expect(!marker.physics.historyRevealed)
        #expect(abs(scroll.contentView.bounds.minY - anchor) < 0.5)
    }

    @Test func ordinaryScrollingIsNotInterceptedOrSnappedBack() {
        var physics = QueueScrollPhysics()
        #expect(physics.drag(delta: 40, offset: 300, anchor: 280) == nil)
        #expect(physics.drag(delta: -20, offset: 400, anchor: 280) == nil)
        #expect(physics.settle(offset: 400, anchor: 280) == nil)
    }
    @Test func deliberatePullRevealsHistoryButSmallPullReturnsToUpcoming() {
        var physics = QueueScrollPhysics()
        #expect(physics.drag(delta: -50, offset: 300, anchor: 300) == 285)
        #expect(!physics.historyRevealed)
        #expect(physics.settle(offset: 285, anchor: 300) == 300)
        #expect(physics.pull == 0)
        #expect(physics.drag(delta: -100, offset: 300, anchor: 300) == 0)
        #expect(physics.historyRevealed)
        #expect(physics.drag(delta: 30, offset: 0, anchor: 300) == 9)
        #expect(physics.settle(offset: 9, anchor: 300) == 0)
        #expect(physics.historyRevealed)
        #expect(physics.drag(delta: 100, offset: 0, anchor: 300) == 300)
        #expect(!physics.historyRevealed)
    }
    @Test func emptyHistoryDoesNotAddAnArtificialBarrier() {
        var physics = QueueScrollPhysics()
        #expect(physics.drag(delta: -100, offset: 0, anchor: 0) == nil)
    }
    @Test func fastScrollStopsAtUpcomingAndRequiresANewGesture() {
        var physics = QueueScrollPhysics()
        #expect(physics.drag(delta: -600, offset: 530, anchor: 300) == 300)
        #expect(physics.waitingForNewGesture)
        #expect(physics.drag(delta: -200, offset: 300, anchor: 300) == 300)
        #expect(!physics.historyRevealed)
        #expect(physics.drag(delta: 40, offset: 300, anchor: 300) == nil)
        #expect(physics.drag(delta: -10, offset: 340, anchor: 300) == nil)
        physics.beginGesture()
        #expect(physics.drag(delta: -100, offset: 300, anchor: 300) == 0)
        #expect(physics.historyRevealed)
    }
    @Test func pullCanReverseWithoutSwitchingSections() {
        var physics = QueueScrollPhysics()
        #expect(physics.drag(delta: -50, offset: 300, anchor: 300) == 285)
        #expect(physics.drag(delta: 60, offset: 285, anchor: 300) == 300)
        #expect(physics.pull == 0)
        physics.historyRevealed = true
        #expect(physics.drag(delta: 50, offset: 0, anchor: 300) == 15)
        #expect(physics.drag(delta: -60, offset: 15, anchor: 300) == 0)
        #expect(physics.historyRevealed)
        #expect(physics.pull == 0)
    }
    @Test func bothDirectionsHaveMatchingResistanceAndThreshold() {
        var upcoming = QueueScrollPhysics()
        var history = QueueScrollPhysics(historyRevealed: true)
        for _ in 0..<8 {
            let up = upcoming.drag(delta: -10, offset: 300 - upcoming.pull * 0.3, anchor: 300)
            let down = history.drag(delta: 10, offset: history.pull * 0.3, anchor: 300)
            #expect(up == 300 - (down ?? 0))
        }
        #expect(upcoming.drag(delta: -10, offset: 276, anchor: 300) == 0)
        #expect(history.drag(delta: 10, offset: 24, anchor: 300) == 300)
    }
}

private final class FlippedQueueDocument: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
func waitForQueueOffset(_ scroll: NSScrollView, target: CGFloat) async throws {
    for _ in 0..<80 {
        if abs(scroll.contentView.bounds.minY - target) < 0.1 {
            try await Task.sleep(for: .milliseconds(50))
            return
        }
        try await Task.sleep(for: .milliseconds(16))
    }
}
