import Foundation

/// `perg day show [data]` - a day as the vault has it.
///
/// Blocks, scheduled tasks and what is due, from the daily note and the index. No
/// EventKit: Apple Calendar stays with the app (ADR-0007 §D4), so this is the day as
/// written down rather than the day as the machine knows it.
enum DayCommands {
    struct Block: Encodable {
        let start: String
        let end: String
        let title: String
        let published: Bool
    }

    struct Day: Encodable {
        let date: String
        let notePath: String
        let noteExists: Bool
        let blocks: [Block]
        let scheduled: [TaskCommands.Item]
        let due: [TaskCommands.Item]
    }

    @MainActor
    static func run(_ arguments: Arguments) async throws -> ExitCode {
        switch arguments.word(1) {
        case "show", nil: return try await show(arguments)
        case let other?:
            throw CommandError("«day \(other)» non esiste; c'è «day show»", code: .usage)
        }
    }

    @MainActor
    private static func show(_ arguments: Arguments) async throws -> ExitCode {
        let session = await VaultResolution.session(at: try VaultResolution.root(from: arguments))
        // The date may come as the word after `show` or as `--day`, because both read
        // naturally: `perg day show 2026-08-18` and `perg day show --day 2026-08-18`.
        let day = try TaskCommands.resolveDay(arguments.word(2) ?? arguments["day"])

        let path = session.dailyNotePath(for: day)
        let blocks = session.timeBlocks(on: day).map {
            Block(start: $0.startText, end: $0.endText, title: $0.title, published: $0.isPublished)
        }
        let scheduled = session.index.allTasks.filter { $0.isScheduled(on: day) }
        let due = session.index.allTasks.filter(\.state.isOpen).filter { $0.due == day }

        if arguments.has("json") {
            Output.json(Day(
                date: day.description,
                notePath: path,
                noteExists: session.exists(path),
                blocks: blocks,
                scheduled: scheduled.map(TaskCommands.item),
                due: due.map(TaskCommands.item)
            ))
        } else {
            Output.line("\(day)  \(path)\(session.exists(path) ? "" : "  (la nota non esiste)")")
            if !blocks.isEmpty {
                Output.line("  blocchi")
                for block in blocks {
                    Output.line("    \(block.start)-\(block.end)  \(block.title)")
                }
            }
            if !scheduled.isEmpty {
                Output.line("  in programma")
                for task in scheduled { Output.line("    \(task.text)") }
            }
            if !due.isEmpty {
                Output.line("  in scadenza")
                for task in due { Output.line("    \(task.text)") }
            }
            if blocks.isEmpty, scheduled.isEmpty, due.isEmpty {
                Output.line("  niente")
            }
        }
        return .success
    }
}
