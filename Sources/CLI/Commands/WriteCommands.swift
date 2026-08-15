import Foundation

/// The commands that change a file: `note new`, `note append`, and the task and block
/// writes. Every one of them accepts `--dry-run` and every one of them is journalled.
///
/// `note rename`, `move` and `trash` are deliberately not here yet. They rewrite links
/// across many notes through `NoteFileOperations`, which does not go through
/// `VaultSession.write` - so neither the journal nor the diff would see the whole of
/// what they did, and a guardrail that covers part of a change is worse than one that
/// admits it is absent.
enum WriteCommands {
    // MARK: note new / append

    @MainActor
    static func noteNew(_ arguments: Arguments) async throws -> ExitCode {
        let title = arguments.rest(from: 2)
        guard !title.isEmpty else {
            throw CommandError("uso: perg note new <titolo> [--folder <cartella>] [--topic <tag>]", code: .usage)
        }

        let session = try await Writing.session(arguments, command: "note new")
        let topics = try (arguments["topic"].map { raw -> [Tag] in
            guard let tag = Tag(raw) else { throw CommandError("«\(raw)» non è un tag valido", code: .usage) }
            return [tag]
        } ?? [])

        let date = try TaskCommands.resolveDay(arguments["date"])
        let result = try session.createNote(
            title: title, in: arguments["folder"] ?? "", date: date, topics: topics
        )
        Writing.report(result, session: session, arguments: arguments)
        return Writing.finish(session)
    }

    @MainActor
    static func noteAppend(_ arguments: Arguments) async throws -> ExitCode {
        let path = try NoteCommands.requirePath(arguments, "note append <percorso> <testo>")
        let text = arguments.rest(from: 3)
        guard !text.isEmpty else {
            throw CommandError("uso: perg note append <percorso> <testo>", code: .usage)
        }

        let session = try await Writing.session(arguments, command: "note append")
        guard session.exists(path) else { throw CommandError("«\(path)» non esiste") }

        guard case .written(let result) = session.append(text: text, to: path) else {
            throw CommandError("non scritto: \(session.problems.last ?? "motivo sconosciuto")")
        }
        Writing.report(result, session: session, arguments: arguments)
        return Writing.finish(session)
    }

    // MARK: task

    @MainActor
    static func taskAdd(_ arguments: Arguments) async throws -> ExitCode {
        let text = arguments.rest(from: 2)
        guard !text.isEmpty else {
            throw CommandError(
                "uso: perg task add <testo> [--scheduled <data>] [--due <data>] [--note <percorso>]",
                code: .usage
            )
        }

        let session = try await Writing.session(arguments, command: "task add")
        var draft = VaultSession.TaskDraft(text: text)
        if let raw = arguments["scheduled"] { draft.scheduled = try TaskCommands.resolveDay(raw) }
        if let raw = arguments["due"] { draft.due = try TaskCommands.resolveDay(raw) }
        if let note = arguments["note"] {
            guard session.exists(note) else {
                // The inbox is created on demand; any other note has to exist, because
                // inventing one from a task is how a vault fills with files nobody
                // meant to make (SPEC §7.4).
                throw CommandError("«\(note)» non esiste: un task va in una nota che c'è, o nell'inbox")
            }
            draft.destination = .note(note)
        }

        guard let result = session.captureTask(draft) else {
            throw CommandError("non scritto: \(session.problems.last ?? "motivo sconosciuto")")
        }
        Writing.report(result, session: session, arguments: arguments)
        return Writing.finish(session)
    }

    @MainActor
    static func taskChange(_ arguments: Arguments, _ change: TaskChangeKind) async throws -> ExitCode {
        let needle = arguments.rest(from: 2)
        guard !needle.isEmpty else {
            throw CommandError("uso: perg task \(change.verb) <testo del task o percorso:riga>", code: .usage)
        }

        let session = try await Writing.session(arguments, command: "task \(change.verb)")
        let task = try resolveTask(session, needle)

        let sessionChange: VaultSession.TaskChange
        switch change {
        case .done: sessionChange = .state(.done)
        case .reopen: sessionChange = .state(.open)
        case .reschedule:
            guard let raw = arguments["to"] else {
                throw CommandError("uso: perg task reschedule <task> --to <data|none>", code: .usage)
            }
            sessionChange = .schedule(raw == "none" ? nil : try TaskCommands.resolveDay(raw))
        }

        switch session.apply(sessionChange, to: task) {
        case .written(let result):
            Writing.report(result, session: session, arguments: arguments)
            return Writing.finish(session)
        case .stale:
            throw CommandError(
                "il task non è più dove risultava: qualcuno ha modificato \(task.sourcePath). Riprova."
            )
        case .unchanged, .failed:
            throw CommandError("non scritto: \(session.problems.last ?? "motivo sconosciuto")")
        }
    }

    enum TaskChangeKind {
        case done, reopen, reschedule

        var verb: String {
            switch self {
            case .done: "done"
            case .reopen: "reopen"
            case .reschedule: "reschedule"
            }
        }
    }

    /// Finds the one task a phrase names, and refuses when it names several.
    ///
    /// `percorso:riga` is exact; anything else is matched against the task's text.
    /// Ambiguity is an error rather than a first match: completing the wrong task is
    /// silent, and the user would find out much later.
    @MainActor
    private static func resolveTask(_ session: VaultSession, _ needle: String) throws -> TaskItem {
        let tasks = session.index.allTasks

        if let colon = needle.lastIndex(of: ":"), let line = Int(needle[needle.index(after: colon)...]) {
            let path = String(needle[needle.startIndex..<colon])
            guard let task = tasks.first(where: { $0.sourcePath == path && $0.lineIndex + 1 == line }) else {
                throw CommandError("nessun task a \(path):\(line)")
            }
            return task
        }

        let matches = tasks.filter { $0.text.localizedCaseInsensitiveContains(needle) }
        switch matches.count {
        case 0: throw CommandError("nessun task contiene «\(needle)»")
        case 1: return matches[0]
        default:
            let list = matches.prefix(5)
                .map { "  \($0.sourcePath):\($0.lineIndex + 1)  \($0.text)" }
                .joined(separator: "\n")
            throw CommandError(
                "«\(needle)» corrisponde a \(matches.count) task; indica percorso:riga\n\(list)",
                code: .usage
            )
        }
    }

    // MARK: day block

    @MainActor
    static func blockAdd(_ arguments: Arguments) async throws -> ExitCode {
        guard let time = arguments["at"] else {
            throw CommandError("uso: perg day block add <titolo> --at HH:MM [--minutes n] [--day <data>]", code: .usage)
        }
        let title = arguments.rest(from: 3)
        guard !title.isEmpty else {
            throw CommandError("uso: perg day block add <titolo> --at HH:MM", code: .usage)
        }
        guard let minutes = minutesFromMidnight(time) else {
            throw CommandError("«\(time)» non è un orario (HH:MM)", code: .usage)
        }

        let session = try await Writing.session(arguments, command: "day block add")
        let day = try TaskCommands.resolveDay(arguments["day"])
        let duration = arguments["minutes"].flatMap(Int.init)

        guard let placed = session.addTimeBlock(
            title: title, on: day, startMinutes: minutes, durationMinutes: duration
        ) else {
            throw CommandError("non scritto: \(session.problems.last ?? "nessuno spazio libero")")
        }

        if placed.block.startMinutes != minutes, !arguments.has("json") {
            // It moved rather than overlapped, and the user asked for a different hour:
            // saying so beats letting them find it on the timeline later.
            Output.line("spostato alle \(placed.block.startText): le \(time) erano occupate")
        }
        if let result = placed.write.result {
            Writing.report(result, session: session, arguments: arguments)
        }
        return Writing.finish(session)
    }

    private static func minutesFromMidnight(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }
}
