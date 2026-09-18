import Foundation

/// The commands that change a file: `note new`, `note append`, `note rename|move|trash`,
/// and the task and block writes. Every one of them accepts `--dry-run` and every one of
/// them is journalled.
enum WriteCommands {
    // MARK: note new / append

    @MainActor
    static func noteNew(_ arguments: Arguments) async throws -> ExitCode {
        let session = try await Writing.session(arguments, command: "note new")
        let summary = try await VaultAPI.createNote(
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
        let summary = try await VaultAPI.appendToNote(session, at: path, text: arguments.rest(from: 3))
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    // MARK: note rename / move / trash (ADR-0016)

    @MainActor
    static func noteRename(_ arguments: Arguments) async throws -> ExitCode {
        let path = try NoteCommands.requirePath(arguments, "note rename <percorso> <nuovo-titolo>")
        let session = try await Writing.session(arguments, command: "note rename")
        let summary = try await VaultAPI.renameNote(session, at: path, to: arguments.rest(from: 3))
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    @MainActor
    static func noteMove(_ arguments: Arguments) async throws -> ExitCode {
        let path = try NoteCommands.requirePath(arguments, "note move <percorso> <cartella>")
        let session = try await Writing.session(arguments, command: "note move")
        let summary = try await VaultAPI.moveNote(session, at: path, toFolder: arguments.rest(from: 3))
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    @MainActor
    static func noteTrash(_ arguments: Arguments) async throws -> ExitCode {
        let path = try NoteCommands.requirePath(arguments, "note trash <percorso>")
        let session = try await Writing.session(arguments, command: "note trash")
        let summary = try await VaultAPI.trashNote(session, at: path)
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
        let summary = try await VaultAPI.capture(
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
        let summary = try await VaultAPI.addTask(
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
        let summary = try await VaultAPI.changeTask(session, matching: arguments.rest(from: 2), change)
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
        let summary = try await VaultAPI.addTimeBlock(
            session,
            title: arguments.rest(from: 3),
            at: time,
            minutes: arguments["minutes"].flatMap(Int.init),
            on: arguments["day"]
        )
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    // MARK: pratica links (ADR-0049 §D12, R-01, R-03)

    @MainActor
    static func praticaLinkNote(_ arguments: Arguments) async throws -> ExitCode {
        let reference = try PraticheCommands.requireReference(arguments, "pratica link-note <pratica> <titolo>")
        let session = try await Writing.session(arguments, command: "pratica link-note")
        let summary = try await VaultAPI.linkPraticaNote(session, pratica: reference, title: arguments.rest(from: 3))
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    @MainActor
    static func praticaUnlinkNote(_ arguments: Arguments) async throws -> ExitCode {
        let reference = try PraticheCommands.requireReference(arguments, "pratica unlink-note <pratica> <titolo>")
        let session = try await Writing.session(arguments, command: "pratica unlink-note")
        let summary = try await VaultAPI.unlinkPraticaNote(session, pratica: reference, title: arguments.rest(from: 3))
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    @MainActor
    static func praticaLinkBoard(_ arguments: Arguments) async throws -> ExitCode {
        let reference = try PraticheCommands.requireReference(arguments, "pratica link-board <pratica> <board>")
        let session = try await Writing.session(arguments, command: "pratica link-board")
        let summary = try await VaultAPI.linkPraticaBoard(session, pratica: reference, board: arguments.rest(from: 3))
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    @MainActor
    static func praticaUnlinkBoard(_ arguments: Arguments) async throws -> ExitCode {
        let reference = try PraticheCommands.requireReference(arguments, "pratica unlink-board <pratica> <board>")
        let session = try await Writing.session(arguments, command: "pratica unlink-board")
        let summary = try await VaultAPI.unlinkPraticaBoard(
            session, pratica: reference, board: arguments.rest(from: 3)
        )
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    @MainActor
    static func praticaLinkTask(_ arguments: Arguments) async throws -> ExitCode {
        let reference = try PraticheCommands.requireReference(arguments, "pratica link-task <pratica> <task>")
        let session = try await Writing.session(arguments, command: "pratica link-task")
        let summary = try await VaultAPI.linkPraticaTask(session, pratica: reference, task: arguments.rest(from: 3))
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    @MainActor
    static func praticaUnlinkTask(_ arguments: Arguments) async throws -> ExitCode {
        let reference = try PraticheCommands.requireReference(arguments, "pratica unlink-task <pratica> <task>")
        let session = try await Writing.session(arguments, command: "pratica unlink-task")
        let summary = try await VaultAPI.unlinkPraticaTask(session, pratica: reference, task: arguments.rest(from: 3))
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    // MARK: pratica create-and-link (R-03)

    @MainActor
    static func praticaCreateNote(_ arguments: Arguments) async throws -> ExitCode {
        let reference = try PraticheCommands.requireReference(arguments, "pratica create-note <pratica> <titolo>")
        let session = try await Writing.session(arguments, command: "pratica create-note")
        let summary = try await VaultAPI.createAndLinkPraticaNote(
            session, pratica: reference, title: arguments.rest(from: 3), folder: arguments["folder"]
        )
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    @MainActor
    static func praticaCreateTask(_ arguments: Arguments) async throws -> ExitCode {
        let reference = try PraticheCommands.requireReference(arguments, "pratica create-task <pratica> <testo>")
        let session = try await Writing.session(arguments, command: "pratica create-task")
        let summary = try await VaultAPI.createAndLinkPraticaTask(
            session, pratica: reference, text: arguments.rest(from: 3)
        )
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    @MainActor
    static func praticaCreateBoard(_ arguments: Arguments) async throws -> ExitCode {
        let reference = try PraticheCommands.requireReference(arguments, "pratica create-board <pratica> <nome>")
        let session = try await Writing.session(arguments, command: "pratica create-board")
        let summary = try await VaultAPI.createAndLinkPraticaBoard(
            session, pratica: reference, name: arguments.rest(from: 3), folder: arguments["folder"]
        )
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    // MARK: message link (R-02, R-03, §D6)

    @MainActor
    static func messageLinkNote(_ arguments: Arguments) async throws -> ExitCode {
        let path = try PraticheCommands.requireMessagePath(arguments, "message link-note <percorso> <titolo>")
        let session = try await Writing.session(arguments, command: "message link-note")
        let summary = try await VaultAPI.linkMessageNote(session, message: path, title: arguments.rest(from: 3))
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    @MainActor
    static func messageUnlinkNote(_ arguments: Arguments) async throws -> ExitCode {
        let path = try PraticheCommands.requireMessagePath(arguments, "message unlink-note <percorso>")
        let session = try await Writing.session(arguments, command: "message unlink-note")
        let summary = try await VaultAPI.unlinkMessageNote(session, message: path)
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }

    @MainActor
    static func messageCreateNote(_ arguments: Arguments) async throws -> ExitCode {
        let path = try PraticheCommands.requireMessagePath(arguments, "message create-note <percorso> <titolo>")
        let session = try await Writing.session(arguments, command: "message create-note")
        let summary = try await VaultAPI.createAndLinkMessageNote(
            session, message: path, title: arguments.rest(from: 3)
        )
        Writing.report(summary, arguments: arguments)
        return Writing.finish(session)
    }
}
