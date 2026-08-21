import Foundation

/// The commands that change a file: `note new`, `note append`, `note rename|move|trash`,
/// and the task and block writes. Every one of them accepts `--dry-run` and every one of
/// them is journalled.
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

    // MARK: note rename / move / trash (ADR-0016)

    @MainActor
    static func noteRename(_ arguments: Arguments) async throws -> ExitCode {
        let path = try NoteCommands.requirePath(arguments, "note rename <percorso> <nuovo-titolo>")
        let session = try await Writing.session(arguments, command: "note rename")
        let summary = try VaultAPI.renameNote(session, at: path, to: arguments.rest(from: 3))
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    @MainActor
    static func noteMove(_ arguments: Arguments) async throws -> ExitCode {
        let path = try NoteCommands.requirePath(arguments, "note move <percorso> <cartella>")
        let session = try await Writing.session(arguments, command: "note move")
        let summary = try VaultAPI.moveNote(session, at: path, toFolder: arguments.rest(from: 3))
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    @MainActor
    static func noteTrash(_ arguments: Arguments) async throws -> ExitCode {
        let path = try NoteCommands.requirePath(arguments, "note trash <percorso>")
        let session = try await Writing.session(arguments, command: "note trash")
        let summary = try VaultAPI.trashNote(session, at: path)
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    // MARK: capture

    /// `perg capture <testo> [--dest note|task|today|note:PERCORSO]`.
    ///
    /// The default is `note` and not the URL route's `today`: a shell command with no
    /// destination is a note being written, while `pergamenum://capture?text=…` has
    /// meant "append to today" since SPEC §9 published it. The two differ on purpose
    /// and `CaptureDestination.named` carries no default of its own so that neither can
    /// drift into the other.
    @MainActor
    static func capture(_ arguments: Arguments) async throws -> ExitCode {
        let session = try await Writing.session(arguments, command: "capture")
        let destination = try VaultAPI.CaptureDestination.named(
            arguments["dest"] ?? "note", folder: arguments["folder"]
        )
        let summary = try VaultAPI.capture(
            session,
            to: destination,
            text: arguments.rest(from: 1),
            scheduled: arguments["scheduled"],
            due: arguments["due"]
        )
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
