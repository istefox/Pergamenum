import Foundation

/// `perg index …` - what the scan found.
enum IndexCommands {
    @MainActor
    static func run(_ arguments: Arguments) async throws -> ExitCode {
        switch arguments.word(1) {
        case "stats", nil:
            return try await stats(arguments)
        case let other?:
            throw CommandError("«index \(other)» non esiste; c'è «index stats»", code: .usage)
        }
    }

    @MainActor
    private static func stats(_ arguments: Arguments) async throws -> ExitCode {
        let session = await VaultResolution.session(at: try VaultResolution.root(from: arguments))
        let stats = VaultAPI.stats(session)

        if arguments.has("json") {
            Output.json(stats)
        } else {
            Output.line(stats.vault)
            Output.line("  note              \(stats.notes)")
            Output.line("  task              \(stats.tasks) (\(stats.openTasks) aperti)")
            Output.line("  link non risolti  \(stats.unresolvedLinks)")
            Output.line("  dalla cache       \(stats.reusedFromCache)")
            Output.line("  scansione         \(stats.scanMilliseconds) ms")
            for failure in stats.failures {
                Output.line("  illeggibile       \(failure)")
            }
        }
        // Problems are worth reporting even when the command succeeded: a vault whose
        // settings would not parse still answers, and the answer is worth trusting less.
        for problem in session.problems {
            Output.error(problem)
        }
        return .success
    }
}
