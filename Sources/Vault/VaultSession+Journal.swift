import Foundation

/// The gesture, and the two things a gesture can do to a file that a text write cannot
/// (ADR-0016 §D6).
///
/// `write(_:to:)` stays exactly where it was and does exactly what it did. What is here is the
/// scope that groups several writes into one reversible thing, and the two primitives that
/// change a file's *shape* rather than its text - a move and a removal - which the journal could
/// not describe at all until ADR-0016 §D2 gave it the vocabulary.
///
/// **`isDryRun` covers all of it or it covers nothing.** Each of the three validates first and
/// stops one line short of the disk, so a dry run refuses exactly what the real thing refuses -
/// the rule `write` has followed since ADR-0007 §D6, applied to the two operations that would
/// otherwise be the ones a dry run silently performed.
extension VaultSession {
    // MARK: The gesture

    /// Runs `body` as one gesture: every write inside it carries the same operation id, and
    /// `undo` given that id reverses all of them.
    ///
    /// The gesture - its id and its command - is bound to the **calling task**, not stored on
    /// the session (ADR-0050 §D1): `JournalGesture.current` is a task-local, so `journalCommand`
    /// and `currentOperation` read it back from inside the body and read the session's standing
    /// command and `nil` from anywhere else. A caller that had its own `journalCommand` finds it
    /// untouched afterwards, because the gesture never wrote over it - the borrow-and-return
    /// `VaultSession+TagRename` performs by hand around the journal itself is here performed by
    /// the binding's own scope.
    ///
    /// **Two transactions open at once from two tasks are not nested (ADR-0050 §D2).** That was
    /// `PG-152` (issue #281): with the id kept on this `@MainActor` object and an `async` body
    /// (ADR-0043 §D2), the scope spanned a suspension, the second `Task { }` found the first's
    /// id still set and either tripped the assertion below or joined the first gesture, and the
    /// first's `defer` then cleared the id under the second's remaining writes. Each task now
    /// carries its own binding, so the interleaving cannot be observed: the writes of each land
    /// under their own id and their own command, whichever order the main actor runs them in.
    ///
    /// **Nested transactions in one task are still a programming error, not a feature.** Two ids
    /// would be open at once and the inner writes would silently join the wrong gesture, which is
    /// the failure a second `undo` would then complete. The task-local makes the check exact - a
    /// non-`nil` value here can only have been bound by an enclosing `transaction` on this task's
    /// own tree - and an `assertionFailure` says so on the first Debug run; in Release the body
    /// still runs, under the gesture already open, because refusing to perform a write the user
    /// asked for would be the worse of the two wrongs.
    @discardableResult
    func transaction<T>(_ command: String, _ body: () async throws -> T) async rethrows -> T {
        guard JournalGesture.current == nil else {
            assertionFailure("transazione annidata: «\(command)» dentro «\(journalCommand)»")
            return try await body()
        }
        let gesture = JournalGesture(operation: WriteJournal.makeID(at: Date()), command: command)
        return try await JournalGesture.$current.withValue(gesture) {
            try await body()
        }
    }

    // MARK: The two shape changes

    /// Moves a file and records that it moved, so `undo` can move it back.
    ///
    /// The bytes do not change, so both hashes are the file's own: what makes this reversible is
    /// `pathBefore`, not the text. There is no `textBefore` - a move has nothing to restore.
    func moveFile(from oldPath: String, to newPath: String) async throws {
        guard oldPath != newPath else { return }
        guard exists(oldPath) else { throw FileOperationError.missing(oldPath) }
        guard !exists(newPath) else {
            throw FileOperationError.alreadyExists(newPath)
        }
        guard !isDryRun else { return }

        // ADR-0043 §D1: the `FileManager.moveItem` and the record derivation on the far
        // side both move inside `VaultDisk`, stamped from that path's own clock.
        let mutations: [VaultDisk.IndexMutation]
        do {
            mutations = try await disk.moveFile(from: oldPath, to: newPath)
        } catch {
            throw FileOperationError.failed(
                "spostamento: \(error.localizedDescription)"
            )
        }
        apply(mutations)

        let newMutation = mutations.first { $0.path == newPath }
        let hash = newMutation?.record?.contentHash ?? ""
        // Task 7: same sequence-tagged shape as `write(_:to:expecting:)` - the mutation
        // is already real by this point (the actor hop already resumed), so this is the
        // sequence itself rather than a provisional one to correct later.
        selfWrittenHashes[newPath, default: []].append((sequence: newMutation?.sequence ?? 0, hash: hash))

        record(WriteJournal.Entry(
            id: WriteJournal.makeID(at: Date()),
            timestamp: Date(),
            path: newPath,
            hashBefore: hash,
            hashAfter: hash,
            textBefore: nil,
            command: journalCommand,
            operation: currentOperation,
            kind: .move,
            pathBefore: oldPath
        ))
    }

    /// Moves a file to the Finder's trash and records its whole text, so `undo` can write it
    /// back (ADR-0016 §D3).
    ///
    /// The trash rather than an unlink, as it always was: a note deleted by a misclick is
    /// recoverable there and nothing this app does is worth making that unrecoverable. The
    /// journal keeps the text because the trash is outside this app's control and can be
    /// emptied - a net that depends on it is a net this app cannot promise.
    ///
    /// `hashAfter` is empty, and that is the honest value: there is no file after this.
    func trashFile(at relativePath: String) async throws {
        guard exists(relativePath) else {
            throw FileOperationError.missing(relativePath)
        }
        // Read before the refusal to perform, not after: a dry run that skipped the read would
        // not discover an unreadable file, and the real thing would then fail where the
        // rehearsal had said it was fine.
        let data = (try? store.url(for: relativePath)).flatMap { try? Data(contentsOf: $0) }
        guard !isDryRun else { return }

        // ADR-0043 §D1: the `trashItem` call moves inside `VaultDisk`, stamped from this
        // path's own clock.
        let mutation: VaultDisk.IndexMutation
        do {
            mutation = try await disk.trashFile(at: relativePath)
        } catch {
            throw FileOperationError.failed(
                "eliminazione: \(error.localizedDescription)"
            )
        }
        apply([mutation])
        selfWrittenHashes.removeValue(forKey: relativePath)

        record(WriteJournal.Entry(
            id: WriteJournal.makeID(at: Date()),
            timestamp: Date(),
            path: relativePath,
            hashBefore: data.map(NoteStore.hash),
            hashAfter: "",
            textBefore: data.flatMap { String(data: $0, encoding: .utf8) },
            command: journalCommand,
            operation: currentOperation,
            kind: .removal
        ))
    }

    // MARK: A file that is not a note

    /// Writes any file in the vault, journalled, without touching the index or the per-note
    /// history.
    ///
    /// For the `.canvas` documents a rename repoints: a board is not a note, so `write(_:to:)`
    /// would re-read a `NoteRecord` that is not there. Everything else about it is the same,
    /// including the journal entry, which is what stops a board card from being the one part of
    /// a rename that cannot be undone.
    ///
    /// `expecting` (ADR-0046 §D5) forwards straight to `VaultDisk.writeFile`.
    ///
    /// **§D5 fix (PG-161/#289):** the journal's own «before» no longer reads on the main
    /// actor ahead of the hop - that read, and the suspension right after it, was Race 2
    /// (ADR-0043 §"Race 2") surviving on this door after `write(_:to:)` closed it on its
    /// own. Only what the main actor alone knows - the command, the operation id, the entry
    /// id and timestamp - travels across, as a `JournalDescriptor`, built only when a
    /// journal is armed. `VaultDisk.writeFile` reads the current bytes itself, immediately
    /// before writing the new ones, inside the same isolation, exactly like the note write.
    func writeFile(_ text: String, to relativePath: String, expecting: String? = nil) async throws {
        guard !isDryRun else { return }

        var journalDescriptor: VaultDisk.JournalDescriptor?
        if journal != nil {
            let now = Date()
            journalDescriptor = VaultDisk.JournalDescriptor(
                entryID: WriteJournal.makeID(at: now),
                timestamp: now,
                command: journalCommand,
                operation: currentOperation
            )
        }

        // ADR-0043 §D1: the byte write moves inside `VaultDisk` too. Its sequence is kept
        // for `selfWrittenHashes` below (Task 7) but the mutation itself is never applied
        // to the index - a board is not a note, unchanged from before this task.
        let outcome: (mutation: VaultDisk.IndexMutation, journalProblem: String?)
        do {
            outcome = try await disk.writeFile(
                text, to: relativePath,
                expecting: expecting,
                journalDescriptor: journalDescriptor,
                journal: journal
            )
        } catch let refusal as VaultWriteRefusal {
            // Rethrown as-is, not wrapped: a refusal is its own channel
            // (`VaultPlanApplication.apply` classifies it apart from `failures`, ADR-0046 §D4),
            // the same shape `VaultSession.write`'s own catch-all already keeps.
            throw refusal
        } catch {
            throw FileOperationError.failed(
                "scrittura: \(error.localizedDescription)"
            )
        }
        let hash = NoteStore.hash(Data(text.utf8))
        selfWrittenHashes[relativePath, default: []].append((sequence: outcome.mutation.sequence, hash: hash))
        if let problem = outcome.journalProblem { recordProblem(problem) }
    }

    // MARK: Undo of a gesture (ADR-0016 §D5)

    /// Puts every write of one gesture back, all of it or none of it.
    ///
    /// Reads every entry the gesture wrote and checks each one **before touching any of
    /// them**: the file is still there, its hash still matches what the journal wrote, and a
    /// removal's path is still free. If any member fails that check, the whole undo is refused
    /// and nothing moves - half a rename put back is the exact state D1 exists to prevent, and
    /// it is why this is a decision distinct from D4's "a failed gesture is not rolled back".
    ///
    /// Newest first once every check has passed: a rename writes the move and then the link
    /// texts, so reversing it has to put the texts back before the file moves back.
    @discardableResult
    func undo(operation id: String) async -> TagRenameOutcome {
        let members = journalOnDisk.entries(operation: id)
        guard !members.isEmpty else {
            return TagRenameOutcome(failures: ["\(id): non è un'operazione nel journal"])
        }

        let failures = preflightUndo(members)
        guard failures.isEmpty else { return TagRenameOutcome(failures: failures) }

        let (changed, runtimeFailures) = await performUndo(members)
        return TagRenameOutcome(changed: changed, failures: runtimeFailures)
    }

    /// Checks that every entry can be reversed, without reversing any of them.
    ///
    /// Shared between `undo(operation:)` above and `undoJournalledWrites(_:)` in
    /// `VaultSession+TagRename.swift`, which took the same guard on one entry at a time before
    /// this plan and now takes it on the whole group it was given - the shared function is what
    /// stops the two from drifting onto different guards for the same three kinds.
    func preflightUndo(_ entries: [WriteJournal.Entry]) -> [String] {
        entries.compactMap(preflightUndo(_:))
    }

    /// One entry's half of the guard above, split by kind into the three functions below so
    /// each stays plainly readable on its own rather than one switch doing all three at once.
    private func preflightUndo(_ entry: WriteJournal.Entry) -> String? {
        switch entry.kind {
        case .textReplacement: preflightTextReplacement(entry)
        case .move: preflightMove(entry)
        case .removal: preflightRemoval(entry)
        }
    }

    private func preflightTextReplacement(_ entry: WriteJournal.Entry) -> String? {
        guard exists(entry.path) else { return "\(entry.path): non c'è più" }
        guard currentHash(at: entry.path) == entry.hashAfter else {
            return "\(entry.path): è cambiato dopo quella scrittura, non lo tocco"
        }
        guard entry.textBefore != nil else { return "\(entry.path): quella scrittura ha creato il file" }
        return nil
    }

    private func preflightMove(_ entry: WriteJournal.Entry) -> String? {
        guard exists(entry.path) else { return "\(entry.path): non c'è più" }
        guard currentHash(at: entry.path) == entry.hashAfter else {
            return "\(entry.path): è cambiato dopo lo spostamento, non lo tocco"
        }
        guard let pathBefore = entry.pathBefore, !exists(pathBefore) else {
            return "\(entry.pathBefore ?? entry.path): occupato, non lo sovrascrivo"
        }
        return nil
    }

    /// The guard that protects a file restored by hand from the Finder: undoing a trash onto a
    /// path something else now occupies would silently overwrite it.
    private func preflightRemoval(_ entry: WriteJournal.Entry) -> String? {
        guard !exists(entry.path) else { return "\(entry.path): è tornato al suo posto, non lo sovrascrivo" }
        guard entry.textBefore != nil else {
            return "\(entry.path): il journal non ha il testo da ripristinare"
        }
        return nil
    }

    /// Reverses every entry `preflightUndo` has already cleared, newest first.
    ///
    /// The individual writes can still fail here - the disk between the check and the write is
    /// the same narrow window D4 already accepts for a gesture going forward - so a failure is
    /// reported rather than assumed impossible.
    func performUndo(_ entries: [WriteJournal.Entry]) async -> (changed: [String], failures: [String]) {
        var changed: [String] = []
        var failures: [String] = []
        for entry in entries.reversed() {
            do {
                switch entry.kind {
                case .textReplacement:
                    guard let textBefore = entry.textBefore else {
                        failures.append("\(entry.path): il journal non ha il testo da ripristinare")
                        continue
                    }
                    // A board went through `writeFile`, never through `write`, when a rename or a
                    // move originally repointed it: reversing it through `write` would read the
                    // JSON back as a note and leave a bogus record in the index.
                    if entry.path.hasSuffix(".\(CanvasStore.fileExtension)") {
                        try await writeFile(textBefore, to: entry.path)
                    } else {
                        try await write(textBefore, to: entry.path)
                    }
                    changed.append(entry.path)
                case .removal:
                    guard let textBefore = entry.textBefore else {
                        failures.append("\(entry.path): il journal non ha il testo da ripristinare")
                        continue
                    }
                    try await write(textBefore, to: entry.path)
                    changed.append(entry.path)
                case .move:
                    guard let pathBefore = entry.pathBefore else {
                        failures.append("\(entry.path): il journal non sa da dove veniva")
                        continue
                    }
                    try await moveFile(from: entry.path, to: pathBefore)
                    changed.append(pathBefore)
                }
            } catch {
                failures.append("\(entry.path): \(error.localizedDescription)")
            }
        }
        return (changed, failures)
    }

    /// The file's current hash, or nil when there is none to read - comparable to
    /// `entry.hashBefore`/`hashAfter` regardless of kind, since both are `NoteStore.hash` over
    /// raw bytes.
    private func currentHash(at relativePath: String) -> String? {
        (try? store.url(for: relativePath))
            .flatMap { try? Data(contentsOf: $0) }
            .map(NoteStore.hash)
    }

    // MARK: Support

    /// Appends to the journal when one is armed, and says so when it could not.
    ///
    /// The write happened; the net did not. `write(_:to:)` has reported that rather than
    /// pretending the change is undoable since ADR-0007, and the three primitives above owe the
    /// same honesty for the same reason.
    private func record(_ entry: WriteJournal.Entry) {
        guard let journal else { return }
        if let problem = journal.record(entry) { recordProblem(problem) }
    }

}
