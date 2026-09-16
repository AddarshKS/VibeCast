import Foundation
import Testing
@testable import VibeCast

struct QueueScrollTests {
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
