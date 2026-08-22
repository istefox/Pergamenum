import Foundation

/// `perg day show [data]` - a day as the vault has it.
///
/// Blocks, scheduled tasks and what is due, from the daily note and the index. No
/// EventKit: Apple Calendar stays with the app (ADR-0007 §D4), so this is the day as
/// written down rather than the day as the machine knows it.
enum DayCommands {
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
        let session = try await VaultResolution.session(at: try VaultResolution.root(from: arguments))
        // The date may come as the word after `show` or as `--day`, because both read
        // naturally: `perg day show 2026-08-18` and `perg day show --day 2026-08-18`.
        let day = try VaultAPI.day(session, on: arguments.word(2) ?? arguments["day"])

        if arguments.has("json") {
            Output.json(day)
            return .success
        }

        Output.line("\(day.date)  \(day.notePath)\(day.noteExists ? "" : "  (la nota non esiste)")")
        if !day.blocks.isEmpty {
            Output.line("  blocchi")
            for block in day.blocks {
                Output.line("    \(block.start)-\(block.end)  \(block.title)")
            }
        }
        if !day.scheduled.isEmpty {
            Output.line("  in programma")
            for task in day.scheduled { Output.line("    \(task.text)") }
        }
        if !day.due.isEmpty {
            Output.line("  in scadenza")
            for task in day.due { Output.line("    \(task.text)") }
        }
        if day.blocks.isEmpty, day.scheduled.isEmpty, day.due.isEmpty {
            Output.line("  niente")
        }
        return .success
    }
}
