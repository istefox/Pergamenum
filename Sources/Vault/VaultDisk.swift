import Foundation

// ADR-0041 (vault layer consistency and security), plan
// docs/superpowers/plans/2026-09-12-vault-layer-consistency-and-security-cha.md, Task 8 -
// R-07: the disk work of a write moves to one actor, and ordering stops being an accident.
//
// **Tester dispatch (ADR-0049 generator/verifier separation).** This file declares the
// exact API surface the brief specifies and nothing else. `write(_:to:precomputedHash:
// journalEntry:journal:recordsHistory:)` below is a stub that always throws: the real
// body - the boundary check, the atomic byte write, the stat, the record derivation
// through `NoteStore.record(from:attributes:at:)` (Task 6), the history write, the journal
// append, and the per-path sequence stamping §D9-§D11 describe - is the coder's job. Every
// `VaultDiskTests` case that exercises this actor is red until that lands, by design.
actor VaultDisk {
    private let store: NoteStore
    private let history: NoteHistory

    init(store: NoteStore, history: NoteHistory) {
        self.store = store
        self.history = history
    }

    /// What one write did, once it made it through the actor (§D9).
    ///
    /// Named `DiskWriteOutcome` rather than `WriteOutcome`, per the task brief: `VaultSession`
    /// already has an unrelated `WriteOutcome` enum (`VaultSession.swift`, `.written`/
    /// `.unchanged`/`.stale`/`.failed`) that this must not collide with or be mistaken for.
    struct DiskWriteOutcome: Sendable {
        let record: NoteRecord
        /// The hash the actor itself computed from the bytes it wrote. `VaultSession`
        /// asserts this equals the `precomputedHash` it handed in (§D10) rather than
        /// trusting the main actor's copy blindly - a mismatch would mean the text
        /// changed crossing the boundary, which should be impossible and is worth
        /// knowing about if it ever is not.
        let hash: String
        /// This path's write sequence, strictly increasing per path (§D11).
        let sequence: UInt64
        /// Set when the journal could not be written, naming why - the write itself
        /// still happened, and this is reported rather than thrown for the same reason
        /// `WriteJournal.record` already returns a problem instead of throwing one.
        let journalProblem: String?
    }

    /// Thrown by every path through the stub body below. Not a production error case -
    /// nothing in `Sources/` ever catches it by name - just what keeps a call to this
    /// actor red instead of crashing the whole test process outright.
    enum StubError: Error, CustomStringConvertible {
        case notImplemented

        var description: String {
            """
            VaultDisk.write is a Task 8 tester stub (ADR-0041 §D9): the actor body - \
            boundary check, atomic write, stat, record derivation, history write, journal \
            append, sequence stamping - is the coder's implementation and has not landed yet.
            """
        }
    }

    /// STUB (ADR-0041 Task 8, tester dispatch): declares the exact signature the brief
    /// specifies. Touches no disk, tracks no per-path sequence, and always throws before
    /// doing anything - the coder replaces this body with the real §D9-§D11 behaviour.
    func write(
        _ text: String, to relativePath: String,
        precomputedHash: String,
        journalEntry: WriteJournal.Entry?,
        journal: WriteJournal?,
        recordsHistory: Bool
    ) async throws -> DiskWriteOutcome {
        throw StubError.notImplemented
    }
}
