import Foundation

/// `perg task …` - the tasks of SPEC §7, which are markdown lines and nothing else.
enum TaskCommands {
    struct Item: Encodable {
        let id: String
        let text: String
        let state: String
        let path: String
        let line: Int
        let scheduled: String?
        let due: String?
        let project: String?
        let links: [String]
    }

    @MainActor
    static func run(_ arguments: Arguments) async throws -> ExitCode {
        switch arguments.word(1) {
        case "list", nil: return try await list(arguments)
        case let other?:
            throw CommandError("«task \(other)» non esiste; c'è «task list»", code: .usage)
        }
    }

    @MainActor
    private static func list(_ arguments: Arguments) async throws -> ExitCode {
        let session = await VaultResolution.session(at: try VaultResolution.root(from: arguments))
        let day = try resolveDay(arguments["day"])

        // The five views of SPEC §7.4, named as the sidebar names them.
        let view: IndexSnapshot.TaskView
        switch arguments["view"] ?? "all" {
        case "inbox": view = .inbox
        case "today", "oggi": view = .today
        case "upcoming", "prossimi": view = .upcoming
        case "by-project", "progetto": view = .byProject
        case "all", "tutti": view = .all
        case let other:
            throw CommandError(
                "«\(other)» non è una vista; ci sono inbox, today, upcoming, by-project, all",
                code: .usage
            )
        }

        let tasks = session.index.tasks(
            for: view, on: day, includingCompleted: arguments.has("completed")
        )

        if arguments.has("json") {
            Output.json(tasks.map(item))
        } else {
            for task in tasks {
                let marker = task.state == .done ? "x" : " "
                var line = "- [\(marker)] \(task.text)"
                if let scheduled = task.scheduled { line += "  >\(scheduled)" }
                if let due = task.due { line += "  !\(due)" }
                Output.line(line)
                Output.line("      \(task.sourcePath):\(task.lineIndex + 1)")
            }
        }
        return .success
    }

    static func item(_ task: TaskItem) -> Item {
        Item(
            id: task.id,
            text: task.text,
            state: String(task.state.marker),
            path: task.sourcePath,
            line: task.lineIndex + 1,
            scheduled: task.scheduled?.description,
            due: task.due?.description,
            project: task.project?.description,
            links: task.links
        )
    }

    /// `--day` as an ISO date, defaulting to today.
    ///
    /// `CalendarDate.today` is `Calendar.current`, so this agrees with what the app
    /// would show at the same moment on the same machine.
    static func resolveDay(_ raw: String?) throws -> CalendarDate {
        guard let raw else { return .today }
        guard let date = CalendarDate(iso: raw) ?? CalendarDate(compact: raw) else {
            throw CommandError("«\(raw)» non è una data (YYYY-MM-DD o YYYYMMDD)", code: .usage)
        }
        return date
    }
}
