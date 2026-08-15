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
        let session = try await Writing.session(arguments, command: "note new")
        let summary = try VaultAPI.createNote(
            session,
            title: arguments.rest(from: 2),
            folder: arguments["folder"],
            topic: arguments["topic"],
            date: arguments["date"]
        )
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    @MainActor
    static func noteAppend(_ arguments: Arguments) async throws -> ExitCode {
        let path = try NoteCommands.requirePath(arguments, "note append <percorso> <testo>")
        let session = try await Writing.session(arguments, command: "note append")
        let summary = try VaultAPI.appendToNote(session, at: path, text: arguments.rest(from: 3))
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    // MARK: task

    @MainActor
    static func taskAdd(_ arguments: Arguments) async throws -> ExitCode {
        let session = try await Writing.session(arguments, command: "task add")
        let summary = try VaultAPI.addTask(
            session,
            text: arguments.rest(from: 2),
            scheduled: arguments["scheduled"],
            due: arguments["due"],
            note: arguments["note"]
        )
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    @MainActor
    static func taskChange(
        _ arguments: Arguments, _ change: VaultAPI.TaskChangeRequest
    ) async throws -> ExitCode {
        let session = try await Writing.session(arguments, command: "task \(change.verb)")
        let summary = try VaultAPI.changeTask(session, matching: arguments.rest(from: 2), change)
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    /// `--to` is read here rather than inside the request because a missing one is a
    /// fact about the command line, not about the vault.
    static func rescheduleRequest(_ arguments: Arguments) throws -> VaultAPI.TaskChangeRequest {
        guard let to = arguments["to"] else {
            throw CommandError("uso: perg task reschedule <task> --to <data|none>", code: .usage)
        }
        return .reschedule(to: to)
    }

    // MARK: day block

    @MainActor
    static func blockAdd(_ arguments: Arguments) async throws -> ExitCode {
        guard let time = arguments["at"] else {
            throw CommandError(
                "uso: perg day block add <titolo> --at HH:MM [--minutes n] [--day <data>]",
                code: .usage
            )
        }
        let session = try await Writing.session(arguments, command: "day block add")
        let summary = try VaultAPI.addTimeBlock(
            session,
            title: arguments.rest(from: 3),
            at: time,
            minutes: arguments["minutes"].flatMap(Int.init),
            on: arguments["day"]
        )
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }
}
