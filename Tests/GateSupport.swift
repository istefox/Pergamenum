import Foundation

/// A one-shot latch on the main actor: `wait()` suspends until `open()` has been called, and
/// returns at once afterwards. Being `@MainActor` it needs no lock, and being explicit it makes
/// the order two tasks run in a fact the test states rather than a coincidence it observes.
///
/// Moved here from `Tests/VaultTransactionGestureTests.swift` (ADR-0051 §D2): shared rather than
/// copied a second time, now that `Tests/DiaryWriteDoorTests.swift` and
/// `Tests/DiaryWriteGuardTests.swift` need the same shape to force their own races
/// deterministically (ADR-0057 §D9). `MailStoreOverride.swift:41`'s `Gate` is a type nested
/// inside another type and is unaffected by this move.
@MainActor
final class Gate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        opened = true
        let resumed = waiters
        waiters.removeAll()
        resumed.forEach { $0.resume() }
    }

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
