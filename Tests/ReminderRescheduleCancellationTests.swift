import Foundation
import Testing
import UserNotifications
@testable import Pergamenum

// PG-353: `reschedule`'s cancellation guards (#789) had no test, because the scheduler owned
// `UNUserNotificationCenter` directly and a test host never reports `access` granted, so every
// run returned at the first guard. A recording `ReminderRequestQueue` and a granted `access`
// reach the loop.

/// Records every call, and can cancel the task that is adding after a given number of adds.
@MainActor
private final class RecordingQueue: ReminderRequestQueue {
    var added: [String] = []
    var removed: [[String]] = []
    var cancelAfter: Int?

    nonisolated func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        MainActor.assumeIsolated { removed.append(identifiers) }
    }

    nonisolated func add(_ request: UNNotificationRequest) async throws {
        let identifier = request.identifier
        await MainActor.run {
            added.append(identifier)
            if let cancelAfter, added.count == cancelAfter {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
    }

    nonisolated func pendingNotificationRequests() async -> [UNNotificationRequest] { [] }
}

private let now = EventKitStore.date(CalendarDate(iso: "2026-10-01")!, hour: 8, minute: 0)!

private func tasks(_ count: Int) -> [TaskItem] {
    (0..<count).compactMap {
        TaskParser.parse(line: "- [ ] Compito \($0) @remind(2026-10-02 09:00)", sourcePath: "N.md", lineIndex: $0)
    }
}

@MainActor
@Suite struct ReminderRescheduleCancellationTests {
    @Test func aGrantedRunAddsEveryRequestAndRecordsItsIdentifiers() async throws {
        let queue = RecordingQueue()
        let scheduler = ReminderScheduler(becomesDelegate: false, queue: queue, access: .granted)
        let items = tasks(3)
        try #require(items.count == 3)

        await scheduler.reschedule(for: items, session: nil, now: now)

        #expect(queue.added == items.map(\.id))
        #expect(scheduler.scheduledIDs == Set(items.map(\.id)))
    }

    @Test func aRunCancelledBeforeItStartsTouchesNothing() async throws {
        let queue = RecordingQueue()
        let scheduler = ReminderScheduler(becomesDelegate: false, queue: queue, access: .granted)
        await scheduler.reschedule(for: tasks(2), session: nil, now: now)
        let before = scheduler.scheduledIDs
        queue.removed = []

        let run = Task { await scheduler.reschedule(for: tasks(3), session: nil, now: now) }
        run.cancel()
        await run.value

        #expect(queue.removed.isEmpty, "a cancelled run must not remove the newer run's requests")
        #expect(scheduler.scheduledIDs == before)
    }

    @Test func aRunCancelledHalfwayStopsBeforeItsNextAddAndNamesOnlyWhatItAdded() async throws {
        let queue = RecordingQueue()
        queue.cancelAfter = 1
        let scheduler = ReminderScheduler(becomesDelegate: false, queue: queue, access: .granted)
        let items = tasks(3)
        try #require(items.count == 3)

        await Task { await scheduler.reschedule(for: items, session: nil, now: now) }.value

        #expect(queue.added == [items[0].id])
        #expect(scheduler.scheduledIDs == [items[0].id])

        // The next run removes exactly what the stopped one added.
        queue.cancelAfter = nil
        await scheduler.reschedule(for: [], session: nil, now: now)
        #expect(queue.removed.last == [items[0].id])
        #expect(scheduler.scheduledIDs.isEmpty)
    }

    @Test func aRunWithoutAccessTouchesNothing() async {
        let queue = RecordingQueue()
        let scheduler = ReminderScheduler(becomesDelegate: false, queue: queue)

        await scheduler.reschedule(for: tasks(2), session: nil, now: now)

        #expect(queue.added.isEmpty)
        #expect(queue.removed.isEmpty)
    }
}
