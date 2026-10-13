import Foundation
import Testing
@testable import Pergamenum

// ADR-0083 §D7, fix round 1: the dwell restarts from the last moment the conditions became true.
// While a preview is up, a pointer that reaches another run hides it and arms the dwell for the
// new run in the same step; hiding alone would leave a pointer that rests there with nothing to
// show it, because no further event is guaranteed to arrive.

@Suite struct LinkPreviewTriggerRearmTests {
    private let runA = NSRange(location: 7, length: 4)
    private let runB = NSRange(location: 30, length: 6)

    private func showing() -> LinkPreviewTrigger {
        var trigger = LinkPreviewTrigger()
        _ = trigger.handle(.pointer(run: runA, commandDown: true, at: 0))
        _ = trigger.handle(.tick(LinkPreviewTrigger.dwell))
        return trigger
    }

    @Test func aPointerReachingAnotherRunWhileShownHidesAndSchedulesTheNewDwell() {
        var trigger = showing()
        let effect = trigger.handle(.pointer(run: runB, commandDown: true, at: 1))
        #expect(effect == .hideAndSchedule(after: LinkPreviewTrigger.dwell))
        #expect(trigger.shownRun == nil)
    }

    @Test func thePointerThatRestsOnTheSecondRunGetsItsPreviewAfterTheDwell() {
        var trigger = showing()
        _ = trigger.handle(.pointer(run: runB, commandDown: true, at: 1))
        // No further pointer event: the tick alone has to show it.
        #expect(trigger.handle(.tick(1 + 0.1)) == .none)
        #expect(trigger.handle(.tick(1 + LinkPreviewTrigger.dwell)) == .show(run: runB))
        #expect(trigger.shownRun == runB)
    }

    @Test func thePointerLeavingTheShownRunForNoRunJustHides() {
        var trigger = showing()
        #expect(trigger.handle(.pointer(run: nil, commandDown: true, at: 1)) == .hide)
        #expect(trigger.handle(.tick(2)) == .none)
    }

    @Test func movingWithinTheShownRunChangesNothing() {
        var trigger = showing()
        #expect(trigger.handle(.pointer(run: runA, commandDown: true, at: 1)) == .none)
        #expect(trigger.shownRun == runA)
    }
}
