import Foundation
@testable import Pergamenum

// PG-208. `MailStoreLocation.resolve()` (`Sources/Core/Email/MailStoreLocation.swift`) reads a
// single process-global key, `UserDefaults.standard.string(forKey: "mailStoreRoot")`. Six test
// files set and `defer`-remove that same key around a sync. Each of their suites is
// `@Suite(.serialized)`, which only serializes tests inside one suite - Swift Testing still runs
// different suites in parallel, so one suite's write can land inside another's read/write window.
// `PraticaConversationRenumberingTests.syncRenumbersAFollowedConversationWhoseIdMailHasChanged`
// sleeps 50ms between two syncs specifically to let a fixture's mtime move, which is exactly the
// window a concurrent suite's `set`/`removeObject` can land in - the observed failure (the second
// sync resolving against the wrong or absent fixture) is that clobber, not a deterministic
// regression.
//
// This is `MailStoreLocation.overrideKey`'s only door: every test that needs the override goes
// through `acquire`/`acquireWithoutOverride`, never `UserDefaults.standard.set` directly, so a new
// call site inherits the exclusion instead of needing to remember it (ADR-0041's shape, applied to
// a global rather than a file). The gate design mirrors `ReleasePipelineTests.ProcessOutcomeBox`:
// `NSLock`-guarded state in a class, `CheckedContinuation` waiters, resumed only after unlocking.
//
// PG-249. The gate serializes one process only, and the persistent domain is shared by every
// process with the host's bundle id: two test runs at once (two worktrees, or a Stop-hook run
// beside a manual one) clobbered each other's value mid-sync. The override therefore lives in the
// argument domain, where a `-mailStoreRoot` launch argument would put it: volatile, local to this
// process, and searched before the persistent domain, so no other process can see or replace it.
// PG-250 closed the other half: `resolve()` now reads the argument domain alone, so a value
// another process leaves in the persistent domain no longer reaches an `acquireWithoutOverride`
// test either.
enum MailStoreOverride {
    /// Waits for exclusive use of the `mailStoreRoot` override, then points it at `root`. Pair
    /// with `defer { MailStoreOverride.release() }` registered immediately after this returns.
    static func acquire(settingRootTo root: URL) async {
        await gate.acquire()
        setArgument(root.path(percentEncoded: false))
    }

    /// Waits for exclusive use of the override without setting it, for a test asserting what
    /// `resolve()` answers with none set - a concurrent suite's override must not leak into it.
    static func acquireWithoutOverride() async {
        await gate.acquire()
    }

    /// Synchronous, so it is callable from a plain `defer`: removes the override, then lets the
    /// next waiter, if any, proceed.
    static func release() {
        setArgument(nil)
        gate.release()
    }

    /// Read-modify-write of the argument domain, keeping every other launch argument in it.
    private static func setArgument(_ path: String?) {
        let defaults = UserDefaults.standard
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments[MailStoreLocation.overrideKey] = path
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }

    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var isHeld = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func acquire() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if isHeld {
                    waiters.append(continuation)
                    lock.unlock()
                    return
                }
                isHeld = true
                lock.unlock()
                continuation.resume()
            }
        }

        func release() {
            lock.lock()
            let next = waiters.isEmpty ? nil : waiters.removeFirst()
            isHeld = next != nil
            lock.unlock()
            next?.resume()
        }
    }

    private static let gate = Gate()
}
