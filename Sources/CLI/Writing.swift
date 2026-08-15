import Foundation

/// What every writing command does around the write itself (ADR-0007 §D6).
///
/// One place, so a command cannot be added that quietly skips the guardrails: opening
/// a session for writing gives you the journal and the dry-run switch whether you
/// remember them or not.
enum Writing {
    /// Opens a session armed for a write.
    @MainActor
    static func session(_ arguments: Arguments, command: String) async throws -> VaultSession {
        let root = try VaultResolution.root(from: arguments)
        let session = await VaultResolution.session(at: root)
        session.isDryRun = arguments.has("dry-run")
        session.journalCommand = command
        // No journal for a dry run: nothing happened, and an entry saying otherwise
        // would be a lie in the one file whose job is to be trusted.
        session.journal = session.isDryRun ? nil : WriteJournal(root: root)
        return session
    }

    /// Reports a write, as a diff when it was a rehearsal and as a line when it was
    /// real.
    ///
    /// The diff is computed against what is on disk *now* rather than against anything
    /// the session held, so what it shows is what would actually change.
    @MainActor
    static func report(
        _ result: VaultSession.WriteResult, session: VaultSession, arguments: Arguments
    ) {
        let existing = try? session.read(result.path).text
        let before = existing ?? ""
        let isNew = existing == nil

        if arguments.has("json") {
            struct Payload: Encodable {
                let path: String
                let applied: Bool
                let diff: String?
            }
            Output.json(Payload(
                path: result.path,
                applied: !session.isDryRun,
                diff: UnifiedDiff.between(before, result.text, path: result.path, isNew: isNew)
            ))
            return
        }

        guard session.isDryRun else {
            Output.line("scritto  \(result.path)")
            return
        }
        guard let diff = UnifiedDiff.between(
            before, result.text, path: result.path, isNew: isNew
        ) else {
            Output.line("niente da cambiare in \(result.path)")
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
