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
