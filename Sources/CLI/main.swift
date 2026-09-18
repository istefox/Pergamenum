import Foundation

/// `perg`, the vault from a shell (ADR-0007 §D1).
///
/// Top-level code in `main.swift`, which Swift 6 runs on the main actor - which is what
/// `VaultSession` is isolated to. That is not a coincidence to be grateful for: the
/// session is `@MainActor` because the app's views read its state synchronously, and a
/// command-line tool inherits the same isolation for free by starting here.

/// Which group of commands answers, kept apart from `run` so that adding one does not
/// push the entry point's branching over what SwiftLint allows.
func dispatch(_ group: String, _ arguments: Arguments) async throws -> ExitCode {
    switch group {
    case "note": return try await noteGroup(arguments)
    case "task": return try await taskGroup(arguments)
    case "categories": return try await CategoryCommands.categories(arguments)
    case "category-tasks": return try await CategoryCommands.categoryTasks(arguments)
    case "day": return try await dayGroup(arguments)
    case "capture": return try await WriteCommands.capture(arguments)
    case "search": return try await SearchCommands.run(arguments)
    case "lint": return try await LintCommands.run(arguments)
    case "index": return try await IndexCommands.run(arguments)
    case "view": return try await ViewCommands.run(arguments)
    case "journal": return try await JournalCommands.run(arguments)
    case "app": return try await AppCommands.run(arguments)
    // Two groups rather than `pratiche list`/`pratiche show`: the plural lists and the
    // singular takes a name, which is how a person says it out loud (SPEC "Connectors":
    // `pratiche` and `pratica <title|path>`).
    case "pratiche": return try await PraticheCommands.list(arguments)
    case "pratica": return try await praticaGroup(arguments)
    case "message": return try await messageGroup(arguments)
    case "help":
        Output.line(Help.text)
        return .success
    default:
        throw CommandError("«\(group)» non è un gruppo di comandi; prova «perg help»", code: .usage)
    }
}

/// Each group splits its writing subcommands from its reading ones here rather than
/// inside one switch: nested, the entry point's branching outgrew what SwiftLint allows
/// and, more to the point, what a reader can follow.
func noteGroup(_ arguments: Arguments) async throws -> ExitCode {
    switch arguments.word(1) {
    case "new": return try await WriteCommands.noteNew(arguments)
    case "append": return try await WriteCommands.noteAppend(arguments)
    case "rename": return try await WriteCommands.noteRename(arguments)
    case "move": return try await WriteCommands.noteMove(arguments)
    case "trash": return try await WriteCommands.noteTrash(arguments)
    default: return try await NoteCommands.run(arguments)
    }
}

func taskGroup(_ arguments: Arguments) async throws -> ExitCode {
    switch arguments.word(1) {
    case "add": return try await WriteCommands.taskAdd(arguments)
    case "done": return try await WriteCommands.taskChange(arguments, .done)
    case "reopen": return try await WriteCommands.taskChange(arguments, .reopen)
    case "reschedule":
        return try await WriteCommands.taskChange(
            arguments, try WriteCommands.rescheduleRequest(arguments)
        )
    default: return try await TaskCommands.run(arguments)
    }
}

func dayGroup(_ arguments: Arguments) async throws -> ExitCode {
    if arguments.word(1) == "block", arguments.word(2) == "add" {
        return try await WriteCommands.blockAdd(arguments)
    }
    return try await DayCommands.run(arguments)
}

/// `pratica <riferimento>` shows (unchanged: word(1) is still the reference itself);
/// every other second word is a verb this dispatches instead, shifting the reference
/// to word(2) (ADR-0049 §D12).
func praticaGroup(_ arguments: Arguments) async throws -> ExitCode {
    if arguments.word(1) == "links" { return try await PraticheCommands.links(arguments) }
    if let result = try await praticaLinkVerb(arguments) { return result }
    if let result = try await praticaCreateVerb(arguments) { return result }
    return try await PraticheCommands.show(arguments)
}

/// Split from `praticaGroup` for the reason `main.swift`'s own doc comment gives:
/// one switch over every verb would push past what SwiftLint allows.
func praticaLinkVerb(_ arguments: Arguments) async throws -> ExitCode? {
    switch arguments.word(1) {
    case "link-note": return try await WriteCommands.praticaLinkNote(arguments)
    case "unlink-note": return try await WriteCommands.praticaUnlinkNote(arguments)
    case "link-board": return try await WriteCommands.praticaLinkBoard(arguments)
    case "unlink-board": return try await WriteCommands.praticaUnlinkBoard(arguments)
    case "link-task": return try await WriteCommands.praticaLinkTask(arguments)
    case "unlink-task": return try await WriteCommands.praticaUnlinkTask(arguments)
    default: return nil
    }
}

func praticaCreateVerb(_ arguments: Arguments) async throws -> ExitCode? {
    switch arguments.word(1) {
    case "create-note": return try await WriteCommands.praticaCreateNote(arguments)
    case "create-task": return try await WriteCommands.praticaCreateTask(arguments)
    case "create-board": return try await WriteCommands.praticaCreateBoard(arguments)
    default: return nil
    }
}

/// A message has no `show` of its own on this side (its content is read through
/// `note read`, since a message is an ordinary note) - every verb is a write.
func messageGroup(_ arguments: Arguments) async throws -> ExitCode {
    switch arguments.word(1) {
    case "link-note": return try await WriteCommands.messageLinkNote(arguments)
    case "unlink-note": return try await WriteCommands.messageUnlinkNote(arguments)
    case "create-note": return try await WriteCommands.messageCreateNote(arguments)
    default:
        throw CommandError("«perg message» vuole link-note, unlink-note o create-note", code: .usage)
    }
}

func run() async -> ExitCode {
    let raw = Array(CommandLine.arguments.dropFirst())

    let arguments: Arguments
    do {
        arguments = try Arguments(raw)
    } catch {
        Output.error("\(error)")
        return .usage
    }

    guard let group = arguments.word(0), !arguments.has("help") else {
        Output.line(Help.text)
        // Asking for help is a success; being given none because you typed nothing is
        // not, so a bare `perg` exits non-zero and a `perg --help` does not.
        return arguments.has("help") ? .success : .usage
    }

    do {
        return try await dispatch(group, arguments)
    } catch let failure as CommandError {
        Output.error(failure.description)
        return failure.code
    } catch let refusal as ConnectorError {
        // Raised by the shared vault API, which has no idea what an exit code is.
        Output.error(refusal.description)
        return refusal.isUsage ? .usage : .failure
    } catch {
        Output.error("\(error)")
        return .failure
    }
}

exit(await run().rawValue)
