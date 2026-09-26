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
        session.journal = dryRun ? nil : session.journalOnDisk
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
    ) async throws -> WriteSummary {
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
            let result = try await session.createNote(
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
    ) async throws -> WriteSummary {
        guard !text.isEmpty else {
            throw ConnectorError("serve il testo da aggiungere", usage: true)
        }
        guard session.exists(path) else { throw ConnectorError("«\(path)» non esiste") }

        switch await session.append(text: text, to: path) {
        case .written(let result):
            return summarise(result, session: session)
        case .stale:
            // A refusal records no problem (the file is intact), so `problems.last` would
            // name somebody else's failure: the refusal says its own sentence.
            throw ConnectorError("non scritto: \(VaultWriteRefusal.movedOn(path).description)")
        case .unchanged, .failed:
            throw ConnectorError("non scritto: \(session.problems.last ?? "motivo sconosciuto")")
        }
    }

    // MARK: Renaming, moving, trashing (ADR-0016)

    /// Where a rename or a move's refusals become part of `failures` rather than a new JSON
    /// key (ADR-0046 §D4): `FileMoveSummary` is the wire shape both connectors answer with,
    /// and the distinct channel the ADR asks for lives in Swift, not on the wire. One function
    /// for both `renameNote` and `moveNote` below, so the sentence cannot drift between the
    /// two - and one seam `Tests/ConnectorTests.swift` can call directly with a hand-built
    /// `NoteFileOperations.Outcome`, since a genuine refusal cannot be forced deterministically
    /// through either async call above (ADR-0046 §D11, same constraint Task 4's tests name).
    static func foldedFailures(_ outcome: NoteFileOperations.Outcome) -> [String] {
        outcome.failures + outcome.refusals.map { VaultWriteRefusal.movedOn($0).description }
    }

    @MainActor
    static func renameNote(
        _ session: VaultSession, at path: String, to newTitle: String
    ) async throws -> FileMoveSummary {
        guard !path.isEmpty else {
            throw ConnectorError("serve il percorso della nota", usage: true)
        }
        guard !newTitle.isEmpty else {
            throw ConnectorError("serve il nuovo titolo", usage: true)
        }
        do {
            let outcome = try await session.renameNote(at: path, to: newTitle)
            return FileMoveSummary(
                newPath: outcome.newPath,
                applied: !session.isDryRun,
                rewrittenPaths: outcome.rewrittenPaths,
                failures: foldedFailures(outcome)
            )
        } catch let refusal as FileOperationError {
            throw ConnectorError("\(refusal)")
        }
    }

    @MainActor
    static func moveNote(
        _ session: VaultSession, at path: String, toFolder folder: String
    ) async throws -> FileMoveSummary {
        guard !path.isEmpty else {
            throw ConnectorError("serve il percorso della nota", usage: true)
        }
        do {
            let outcome = try await session.moveNote(at: path, toFolder: folder)
            return FileMoveSummary(
                newPath: outcome.newPath,
                applied: !session.isDryRun,
                rewrittenPaths: outcome.rewrittenPaths,
                failures: foldedFailures(outcome)
            )
        } catch let refusal as FileOperationError {
            throw ConnectorError("\(refusal)")
        }
    }

    @MainActor
    static func trashNote(_ session: VaultSession, at path: String) async throws -> TrashSummary {
        guard !path.isEmpty else {
            throw ConnectorError("serve il percorso della nota", usage: true)
        }
        do {
            let orphaned = try await session.trashNote(at: path)
            return TrashSummary(path: path, applied: !session.isDryRun, orphaned: orphaned)
        } catch let refusal as FileOperationError {
            throw ConnectorError("\(refusal)")
        }
    }

    // MARK: Tasks

    @MainActor
    static func addTask(
        _ session: VaultSession, text: String, scheduled: String?, due: String?, note: String?
    ) async throws -> WriteSummary {
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

        guard let result = await session.captureTask(draft) else {
            throw ConnectorError("non scritto: \(session.problems.last ?? "motivo sconosciuto")")
        }
        return summarise(result, session: session)
    }

    @MainActor
    static func changeTask(
        _ session: VaultSession, matching needle: String, _ request: TaskChangeRequest
    ) async throws -> WriteSummary {
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

        switch await session.apply(change, to: target) {
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
    ) async throws -> WriteSummary {
        guard !title.isEmpty else {
            throw ConnectorError("serve un titolo per il blocco", usage: true)
        }
        let requested = try minutesFromMidnight(time)

        guard let placed = await session.addTimeBlock(
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
    /// ADR-0041 Task 9 (R-08) made this the first `async` function in this file, because it
    /// was the only one calling `session.write(_:to:)` directly instead of through one of
    /// `VaultSession`'s then-synchronous wrappers. ADR-0043 §D2 deleted that synchronous
    /// door, so every wrapper this file calls - `createNote`, `append`, `renameNote`,
    /// `moveNote`, `trashNote`, `captureTask`, `apply`, `addTimeBlock`, `undo` - is `async`
    /// now, and so is every function here. The cost ADR-0041 declined to pay (an `await` at
    /// every CLI, MCP and test call site) is what this chain paid on purpose: one write
    /// door, no second ordering regime beside it.
    @MainActor
    static func undo(_ session: VaultSession, id: String) async throws -> UndoOutcome {
        let journal = session.journalOnDisk
        guard journal.entries(operation: id).isEmpty else {
            let outcome = await session.undo(operation: id)
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

        // `expecting:` (ADR-0043 §D8, Task 9) is the backstop for the window the
        // pre-check above cannot cover - between that read and this write. The pre-check
        // stays: its Italian message is the one the user should see for the common case,
        // and a refusal here reports the same sentence rather than a different one.
        do {
            let result = try await session.write(textBefore, to: entry.path, expecting: entry.hashAfter)
            return .single(summarise(result, session: session))
        } catch is VaultSession.WriteRefusal {
            throw ConnectorError(
                """
                «\(entry.path)» è cambiato dopo quella scrittura: non lo tocco. \
                Il journal ripristina solo ciò che ha scritto lui.
                """
            )
        }
    }

    /// The journal read straight off disk: no session, because listing what was written
    /// does not need the vault scanned to answer.
    ///
    /// `base` and `throws` are new with ADR-0017: the journal moved beside the vault,
    /// so finding it needs the state directory `VaultState.resolve(root:base:)` reads
    /// out of `settings.json`, and a vault this process has never opened has no id to
    /// resolve. Reported rather than minting one from a read-only log command, which is
    /// as far as this call site goes for now - wiring `base` in from the two callers'
    /// own `VaultState.applicationSupportBase()` is slice 3.
    ///
    /// The limit is checked first (ADR-0063 §D1.1): a negative one reached
    /// `suffix(_:)`, which traps, and the caller's mistake outranks «vault mai aperto».
    static func journalLog(at root: URL, base: URL, limit: Int?) throws -> [JournalRow] {
        let limit = try checkedLimit(limit)
        guard let state = VaultState.resolve(root: root, base: base) else {
            throw ConnectorError("vault mai aperto: nessun journal da leggere")
        }
        return WriteJournal(directory: state.journal).entries().suffix(limit ?? 20).map(JournalRow.init)
    }
}
