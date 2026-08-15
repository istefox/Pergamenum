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
    case "note": return try await NoteCommands.run(arguments)
    case "search": return try await SearchCommands.run(arguments)
    case "task": return try await TaskCommands.run(arguments)
    case "day": return try await DayCommands.run(arguments)
    case "lint": return try await LintCommands.run(arguments)
    case "index": return try await IndexCommands.run(arguments)
    case "help":
        Output.line(Help.text)
        return .success
    default:
        throw CommandError("«\(group)» non è un gruppo di comandi; prova «perg help»", code: .usage)
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
    } catch {
        Output.error("\(error)")
        return .failure
    }
}

exit(await run().rawValue)
