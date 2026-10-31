import Foundation

/// Lets one connector call at a time through, in the order they arrived (PG-438).
///
/// The three guardrails of ADR-0007 §D6 are state on the session, by design: `VaultAPI.arm`
/// sets `isDryRun`, `journalCommand` and `journal` on the one `VaultSession`, and every write
/// underneath reads them from there rather than being handed them. That holds per call, and
/// only per call. The MCP SDK runs each request in a task of its own, and a call suspends -
/// at the rescan, inside a write - so a second call could re-arm the session while the first
/// was still writing: a `dryRun: true` arriving mid-flight turned a real write into an
/// unjournalled rehearsal, half-applied across the files of a multi-file verb. The calls
/// must not overlap, and this is what keeps them apart.
///
/// A FIFO mutex on the main actor, where the session already lives. The body runs inline in
/// the caller's task: no unstructured `Task`, so nothing has to be `Sendable` to cross into
/// one. Release hands ownership straight to the first waiter rather than clearing the flag,
/// so a call arriving in between queues behind it instead of jumping the line. A waiter
/// whose task is cancelled is still resumed in turn and runs its body: cancellation here
/// would only add a way to leave the queue wedged.
///
/// Not reentrant: a body that calls `run` on the same gate waits on itself forever.
/// Shared with `perg` because it lives under `Sources/Connector`, but only the MCP host
/// needs it - `perg` makes one call per process.
@MainActor
final class ConnectorCallGate {
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T>(_ body: () async throws -> T) async rethrows -> T {
        if isBusy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            isBusy = true
        }
        defer {
            if waiters.isEmpty {
                isBusy = false
            } else {
                waiters.removeFirst().resume()
            }
        }
        return try await body()
    }
}
