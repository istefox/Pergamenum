import Foundation

/// The gesture a write belongs to, carried by the task that issues the write rather than by the
/// session it writes through (ADR-0050 §D1).
///
/// `VaultSession.transaction(_:_:)` opens one of these for the duration of its body. Every write
/// the body issues - directly, through a structured child, or through an unstructured `Task { }`
/// it starts - reads the same value back and stamps the journal entry with it, which is what lets
/// `undo` reverse the whole gesture as one thing (ADR-0016 §D1).
///
/// **Why a task-local and not a property on the session.** `transaction`'s body is `async`
/// (ADR-0043 §D2), so its scope spans suspensions, and a `@MainActor` property set for that
/// scope is shared with every other task the main actor runs in between. Two transactions
/// started from two `Task { }`s interleaved on that property: the second found the first's id
/// still set and either tripped the nested-transaction assertion or joined the wrong gesture,
/// and the first's `defer` then cleared the id under the second's remaining writes (`PG-152`,
/// issue #281). A task-local is bound per task: two concurrent transactions each see their own,
/// a write outside any transaction sees `nil`, and nothing is ever reset by the wrong party.
///
/// An operation *stack* on the actor - the shape the issue sketched - would have solved
/// nesting, which was never the failure, and not interleaving, which was: with two gestures
/// open the top of the stack is still one of them, and a write from the other still joins it.
/// The one fact a write needs is which task tree issued it, and that is the one fact only the
/// task can carry.
///
/// Foundation-only and `Sendable` by construction (two `String`s), so it compiles into `perg`
/// and `pergamenum-mcp` as `Sources/Core/**` does and can cross the `VaultDisk` actor hop in
/// a `JournalDescriptor` exactly as the two strings did before.
struct JournalGesture: Equatable, Sendable {
    /// The id every journal entry written inside the gesture carries as `operation`.
    let operation: String
    /// What the journal records as the cause for those entries.
    let command: String

    /// The gesture the current task is inside, or `nil` when it is inside none.
    ///
    /// Bound only by `VaultSession.transaction(_:_:)`, through `$current.withValue`; nothing
    /// assigns it. Inherited by structured children and by an unstructured `Task { }` created
    /// inside the binding (§D3), not by `Task.detached`, which by design inherits nothing.
    @TaskLocal static var current: JournalGesture?
}
