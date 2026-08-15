import Foundation

/// What every writing command does around the write itself (ADR-0007 §D6).
///
/// The guardrails themselves live in `VaultAPI` so that the MCP server inherits them
/// rather than reimplementing them; what is left here is the shell's half - reading
/// `--dry-run` off the command line, and saying the outcome to a person.
enum Writing {
    /// Opens a session and arms it for a write.
    @MainActor
    static func session(_ arguments: Arguments, command: String) async throws -> VaultSession {
        let session = await VaultResolution.session(at: try VaultResolution.root(from: arguments))
        VaultAPI.arm(session, command: command, dryRun: arguments.has("dry-run"))
        return session
    }

    /// Reports a write, as a diff when it was a rehearsal and as a line when it was real.
    static func report(_ summary: VaultAPI.WriteSummary, arguments: Arguments) {
        if arguments.has("json") {
            Output.json(summary)
            return
        }
        if let note = summary.note { Output.line(note) }

        guard !summary.applied else {
            Output.line("scritto  \(summary.path)")
            return
        }
        guard let diff = summary.diff else {
            Output.line("niente da cambiare in \(summary.path)")
            return
        }
        Output.line(diff)
        Output.line("")
        Output.line("prova: niente è stato scritto. Togli --dry-run per applicare.")
    }

    /// Everything a writing command has to say once it is done, problems included.
    @MainActor
    static func finish(_ session: VaultSession) -> ExitCode {
        for problem in session.problems {
            Output.error(problem)
        }
        return .success
    }
}
