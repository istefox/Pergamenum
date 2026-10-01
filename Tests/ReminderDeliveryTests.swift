import Foundation
import Testing
import UserNotifications
@testable import Pergamenum

// PG-243's hand checks moved below the banner, `docs/plans/pg-243-tap-automated-checks.md`,
// Task 2 (R-01) and Task 3 (R-02).
//
// Every scheduler here is built with `becomesDelegate: false`: one built with the default
// would point the host process's real notification delegate at a throwaway object (the
// hazard `Tests/ReminderTapTests.swift`'s header records). D5 pins that the seam holds.

/// What the scheduler's route sink was handed.
@MainActor
private final class RouteRecorder {
    var routes: [PergamenumRoute] = []
}

@MainActor
private func scheduler(recordingInto recorder: RouteRecorder) -> ReminderScheduler {
    let scheduler = ReminderScheduler(becomesDelegate: false)
    scheduler.openRoute = { route in recorder.routes.append(route) }
    return scheduler
}

@MainActor
@Suite struct ReminderDeliveryTests {

    // MARK: D1 - an opened id route reaches the sink exactly once

    @Test func anOpenedIDRouteReachesTheSinkOnce() async {
        let recorder = RouteRecorder()
        let scheduler = scheduler(recordingInto: recorder)

        await scheduler.deliver(.open(.noteID("3f2c1b4a-0000-4000-8000-000000000000")))

        #expect(recorder.routes == [.noteID("3f2c1b4a-0000-4000-8000-000000000000")])
    }

    // MARK: D2 - a board route is passed through unchanged

    @Test func anOpenedBoardRouteIsPassedThroughUnchanged() async {
        let recorder = RouteRecorder()
        let scheduler = scheduler(recordingInto: recorder)

        await scheduler.deliver(.open(.canvas(path: "Area/Area.canvas", nodeID: "7a1f")))

        #expect(recorder.routes == [.canvas(path: "Area/Area.canvas", nodeID: "7a1f")])
    }

    // MARK: D3 - nothing but `.open` reaches the sink

    @Test(arguments: [ReminderTap.noRoute, .unreadableRoute, .notDefaultAction])
    func aTapThatIsNotAnOpenNeverReachesTheSink(_ tap: ReminderTap) async {
        let recorder = RouteRecorder()
        let scheduler = scheduler(recordingInto: recorder)

        await scheduler.deliver(tap)

        #expect(recorder.routes.isEmpty)
    }

    // MARK: D4 - no sink is a no-op, not a trap

    @Test func anOpenedRouteWithNoSinkReturns() async {
        let scheduler = ReminderScheduler(becomesDelegate: false)
        #expect(scheduler.openRoute == nil)

        await scheduler.deliver(.open(.note(path: "b.md")))
    }

    // MARK: D5 - the seam leaves the process's delegate where it was

    @Test func aSchedulerBuiltForTheSuiteLeavesTheProcessDelegateUntouched() {
        let center = UNUserNotificationCenter.current()
        let before = center.delegate

        let scheduler = ReminderScheduler(becomesDelegate: false)

        #expect(center.delegate === before)
        #expect(center.delegate !== scheduler)
    }

    // MARK: H1 - the test host's delegate is the app's own scheduler (R-02)

    @Test func theHostProcessDelegateIsAReminderScheduler() {
        #expect(UNUserNotificationCenter.current().delegate is ReminderScheduler)
    }
}
