import Foundation

/// Everything a connector can change, and the three guardrails around it (ADR-0007 §D6).
///
/// One place, so a connector cannot be given a new write that quietly skips them:
/// arming a session for writing hands it the journal and the dry-run switch whether the
/// caller remembers them or not.
extension VaultAPI {
    /// What a `task done|reopen|reschedule` asks for.
    enum TaskChangeRequest {
        case done
        case reopen
        /// A date, or `none` to clear the day it was scheduled for.
        case reschedule(to: String)

        var verb: String {
            switch self {
            case .done: "done"
            case .reopen: "reopen"
            case .reschedule: "reschedule"
            }
        }
    }

    /// Arms an open session for a write.
    ///
    /// No journal for a dry run: nothing happened, and an entry saying otherwise would
    /// be a lie in the one file whose job is to be trusted.
    @MainActor
    static func arm(_ session: VaultSession, command: String, dryRun: Bool) {
        session.isDryRun = dryRun
        session.journalCommand = command
        session.journal = dryRun ? nil : WriteJournal(root: session.root)
    }

    /// Describes a write, as a diff when it was a rehearsal and as a bare fact when it
    /// was real.
    ///
    /// The diff is computed against what is on disk *now* rather than against anything
    /// the session held, so what it shows is what would actually change.
    @MainActor
    static func summarise(
        _ result: VaultSession.WriteResult, session: VaultSession, note: String? = nil
    ) -> WriteSummary {
        let existing = try? session.read(result.path).text
        return WriteSummary(
            path: result.path,
            applied: !session.isDryRun,
            diff: UnifiedDiff.between(
                existing ?? "", result.text, path: result.path, isNew: existing == nil
            ),
            note: note
        )
    }

    // MARK: Notes

    @MainActor
    static func createNote(
        _ session: VaultSession, title: String, folder: String?, topic: String?, date: String?
    ) throws -> WriteSummary {
        guard !title.isEmpty else {
            throw ConnectorError("serve un titolo per la nota", usage: true)
        }
        let topics = try topic.map { raw -> [Tag] in
            guard let tag = Tag(raw) else {
                throw ConnectorError("«\(raw)» non è un tag valido", usage: true)
            }
            return [tag]
        } ?? []

        do {
            let result = try session.createNote(
                title: title, in: folder ?? "", date: try day(date), topics: topics
            )
            return summarise(result, session: session)
        } catch let refusal as VaultSession.CreationError {
            throw ConnectorError("\(refusal)")
        }
    }

    @MainActor
    static func appendToNote(
        _ session: VaultSession, at path: String, text: String
    ) throws -> WriteSummary {
        guard !text.isEmpty else {
            throw ConnectorError("serve il testo da aggiungere", usage: true)
        }
        guard session.exists(path) else { throw ConnectorError("«\(path)» non esiste") }

        guard case .written(let result) = session.append(text: text, to: path) else {
            throw ConnectorError("non scritto: \(session.problems.last ?? "motivo sconosciuto")")
        }
        return summarise(result, session: session)
    }

    // MARK: Renaming, moving, trashing (ADR-0016)

    @MainActor
    static func renameNote(
        _ session: VaultSession, at path: String, to newTitle: String
    ) throws -> FileMoveSummary {
        guard !path.isEmpty else {
            throw ConnectorError("serve il percorso della nota", usage: true)
        }
        guard !newTitle.isEmpty else {
            throw ConnectorError("serve il nuovo titolo", usage: true)
        }
        do {
            let outcome = try session.renameNote(at: path, to: newTitle)
            return FileMoveSummary(
                newPath: outcome.newPath,
                applied: !session.isDryRun,
                rewrittenPaths: outcome.rewrittenPaths,
                failures: outcome.failures
            )
        } catch let refusal as NoteFileOperations.OperationError {
            throw ConnectorError("\(refusal)")
        }
    }

    @MainActor
    static func moveNote(
        _ session: VaultSession, at path: String, toFolder folder: String
    ) throws -> FileMoveSummary {
        guard !path.isEmpty else {
            throw ConnectorError("serve il percorso della nota", usage: true)
        }
        do {
            let outcome = try session.moveNote(at: path, toFolder: folder)
            return FileMoveSummary(
                newPath: outcome.newPath,
                applied: !session.isDryRun,
                rewrittenPaths: outcome.rewrittenPaths,
                failures: outcome.failures
            )
        } catch let refusal as NoteFileOperations.OperationError {
            throw ConnectorError("\(refusal)")
        }
    }

    @MainActor
    static func trashNote(_ session: VaultSession, at path: String) throws -> TrashSummary {
        guard !path.isEmpty else {
            throw ConnectorError("serve il percorso della nota", usage: true)
        }
        do {
            let orphaned = try session.trashNote(at: path)
            return TrashSummary(path: path, applied: !session.isDryRun, orphaned: orphaned)
        } catch let refusal as NoteFileOperations.OperationError {
            throw ConnectorError("\(refusal)")
        }
    }

    // MARK: Tasks

    @MainActor
    static func addTask(
        _ session: VaultSession, text: String, scheduled: String?, due: String?, note: String?
    ) throws -> WriteSummary {
        guard !text.isEmpty else {
            throw ConnectorError("serve il testo del task", usage: true)
        }

        var draft = VaultSession.TaskDraft(text: text)
        if let scheduled { draft.scheduled = try day(scheduled) }
        if let due { draft.due = try day(due) }
        if let note {
            // The inbox is created on demand; any other note has to exist, because
            // inventing one from a task is how a vault fills with files nobody meant to
            // make (SPEC §7.4).
            guard session.exists(note) else {
                throw ConnectorError("«\(note)» non esiste: un task va in una nota che c'è, o nell'inbox")
            }
            draft.destination = .note(note)
        }

        guard let result = session.captureTask(draft) else {
            throw ConnectorError("non scritto: \(session.problems.last ?? "motivo sconosciuto")")
        }
        return summarise(result, session: session)
    }

    @MainActor
    static func changeTask(
        _ session: VaultSession, matching needle: String, _ request: TaskChangeRequest
    ) throws -> WriteSummary {
        guard !needle.isEmpty else {
            throw ConnectorError("serve il testo del task, oppure percorso:riga", usage: true)
        }
        let target = try task(session, matching: needle)

        let change: VaultSession.TaskChange
        switch request {
        case .done: change = .state(.done)
        case .reopen: change = .state(.open)
        case .reschedule(let to): change = .schedule(to == "none" ? nil : try day(to))
        }

        switch session.apply(change, to: target) {
        case .written(let result):
            return summarise(result, session: session)
        case .stale:
            throw ConnectorError(
                "il task non è più dove risultava: qualcuno ha modificato \(target.sourcePath). Riprova."
            )
        case .unchanged, .failed:
            throw ConnectorError("non scritto: \(session.problems.last ?? "motivo sconosciuto")")
        }
    }

    // MARK: The day

    @MainActor
    static func addTimeBlock(
        _ session: VaultSession, title: String, at time: String, minutes: Int?, on rawDay: String?
    ) throws -> WriteSummary {
        guard !title.isEmpty else {
            throw ConnectorError("serve un titolo per il blocco", usage: true)
        }
        let requested = try minutesFromMidnight(time)

        guard let placed = session.addTimeBlock(
            title: title, on: try day(rawDay), startMinutes: requested, durationMinutes: minutes
        ) else {
            throw ConnectorError("non scritto: \(session.problems.last ?? "nessuno spazio libero")")
        }
        guard let result = placed.write.result else {
            throw ConnectorError("non scritto: \(session.problems.last ?? "motivo sconosciuto")")
        }

        // It moved rather than overlapped, and the caller asked for a different hour:
        // saying so beats letting them find it on the timeline later.
        let moved = placed.block.startMinutes == requested
            ? nil
            : "spostato alle \(placed.block.startText): le \(time) erano occupate"
        return summarise(result, session: session, note: moved)
    }

    // MARK: The journal

    /// Puts a file, or a whole gesture, back the way a journalled write found it - one word,
    /// two behaviours, because the person typing an id is asking the same question either way
    /// (ADR-0016 §D5).
    ///
    /// An id that names an operation in the journal is a gesture: refuses the whole thing,
    /// naming every reason, if any single member has moved on since. An id that does not is
    /// a single entry, and this is the exact behaviour `undo` had before ADR-0016 - refuses
    /// when the file has moved on since, because undoing onto somebody else's later edit is
    /// worse than declining to undo at all.
    @MainActor
    static func undo(_ session: VaultSession, id: String) throws -> UndoOutcome {
        let journal = WriteJournal(root: session.root)
        guard journal.entries(operation: id).isEmpty else {
            let outcome = session.undo(operation: id)
            guard outcome.failures.isEmpty else {
                throw ConnectorError(outcome.failures.joined(separator: "\n"))
            }
            return .operation(OperationUndoSummary(operation: id, changed: outcome.changed))
        }

        guard let entry = journal.entry(id: id) else {
            throw ConnectorError("nessuna scrittura con id \(id)")
        }
        guard let current = try? session.read(entry.path) else {
            throw ConnectorError("«\(entry.path)» non c'è più: non ripristino su un file assente")
        }
        guard current.record.contentHash == entry.hashAfter else {
            throw ConnectorError(
                """
                «\(entry.path)» è cambiato dopo quella scrittura: non lo tocco. \
                Il journal ripristina solo ciò che ha scritto lui.
                """
            )
        }
        guard let textBefore = entry.textBefore else {
            throw ConnectorError(
                """
                quella scrittura ha creato «\(entry.path)»: annullarla vuol dire \
                cancellare il file, e questo comando non cancella. Rimuovilo a mano.
                """
            )
        }

        return .single(summarise(try session.write(textBefore, to: entry.path), session: session))
    }

    /// The journal read straight off disk: no session, because listing what was written
    /// does not need the vault scanned to answer.
    static func journalLog(at root: URL, limit: Int?) -> [JournalRow] {
        WriteJournal(root: root).entries().suffix(limit ?? 20).map(JournalRow.init)
    }
}
