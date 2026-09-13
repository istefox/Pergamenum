import Foundation

// ADR-0041 (vault layer consistency and security), plan
// docs/superpowers/plans/2026-09-12-vault-layer-consistency-and-security-cha.md, Task 8 -
// R-07: the disk work of a write moves to one actor, and ordering stops being an accident.
//
// One actor hop performs, in order (§D9): the boundary check, the atomic byte write, the
// stat, the record derivation (§D7's shared helper), the version-history write and the
// journal append. Five disk operations that used to be five separate synchronous
// main-actor calls become one suspension. `VaultSession.write` (`VaultSession.swift`)
// computes the hash and records it into `selfWrittenHashes` *before* this hop (§D10), and
// applies the returned `DiskWriteOutcome` through the per-path sequence guard in
// `VaultSession+WriteOrdering.swift` (§D11) once it resumes.
actor VaultDisk {
    private let store: NoteStore
    private let history: NoteHistory

    /// This path's next write sequence, stamped per call (§D11). An `actor` serialises
    /// its own state but not the order its callers' continuations resume in, so this is
    /// what lets `VaultSession` tell an in-order outcome from a stale one - never the
    /// order `await`s happen to return in.
    private var sequences: [String: UInt64] = [:]

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
        /// Set when the journal could not be written, or when the hash the actor computed
        /// disagreed with `precomputedHash` - the write itself still happened either way,
        /// and this is reported rather than thrown for the same reason
        /// `WriteJournal.record` already returns a problem instead of throwing one.
        let journalProblem: String?
    }

    /// Writes `text` to `relativePath`, derives its record from the bytes just written,
    /// records history and the journal entry when asked, and stamps the outcome with this
    /// path's next sequence number.
    ///
    /// The record is derived from `text` itself, not from a fresh read of the file after
    /// writing it (ADR-0001 §D2.3): a second writer touching the same path between this
    /// actor's write and a later read must never retroactively change what this write's
    /// own outcome says it wrote.
    func write(
        _ text: String, to relativePath: String,
        precomputedHash: String,
        journalEntry: WriteJournal.Entry?,
        journal: WriteJournal?,
        recordsHistory: Bool
    ) async throws -> DiskWriteOutcome {
        // Boundary check + atomic byte write, in one call: `NoteStore.write` resolves
        // `relativePath` through `VaultBoundary` and throws before a single byte lands
        // anywhere, on or off the vault.
        let hash = try store.write(text, to: relativePath)

        // Stat, then derive the record from the bytes this call itself wrote.
        let fileURL = try store.url(for: relativePath)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
        let record = try store.record(from: Data(text.utf8), attributes: attributes, at: relativePath)

        // Unconditional and scoped to notes (ADR-0011 §D2): the decision itself is made by
        // the caller on the main actor and handed in as `recordsHistory` - only the write
        // moves in here.
        if recordsHistory {
            history.record(text, for: relativePath)
        }

        var journalProblem: String?
        if let journal, let journalEntry {
            journalProblem = journal.record(journalEntry)
        }

        // §D9/§D10: it should be impossible for the bytes just written to hash to
        // anything other than what the main actor precomputed before the hop. A
        // disagreement would mean the text changed crossing the boundary, which is worth
        // knowing about rather than trusted silently.
        if hash != precomputedHash {
            let mismatch = "write to \(relativePath): computed hash \(hash) does not match precomputed \(precomputedHash)"
            journalProblem = journalProblem.map { "\($0); \(mismatch)" } ?? mismatch
        }

        return DiskWriteOutcome(
            record: record,
            hash: hash,
            sequence: nextSequence(for: relativePath),
            journalProblem: journalProblem
        )
    }

    private func nextSequence(for relativePath: String) -> UInt64 {
        let next = (sequences[relativePath] ?? 0) + 1
        sequences[relativePath] = next
        return next
    }
}
