import Foundation

// ADR-0041 (vault layer consistency and security), plan
// docs/superpowers/plans/2026-09-12-vault-layer-consistency-and-security-cha.md, Task 8 -
// R-07: the disk work of a write moves to one actor, and ordering stops being an accident.
//
// ADR-0043 (vault write ordering), Tasks 4-6 widen this from "the disk work of a write" to
// "the disk work" (§D1): every operation that changes a file in the vault - the note write,
// the non-note `writeFile`, the `FileManager.moveItem` inside `moveFile`, the `trashItem`
// inside `trashFile` - moves inside this actor, and each returns its index consequence in
// one currency, `IndexMutation`, stamped from the same per-path clock `nextSequence(for:)`
// already used for the note write.
//
// One actor hop performs, in order (§D9): the boundary check, the atomic byte write, the
// stat, the record derivation (§D7's shared helper), the version-history write and the
// journal append. Five disk operations that used to be five separate synchronous
// main-actor calls become one suspension. `VaultSession.write` (`VaultSession.swift`)
// computes the hash and records it into `selfWrittenHashes` *before* this hop (§D10), and
// applies the returned `DiskWriteOutcome` through `VaultSession.apply(_:)` (ADR-0043 §D1,
// `VaultSession.swift`) once it resumes.
actor VaultDisk {
    private let store: NoteStore
    private let history: NoteHistory

    /// This path's next write sequence, stamped per call (§D11, widened by ADR-0043 §D1 to
    /// every operation that touches a path, not only a text write). An `actor` serialises
    /// its own state but not the order its callers' continuations resume in, so this is
    /// what lets `VaultSession` tell an in-order outcome from a stale one - never the
    /// order `await`s happen to return in.
    private var sequences: [String: UInt64] = [:]

    init(store: NoteStore, history: NoteHistory) {
        self.store = store
        self.history = history
    }

    private func nextSequence(for relativePath: String) -> UInt64 {
        let next = (sequences[relativePath] ?? 0) + 1
        sequences[relativePath] = next
        return next
    }
}

// MARK: - ADR-0043 §D1 - one currency for what one path's index row must become

extension VaultDisk {
    /// What one path's index row must become, and when that was decided (§D11's clock).
    struct IndexMutation: Sendable {
        let path: String
        /// Nil means there is no file at this path any more (a trash, or the far side of
        /// a move's removal).
        let record: NoteRecord?
        let sequence: UInt64
    }

    /// What one write did, once it made it through the actor (§D9).
    ///
    /// Named `DiskWriteOutcome` rather than `WriteOutcome`, per the task brief: `VaultSession`
    /// already has an unrelated `WriteOutcome` enum (`VaultSession.swift`, `.written`/
    /// `.unchanged`/`.stale`/`.failed`) that this must not collide with or be mistaken for.
    struct DiskWriteOutcome: Sendable {
        /// This write's index consequence (ADR-0043 §D1), replacing the loose
        /// `record`/`sequence` pair `DiskWriteOutcome` carried before this task.
        let mutation: IndexMutation
        /// The hash the actor itself computed from the bytes it wrote. `VaultSession`
        /// asserts this equals the `precomputedHash` it handed in (§D10) rather than
        /// trusting the main actor's copy blindly - a mismatch would mean the text
        /// changed crossing the boundary, which should be impossible and is worth
        /// knowing about if it ever is not.
        let hash: String
        /// Set when the journal could not be written, or when the hash the actor computed
        /// disagreed with `precomputedHash` - the write itself still happened either way,
        /// and this is reported rather than thrown for the same reason
        /// `WriteJournal.record` already returns a problem instead of throwing one.
        let journalProblem: String?

        init(mutation: IndexMutation, hash: String, journalProblem: String?) {
            self.mutation = mutation
            self.hash = hash
            self.journalProblem = journalProblem
        }

        /// Back-compat shape for the outcome-based constructor ADR-0041 §D11 introduced.
        /// `Tests/VaultWriteOrderingTests.swift`'s batch-1
        /// `theOlderOutcomeIsDroppedWhenSequencesArriveInverted` (untouched by this task,
        /// test-authoring scope forbids it) still builds an outcome this way to force an
        /// inversion without a real actor write. A write's own record is never nil, so this
        /// flat shape and the nested `IndexMutation` above describe exactly the same thing.
        init(record: NoteRecord, hash: String, sequence: UInt64, journalProblem: String?) {
            self.init(
                mutation: IndexMutation(path: record.relativePath, record: record, sequence: sequence),
                hash: hash, journalProblem: journalProblem
            )
        }

        var record: NoteRecord? { mutation.record }
        var sequence: UInt64 { mutation.sequence }
    }
}

// MARK: - ADR-0043 §D5 - what only the main actor knows about a journal entry

extension VaultDisk {
    /// What only the main actor knows about a journal entry before this write happens. The
    /// parts that describe the file - `hashBefore`, `textBefore` - are filled in inside the
    /// actor instead (§D5): a claim about a disk transition can only be made where the
    /// transition is serialized.
    struct JournalDescriptor: Sendable {
        let entryID: String
        let timestamp: Date
        let command: String
        let operation: String?
    }
}

// MARK: - The note write

extension VaultDisk {
    /// Writes `text` to `relativePath`, derives its record from the bytes just written,
    /// records history and the journal entry when asked, and stamps the outcome with this
    /// path's next sequence number.
    ///
    /// The record is derived from `text` itself, not from a fresh read of the file after
    /// writing it (ADR-0001 §D2.3): a second writer touching the same path between this
    /// actor's write and a later read must never retroactively change what this write's
    /// own outcome says it wrote.
    ///
    /// **Pre-ADR-0043 shape, kept for `Tests/VaultDiskTests.swift`.** That file is a
    /// tester-owned fixture from ADR-0041 Task 8, not touched by this task's tester
    /// dispatch, and it hands in a complete `WriteJournal.Entry` (its own `hashBefore`
    /// included) rather than the descriptor below. The overload below - distinguished by
    /// its `journalDescriptor:` label, never ambiguous with this one - is what
    /// `VaultSession.write` actually calls (§D5); this one journals exactly the entry it
    /// is given and is otherwise unused in production.
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
            mutation: IndexMutation(path: relativePath, record: record, sequence: nextSequence(for: relativePath)),
            hash: hash,
            journalProblem: journalProblem
        )
    }

    /// The door `VaultSession.write` actually calls (ADR-0043 §D5). Unlike the overload
    /// above, this one reads the file's current bytes itself - `store.text(_:)`
    /// (`NoteStore+ReadSurface.swift`, ADR-0041 §D7), not the full `store.read` - and hashes
    /// them, immediately before writing the new ones, inside the same isolation the write
    /// itself runs in: a journal entry is a claim about a disk transition, and a claim
    /// about a transition can only be made where the transition is serialized. A path that
    /// does not exist yet yields `nil` for both `hashBefore` and `textBefore`, which is
    /// what a creation means.
    ///
    /// `isDryRun` and the "is a journal even armed" decision both stay on the main actor,
    /// travelling with `journalDescriptor` (`nil` when there is nothing to journal) rather
    /// than being re-derived here - the actor never reads a file nobody is going to journal.
    ///
    /// `expecting` (ADR-0043 §D8, Task 9) is compared against `hashBefore` below - the read
    /// this overload already performs for the journal, so the precondition is free. A
    /// mismatch throws `VaultSession.WriteRefusal` before `store.write` is ever called: no
    /// byte moves, no history entry, no journal entry, no index mutation.
    ///
    /// `requiringExistingFolder` (PG-168) sits beside `expecting` for the same ADR-0043 §D5
    /// reason: a claim about a disk transition can only be made where the transition is
    /// serialized. It is a claim about the *container* rather than the contents, which is why it
    /// is a second parameter and not an extension of `expecting` - §D8 excludes a full render
    /// from `expecting` by name (a note composed from Mail has no "before" to expect), and that
    /// exclusion stands unchanged; this precondition is available to exactly that excluded
    /// case, which is where the defect lives. Losing the race between this check and
    /// `store.write` is survivable by construction: in this mode `NoteStore.write` does not
    /// create intermediates, so the byte write fails rather than recreating the folder.
    ///
    /// `expectingAbsent` (ADR-0057 §D3) is the creation-case sibling of `expecting`: when
    /// `true`, a file already at `relativePath` throws `WriteRefusal.movedOn` before any byte
    /// is written. It tests existence (`FileManager.fileExists`), not `textBefore == nil`, so
    /// a file that exists but cannot be read as UTF-8 is refused rather than overwritten -
    /// ADR-0052's «never save over a file you could not read». `VaultSession.write` never
    /// passes it together with a non-nil `expecting`.
    func write(
        _ text: String, to relativePath: String,
        precomputedHash: String,
        expecting: String? = nil,
        expectingAbsent: Bool = false,
        requiringExistingFolder: Bool = false,
        journalDescriptor: JournalDescriptor?,
        journal: WriteJournal?,
        recordsHistory: Bool
    ) async throws -> DiskWriteOutcome {
        // Read before write, in the same isolation: this is the "before" a journal entry
        // for this write can honestly claim (§D5), and now also what `expecting` is
        // checked against.
        let textBefore = try? store.text(relativePath)
        let hashBefore = textBefore.map { NoteStore.hash(Data($0.utf8)) }

        if let expecting, hashBefore != expecting {
            throw VaultSession.WriteRefusal.movedOn(relativePath)
        }
        // Existence, not readability (ADR-0057 §D3): a file that is there but not UTF-8
        // leaves `textBefore` nil, and treating that as absent would overwrite it.
        if expectingAbsent, try fileExists(relativePath) {
            throw VaultSession.WriteRefusal.movedOn(relativePath)
        }

        if requiringExistingFolder {
            let parent = try store.url(for: relativePath).deletingLastPathComponent()
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: parent.path(percentEncoded: false), isDirectory: &isDirectory
            )
            guard exists, isDirectory.boolValue else {
                throw VaultSession.WriteRefusal.folderVanished((relativePath as NSString).deletingLastPathComponent)
            }
        }

        let hash = try store.write(text, to: relativePath, requiringExistingFolder: requiringExistingFolder)

        let fileURL = try store.url(for: relativePath)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
        let record = try store.record(from: Data(text.utf8), attributes: attributes, at: relativePath)

        if recordsHistory {
            history.record(text, for: relativePath)
        }

        var journalProblem: String?
        if let journal, let descriptor = journalDescriptor {
            let entry = WriteJournal.Entry(
                id: descriptor.entryID,
                timestamp: descriptor.timestamp,
                path: relativePath,
                hashBefore: hashBefore,
                hashAfter: hash,
                textBefore: textBefore,
                command: descriptor.command,
                operation: descriptor.operation
            )
            journalProblem = journal.record(entry)
        }

        if hash != precomputedHash {
            let mismatch = "write to \(relativePath): computed hash \(hash) does not match precomputed \(precomputedHash)"
            journalProblem = journalProblem.map { "\($0); \(mismatch)" } ?? mismatch
        }

        return DiskWriteOutcome(
            mutation: IndexMutation(path: relativePath, record: record, sequence: nextSequence(for: relativePath)),
            hash: hash,
            journalProblem: journalProblem
        )
    }

    /// Whether anything is at `relativePath` at all, readable or not (ADR-0057 §D3).
    private func fileExists(_ relativePath: String) throws -> Bool {
        try FileManager.default.fileExists(atPath: store.url(for: relativePath).path(percentEncoded: false))
    }

    /// Whether iCloud left its `.Nota.md.icloud` stub where `relativePath` was - an evicted
    /// note, not a deleted one (ADR-0064 §D2). A path that fails the boundary answers `false`;
    /// `reconcile` has already asked `fileExists` about the same directory by then.
    private func evictedPlaceholderExists(for relativePath: String) -> Bool {
        let directory = (relativePath as NSString).deletingLastPathComponent
        let name = VaultScanner.evictedPlaceholderName(for: (relativePath as NSString).lastPathComponent)
        let placeholder = directory.isEmpty ? name : directory + "/" + name
        return (try? fileExists(placeholder)) ?? false
    }
}

// MARK: - The non-note byte write, the move and the trash (ADR-0043 §D1)

extension VaultDisk {
    /// Writes any file in the vault - a `.canvas` board, most often - without touching the
    /// index or the per-note history, journalling nothing itself.
    ///
    /// `expecting` (ADR-0046 §D5) is compared against the file's current bytes, read here for
    /// that purpose - unlike `write(_:to:precomputedHash:...)` above, this overload performed
    /// no read at all before this, so a guarded board write costs one extra read. The
    /// comparison happens inside the actor, immediately before `store.write`, so no suspension
    /// can separate the read from the write. A path with no file reads as `nil`, which never
    /// equals a non-nil `expecting`, so a vanished board is refused rather than re-created
    /// (§D8).
    ///
    /// **Pre-§D5 shape, kept for `Tests/VaultWriteOrderingTests.swift`**, the same reason the
    /// note write above keeps its own journal-less overload: that file drives this actor's raw
    /// write/move/trash primitives directly, with no journal in play. The overload below -
    /// distinguished by its `journalDescriptor:` label - is what `VaultSession.writeFile`
    /// actually calls (§D5, PG-161/#289).
    func writeFile(_ text: String, to relativePath: String, expecting: String? = nil) async throws -> IndexMutation {
        if let expecting {
            let existing = try? store.text(relativePath)
            let existingHash = existing.map { NoteStore.hash(Data($0.utf8)) }
            guard existingHash == expecting else {
                throw VaultWriteRefusal.movedOn(relativePath)
            }
        }

        let data = Data(text.utf8)
        try store.write(text, to: relativePath)
        let fileURL = try store.url(for: relativePath)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
        let record = try? store.record(from: data, attributes: attributes, at: relativePath)
        return IndexMutation(path: relativePath, record: record, sequence: nextSequence(for: relativePath))
    }

    /// The door `VaultSession.writeFile` actually calls (§D5, PG-161/#289). Unlike the
    /// overload above, this one reads the file's current bytes itself - immediately before
    /// writing the new ones, inside the same isolation the write itself runs in - and
    /// records the journal entry here too: a claim about a disk transition can only be made
    /// where the transition is serialized, the same rule `write(_:to:precomputedHash:
    /// expecting:journalDescriptor:...)` already applies to the note door. Before this, the
    /// main actor read `existing` ahead of the hop in `VaultSession.writeFile` - Race 2's
    /// exact shape (ADR-0043 §"Race 2"), surviving on this door after the note write closed
    /// it on its own (ADR-0046 §D5's note). `journalDescriptor` carries only what the main
    /// actor alone knows - the command, the operation id, the entry id and timestamp.
    func writeFile(
        _ text: String, to relativePath: String,
        expecting: String? = nil,
        expectingAbsent: Bool = false,
        journalDescriptor: JournalDescriptor?,
        journal: WriteJournal?
    ) async throws -> (mutation: IndexMutation, journalProblem: String?) {
        let textBefore = try? store.text(relativePath)
        let hashBefore = textBefore.map { NoteStore.hash(Data($0.utf8)) }

        if let expecting, hashBefore != expecting {
            throw VaultWriteRefusal.movedOn(relativePath)
        }
        // ADR-0063 §D4.5: a creation that must not land on anything. Decided on existence,
        // not on `textBefore` - an unreadable file is still a file (ADR-0057 §D3) - and here,
        // inside the actor, so no suspension separates the check from the write.
        if expectingAbsent, try fileExists(relativePath) {
            throw VaultWriteRefusal.movedOn(relativePath)
        }

        let data = Data(text.utf8)
        let hash = try store.write(text, to: relativePath)
        let fileURL = try store.url(for: relativePath)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
        let record = try? store.record(from: data, attributes: attributes, at: relativePath)

        var journalProblem: String?
        if let journal, let descriptor = journalDescriptor {
            let entry = WriteJournal.Entry(
                id: descriptor.entryID,
                timestamp: descriptor.timestamp,
                path: relativePath,
                hashBefore: hashBefore,
                hashAfter: hash,
                textBefore: textBefore,
                command: descriptor.command,
                operation: descriptor.operation
            )
            journalProblem = journal.record(entry)
        }

        let mutation = IndexMutation(path: relativePath, record: record, sequence: nextSequence(for: relativePath))
        return (mutation, journalProblem)
    }

    /// Moves a file and returns both endpoints' mutations, each stamped from its own
    /// path's clock (§D1) - the removal and the insertion are two different rows and must
    /// be orderable against a concurrent write to either one independently.
    func moveFile(from oldPath: String, to newPath: String) async throws -> [IndexMutation] {
        // Both resolved before any disk touch, so a boundary violation on either end
        // refuses before a single byte moves.
        let destination = try store.url(for: newPath)
        let source = try store.url(for: oldPath)

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: source, to: destination)

        let removal = IndexMutation(path: oldPath, record: nil, sequence: nextSequence(for: oldPath))

        // One read of the moved file, not two (ADR-0041 §D7): the same bytes are hashed
        // for the watcher and handed to `record(from:attributes:at:)` for the index, rather
        // than hashing here and re-reading the file after.
        let movedData = try? Data(contentsOf: destination)
        let movedAttributes = try? FileManager.default.attributesOfItem(
            atPath: destination.path(percentEncoded: false)
        )
        let movedRecord = movedData.flatMap { bytes in
            try? store.record(from: bytes, attributes: movedAttributes ?? [:], at: newPath)
        }
        let insertion = IndexMutation(path: newPath, record: movedRecord, sequence: nextSequence(for: newPath))

        return [removal, insertion]
    }

    /// Moves a file to the Finder's trash and returns the removal (§D1). The trash rather
    /// than an unlink, as it always was: a note deleted by a misclick is recoverable there.
    func trashFile(at relativePath: String) async throws -> IndexMutation {
        let url = try store.url(for: relativePath)
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        return IndexMutation(path: relativePath, record: nil, sequence: nextSequence(for: relativePath))
    }
}

// MARK: - The watcher's reconciliation (ADR-0043 §D3)

extension VaultDisk {
    /// Reads one changed path, compares against the hashes the session recorded for it,
    /// advances that path's clock and says both what the index must become and whether
    /// anybody outside this process wrote it.
    ///
    /// Advancing the clock on a read, found or missing, is deliberate and is what makes
    /// the guard total (§D3): the mutation describes the file as this actor saw it at the
    /// moment it looked, on the same per-path clock every write, move and trash share - a
    /// write that lands afterwards is newer and must win, one that already landed before is
    /// older and must lose.
    ///
    /// `selfWritten` is the session's `selfWrittenHashes` list for this path (ADR-0043 §D6):
    /// a file read here whose content hash matches an entry is the session's own write,
    /// and `matchedSequence` names that entry so the caller can prune. An absence marker
    /// (`VaultSession.absenceMarker`, ADR-0064 §D6) is matched only when nothing at all is
    /// at the path - a move this session made vacated it - and never against a file read.
    ///
    /// A path that cannot be read reports `.deleted` only when it is absent (ADR-0064 §D2):
    /// nothing at the path, no iCloud placeholder for it, no matching absence. A file that
    /// is there but unreadable, an evicted note, or a path outside the vault reports
    /// nothing.
    func reconcile(
        _ relativePath: String, selfWritten: [(sequence: UInt64, hash: String)]
    ) async -> (mutation: IndexMutation, change: VaultSession.ExternalChange?, matchedSequence: UInt64?) {
        guard let (record, text) = try? store.read(relativePath) else {
            // Nothing usable to index either way, so the mutation is the same for every
            // reason the read failed: `record: nil`, the clock advanced once. Nothing ever
            // applies it over a real record it did not observe.
            let mutation = IndexMutation(path: relativePath, record: nil, sequence: nextSequence(for: relativePath))
            // What is reported is decided on existence, not readability (§D2, the rule
            // ADR-0057 §D3 applies to `expectingAbsent`): a file that is there but not
            // UTF-8 is not a deletion, and neither is a path that fails the boundary.
            guard let present = try? fileExists(relativePath), !present,
                  !evictedPlaceholderExists(for: relativePath)
            else {
                return (mutation, nil, nil)
            }
            if let matched = selfWritten.last(where: { $0.hash == VaultSession.absenceMarker }) {
                return (mutation, nil, matched.sequence)
            }
            return (mutation, VaultSession.ExternalChange(path: relativePath, content: .deleted), nil)
        }

        let mutation = IndexMutation(path: relativePath, record: record, sequence: nextSequence(for: relativePath))
        if let matched = selfWritten.last(where: { $0.hash == record.contentHash }) {
            return (mutation, nil, matched.sequence)
        }
        return (mutation, VaultSession.ExternalChange(path: relativePath, content: .text(text)), nil)
    }
}
