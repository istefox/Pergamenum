import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md - regression
// coverage for `SyncRunQueue` (`Sources/Features/Pratiche/PraticheController.swift`),
// the pure serialization rule extracted from `PraticaLiveSync.run(praticaPath:)` after
// a real bug: two concurrent `run(praticaPath:)` calls each assigned the coordinator's
// shared `running` reference and each `defer`-cleared it, so the earlier sync became
// uncancellable and could be clobbered by the later one's cleanup.
//
// Pure struct, no async, no I/O - the same testing philosophy as
// `Tests/PraticheControllerTests.swift`'s `PraticaWatcherTests`.

@Suite struct SyncRunQueueTests {
    @Test func requestOnAnIdleQueueRunsImmediatelyAndMarksItRunning() {
        var queue = SyncRunQueue()

        #expect(queue.request("A") == "A")
        #expect(queue.isRunning == true)
        #expect(queue.pending.isEmpty)
    }

    @Test func aSecondRequestWhileRunningIsQueuedNotStarted() {
        var queue = SyncRunQueue()
        _ = queue.request("A")

        #expect(queue.request("B") == nil, "a second path must not start while A is running")
        #expect(queue.isRunning == true)
        #expect(queue.pending == ["B"])
    }

    @Test func requestingTheSamePathTwiceWhileRunningQueuesItOnlyOnce() {
        var queue = SyncRunQueue()
        _ = queue.request("A")

        #expect(queue.request("B") == nil)
        #expect(queue.request("B") == nil, "the same path requested again must not be queued twice")
        #expect(queue.pending == ["B"], "B must appear exactly once")
    }

    @Test func finishedWithAnEmptyQueueClearsIsRunningAndReturnsNil() {
        var queue = SyncRunQueue()
        _ = queue.request("A")

        #expect(queue.finished() == nil)
        #expect(queue.isRunning == false)
    }

    @Test func finishedWithAQueuedPathDequeuesFIFOAndStaysRunning() {
        var queue = SyncRunQueue()
        _ = queue.request("A")
        _ = queue.request("B")
        _ = queue.request("C")

        #expect(queue.finished() == "B", "the first queued path must run next, FIFO")
        #expect(queue.isRunning == true, "the queue must not go idle while work remains")
        #expect(queue.pending == ["C"])
    }

    @Test func cancelPendingClearsTheQueueWithoutTouchingIsRunning() {
        var queue = SyncRunQueue()
        _ = queue.request("A")
        _ = queue.request("B")
        _ = queue.request("C")

        queue.cancelPending()
        #expect(queue.pending.isEmpty)
        #expect(queue.isRunning == true, "cancelPending must not end the active run itself")

        #expect(queue.finished() == nil, "with the queue cleared, finishing the active run goes idle")
        #expect(queue.isRunning == false)
    }

    /// The realistic sequence a burst of triggers produces: one path runs, two more
    /// arrive while it is busy, and each `finished()` call drains them FIFO until the
    /// queue is idle again.
    @Test func aRealisticSequenceOfOneRunnerAndTwoQueuedPathsDrainsInOrder() {
        var queue = SyncRunQueue()

        #expect(queue.request("A") == "A")
        #expect(queue.request("B") == nil)
        #expect(queue.request("C") == nil)
        #expect(queue.pending == ["B", "C"])

        #expect(queue.finished() == "B")
        #expect(queue.isRunning == true)

        #expect(queue.finished() == "C")
        #expect(queue.isRunning == true)

        #expect(queue.finished() == nil)
        #expect(queue.isRunning == false)
    }
}

// Regression coverage for `PraticaLiveSync.shouldRunQueuedRequest(kind:currentEligibility:)`
// (finding :976): a queued AUTOMATIC request must recheck the pratica's CURRENT
// eligibility at dequeue time, since "closed while another sync ran" is exactly the
// window in which a request can sit in `queue.pending` from before the close. Pure
// static function, same testing philosophy as `SyncRunQueueTests` above - no async, no
// real `PraticheController`, no Mail store.
@Suite struct ShouldRunQueuedRequestTests {
    @Test func manualRefreshAlwaysRunsRegardlessOfEligibility() {
        #expect(PraticaLiveSync.shouldRunQueuedRequest(kind: .manualRefresh, currentEligibility: .manualOnly))
        #expect(PraticaLiveSync.shouldRunQueuedRequest(kind: .manualRefresh, currentEligibility: .automatic))
        #expect(PraticaLiveSync.shouldRunQueuedRequest(kind: .manualRefresh, currentEligibility: nil))
    }

    @Test func automaticTriggerRunsWhenStillEligibleAtDequeueTime() {
        #expect(PraticaLiveSync.shouldRunQueuedRequest(kind: .fsEvents, currentEligibility: .automatic))
        #expect(PraticaLiveSync.shouldRunQueuedRequest(kind: .windowKey, currentEligibility: .automatic))
        #expect(PraticaLiveSync.shouldRunQueuedRequest(kind: .vaultOpen, currentEligibility: .automatic))
    }

    @Test func automaticTriggerIsRevokedWhenThePraticaClosedWhileQueued() {
        #expect(
            !PraticaLiveSync.shouldRunQueuedRequest(kind: .fsEvents, currentEligibility: .manualOnly),
            "the pratica was closed between the queue and the dequeue - the queued automatic sync must not run"
        )
        #expect(!PraticaLiveSync.shouldRunQueuedRequest(kind: .windowKey, currentEligibility: .manualOnly))
        #expect(!PraticaLiveSync.shouldRunQueuedRequest(kind: .vaultOpen, currentEligibility: .manualOnly))
    }

    @Test func aPraticaNoLongerFoundRunsRatherThanSilentlyDropping() {
        #expect(
            PraticaLiveSync.shouldRunQueuedRequest(kind: .fsEvents, currentEligibility: nil),
            "a missing lookup (deleted pratica, vault moved on) must not be read as ineligible"
        )
    }
}

// Regression coverage for `PraticaLiveSync.coalescedKind(existing:incoming:)` (finding
// :1001): a queued `.manualRefresh` must survive a later automatic trigger coalescing
// onto the same still-pending path, or `shouldRunQueuedRequest` would wrongly treat the
// original explicit «Aggiorna ora» as revocable once the pratica closes before dequeue.
@Suite struct CoalescedKindTests {
    @Test func nothingQueuedYetTheIncomingKindAlwaysWins() {
        #expect(PraticaLiveSync.coalescedKind(existing: nil, incoming: .fsEvents) == .fsEvents)
        #expect(PraticaLiveSync.coalescedKind(existing: nil, incoming: .manualRefresh) == .manualRefresh)
    }

    @Test func aQueuedManualRefreshSurvivesALaterAutomaticTrigger() {
        #expect(
            PraticaLiveSync.coalescedKind(existing: .manualRefresh, incoming: .fsEvents) == .manualRefresh,
            "an explicit «Aggiorna ora» must not be silently downgraded to an automatic trigger's kind"
        )
        #expect(PraticaLiveSync.coalescedKind(existing: .manualRefresh, incoming: .windowKey) == .manualRefresh)
        #expect(PraticaLiveSync.coalescedKind(existing: .manualRefresh, incoming: .vaultOpen) == .manualRefresh)
    }

    @Test func twoAutomaticTriggersCoalesceToTheLatestOne() {
        #expect(
            PraticaLiveSync.coalescedKind(existing: .fsEvents, incoming: .windowKey) == .windowKey,
            "with nothing explicit queued, the later automatic trigger's kind is the one that matters"
        )
    }

    @Test func aSecondManualRefreshStaysManualRefresh() {
        #expect(PraticaLiveSync.coalescedKind(existing: .manualRefresh, incoming: .manualRefresh) == .manualRefresh)
    }
}
