import Foundation

/// `perg task …` - the tasks of SPEC §7, which are markdown lines and nothing else.
enum TaskCommands {
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
        let session = try await VaultResolution.session(at: try VaultResolution.root(from: arguments))
        let tasks = try VaultAPI.tasks(
            session,
            view: arguments["view"],
            on: arguments["day"],
            includingCompleted: arguments.has("completed")
        )

        if arguments.has("json") {
            Output.json(tasks)
        } else {
            for task in tasks {
                var line = "- [\(task.state)] \(task.text)"
                if let scheduled = task.scheduled { line += "  >\(scheduled)" }
                if let due = task.due { line += "  !\(due)" }
                Output.line(line)
                Output.line("      \(task.path):\(task.line)")
            }
        }
        return .success
    }
}
