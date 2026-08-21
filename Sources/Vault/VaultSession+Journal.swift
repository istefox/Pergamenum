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
    /// The command is set for the duration and restored after, so a caller that had its own
    /// `journalCommand` gets it back - the same borrow-and-return `VaultSession+TagRename`
    /// already performs around the journal itself.
    ///
    /// **Nested transactions are a programming error, not a feature.** Two ids would be open at
    /// once and the inner writes would silently join the wrong gesture, which is the failure a
    /// second `undo` would then complete. An `assertionFailure` says so on the first Debug run;
    /// in Release the body still runs, under the gesture already open, because refusing to
    /// perform a write the user asked for would be the worse of the two wrongs.
    @discardableResult
    func transaction<T>(_ command: String, _ body: () throws -> T) rethrows -> T {
        guard currentOperation == nil else {
            assertionFailure("transazione annidata: «\(command)» dentro «\(journalCommand)»")
            return try body()
        }
        let previousCommand = journalCommand
        journalCommand = command
        currentOperation = WriteJournal.makeID(at: Date())
        defer {
            currentOperation = nil
            journalCommand = previousCommand
        }
        return try body()
    }

    /// The id of the gesture that just closed, for a caller that has to offer to undo it.
    ///
    /// Read inside the transaction, because outside it there is nothing to read. A caller that
    /// wants it does `var id: String?; transaction("…") { id = openOperation; … }`.
    var openOperation: String? { currentOperation }

    // MARK: The two shape changes

    /// Moves a file and records that it moved, so `undo` can move it back.
    ///
    /// The bytes do not change, so both hashes are the file's own: what makes this reversible is
    /// `pathBefore`, not the text. There is no `textBefore` - a move has nothing to restore.
    func moveFile(from oldPath: String, to newPath: String) throws {
        guard oldPath != newPath else { return }
        guard exists(oldPath) else { throw NoteFileOperations.OperationError.missing(oldPath) }
        guard !exists(newPath) else {
            throw NoteFileOperations.OperationError.alreadyExists(newPath)
        }
        guard !isDryRun else { return }

        let destination = store.url(for: newPath)
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: store.url(for: oldPath), to: destination)
        } catch {
            throw NoteFileOperations.OperationError.failed(
                "spostamento: \(error.localizedDescription)"
            )
        }

        let hash = (try? Data(contentsOf: destination)).map(NoteStore.hash) ?? ""
        selfWrittenHashes[newPath] = hash
        updateIndex(nil, at: oldPath)
        updateIndex(try? store.read(newPath).record, at: newPath)

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
    func trashFile(at relativePath: String) throws {
        guard exists(relativePath) else {
            throw NoteFileOperations.OperationError.missing(relativePath)
        }
        // Read before the refusal to perform, not after: a dry run that skipped the read would
        // not discover an unreadable file, and the real thing would then fail where the
        // rehearsal had said it was fine.
        let data = try? Data(contentsOf: store.url(for: relativePath))
        guard !isDryRun else { return }

        do {
            try FileManager.default.trashItem(
                at: store.url(for: relativePath), resultingItemURL: nil
            )
        } catch {
            throw NoteFileOperations.OperationError.failed(
                "eliminazione: \(error.localizedDescription)"
            )
        }

        updateIndex(nil, at: relativePath)
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
    func writeFile(_ text: String, to relativePath: String) throws {
        let existing = (journal != nil && !isDryRun)
            ? try? String(contentsOf: store.url(for: relativePath), encoding: .utf8)
            : nil
        guard !isDryRun else { return }

        let url = store.url(for: relativePath)
        let data = Data(text.utf8)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw NoteFileOperations.OperationError.failed(
                "scrittura: \(error.localizedDescription)"
            )
        }
        let hash = NoteStore.hash(data)
        selfWrittenHashes[relativePath] = hash

        record(WriteJournal.Entry(
            id: WriteJournal.makeID(at: Date()),
            timestamp: Date(),
            path: relativePath,
            hashBefore: existing.map { NoteStore.hash(Data($0.utf8)) },
            hashAfter: hash,
            textBefore: existing,
            command: journalCommand,
            operation: currentOperation
        ))
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
    func undo(operation id: String) -> TagRenameOutcome {
        let members = WriteJournal(root: root).entries(operation: id)
        guard !members.isEmpty else {
            return TagRenameOutcome(failures: ["\(id): non è un'operazione nel journal"])
        }

        let failures = preflightUndo(members)
        guard failures.isEmpty else { return TagRenameOutcome(failures: failures) }

        let (changed, runtimeFailures) = performUndo(members)
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
    func performUndo(_ entries: [WriteJournal.Entry]) -> (changed: [String], failures: [String]) {
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
                        try writeFile(textBefore, to: entry.path)
                    } else {
                        try write(textBefore, to: entry.path)
                    }
                    changed.append(entry.path)
                case .removal:
                    guard let textBefore = entry.textBefore else {
                        failures.append("\(entry.path): il journal non ha il testo da ripristinare")
                        continue
                    }
                    try write(textBefore, to: entry.path)
                    changed.append(entry.path)
                case .move:
                    guard let pathBefore = entry.pathBefore else {
                        failures.append("\(entry.path): il journal non sa da dove veniva")
                        continue
                    }
                    try moveFile(from: entry.path, to: pathBefore)
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
        (try? Data(contentsOf: store.url(for: relativePath))).map(NoteStore.hash)
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
