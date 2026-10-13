import Foundation
@testable import Pergamenum

// ADR-0095 §D4 (planned), plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 2 (PG-406).
//
// The pause a test fires by hand: no timer, so no test waits on the clock (ADR-0043 §D9).

/// Records the last action given to `restart(_:)`, counts the restarts, and runs the pending
/// action once on `fire()`.
@MainActor
final class ManualPauseScheduler: PauseScheduler {
    /// How many times `restart(_:)` was called, `cancel()` not counted.
    private(set) var restarts = 0
    private var pending: (@MainActor () -> Void)?

    /// Whether an action is waiting to be fired.
    var isPending: Bool { pending != nil }

    func restart(_ action: @escaping @MainActor () -> Void) {
        restarts += 1
        pending = action
    }

    func cancel() {
        pending = nil
    }

    /// Runs the pending action, if any, once; a second `fire()` with no restart in between does nothing.
    func fire() {
        guard let action = pending else { return }
        pending = nil
        action()
    }
}
