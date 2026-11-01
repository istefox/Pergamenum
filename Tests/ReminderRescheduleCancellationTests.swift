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
    /// Identifiers the centre reports pending, as a previous launch would have left them.
    var pending: [String] = []
    /// Cancels the task reading the pending requests, as a newer run would while it waits.
    var cancelOnPendingRead = false
    /// Parks the next pending read, once, until `releasePendingRead()`, as a slow centre would.
    var parksNextPendingRead = false
    private var parkedRead: CheckedContinuation<Void, Never>?
    var hasParkedRead: Bool { parkedRead != nil }

    func releasePendingRead() {
        parkedRead?.resume()
        parkedRead = nil
    }

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

    nonisolated func pendingNotificationRequests() async -> [UNNotificationRequest] {
        let parks = await MainActor.run {
            defer { parksNextPendingRead = false }
            return parksNextPendingRead
        }
        if parks {
            await withCheckedContinuation { continuation in
                Task { @MainActor in self.parkedRead = continuation }
            }
        }
        let identifiers = await MainActor.run {
            if cancelOnPendingRead { withUnsafeCurrentTask { $0?.cancel() } }
            return pending
        }
        return identifiers.map {
            UNNotificationRequest(identifier: $0, content: UNMutableNotificationContent(), trigger: nil)
        }
    }
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

    @Test func theFirstRunAfterARelaunchRemovesWhatThePreviousLaunchScheduled() async { // PG-443
        // A fresh scheduler knows no identifiers; the centre still holds the previous launch's
        // reminder for a task deleted since, and a test notification that is not a reminder.
        let queue = RecordingQueue()
        let testID = "\(ReminderScheduler.testIdentifierPrefix)prova"
        queue.pending = ["stale-task", testID]
        let scheduler = ReminderScheduler(becomesDelegate: false, queue: queue, access: .granted)

        await scheduler.reschedule(for: [], session: nil, now: now)

        #expect(queue.removed.last == ["stale-task"])
        #expect(queue.removed.allSatisfy { !$0.contains(testID) })
    }

    @Test func aRunCancelledWhileReadingThePendingRequestsTouchesNothing() async throws { // PG-443
        let queue = RecordingQueue()
        let scheduler = ReminderScheduler(becomesDelegate: false, queue: queue, access: .granted)
        let items = tasks(2)
        try #require(items.count == 2)
        await scheduler.reschedule(for: items, session: nil, now: now)
        let before = scheduler.scheduledIDs
        try #require(!before.isEmpty)
        queue.added = []
        queue.removed = []
        queue.cancelOnPendingRead = true

        await Task { await scheduler.reschedule(for: tasks(3), session: nil, now: now) }.value

        #expect(queue.removed.isEmpty, "a run cancelled during the read must not remove the newer run's requests")
        #expect(queue.added.isEmpty)
        #expect(scheduler.scheduledIDs == before)
    }

    @Test func aRunSupersededWhileReadingThePendingRequestsTouchesNothing() async throws {
        // The Settings button's run is not cancellable, so an older run is told apart from the
        // newest by more than `Task.isCancelled`: it resumes after a newer run has finished and
        // must neither remove that run's requests nor re-add its own stale set.
        let queue = RecordingQueue()
        let scheduler = ReminderScheduler(becomesDelegate: false, queue: queue, access: .granted)
        let newer = tasks(3)
        try #require(newer.count == 3)
        queue.parksNextPendingRead = true

        let older = Task { await scheduler.reschedule(for: tasks(2), session: nil, now: now) }
        while !queue.hasParkedRead { await Task.yield() }
        await scheduler.reschedule(for: newer, session: nil, now: now)
        let added = queue.added
        let removed = queue.removed
        try #require(scheduler.scheduledIDs == Set(newer.map(\.id)))

        queue.releasePendingRead()
        await older.value

        #expect(queue.removed == removed, "a superseded run must not remove the newer run's requests")
        #expect(queue.added == added, "a superseded run must not re-add its own stale set")
        #expect(scheduler.scheduledIDs == Set(newer.map(\.id)))
    }

    @Test func aRunWithoutAccessTouchesNothing() async {
        let queue = RecordingQueue()
        let scheduler = ReminderScheduler(becomesDelegate: false, queue: queue)

        await scheduler.reschedule(for: tasks(2), session: nil, now: now)

        #expect(queue.added.isEmpty)
        #expect(queue.removed.isEmpty)
    }
}
