import Foundation

/// `note classify` and `note extract` (ADR-0085 §D10): flags read here, everything else in
/// `VaultAPI` so the MCP server answers the same way.
enum NoteBirthCommands {
    /// `perg note classify <percorso> --topic a,b [--folder F]`.
    @MainActor
    static func noteClassify(_ arguments: Arguments) async throws -> ExitCode {
        let path = try NoteCommands.requirePath(arguments, "note classify <percorso> --topic <a,b> [--folder <cartella>]")
        let session = try await Writing.session(arguments, command: "note classify")
        let summary = try await VaultAPI.classifyNote(
            session, at: path, topics: arguments["topic"] ?? "", folder: arguments["folder"]
        )
        if arguments.has("json") {
            Output.json(summary)
        } else {
            if let note = summary.note { Output.line(note) }
            report(applied: summary.applied, diffs: [summary.diff], fallback: path)
            if let movedTo = summary.movedTo {
                Output.line(summary.applied ? "spostato  \(movedTo)" : "diventerebbe  \(movedTo)")
            }
        }
        return Writing.finish(session)
    }

    /// `perg note extract <percorso> --lines A-B --title T [--folder F] [--topic t]`.
    @MainActor
    static func noteExtract(_ arguments: Arguments) async throws -> ExitCode {
        let usage = "note extract <percorso> --lines <A-B> --title <titolo> [--folder <cartella>] [--topic <a,b>]"
        let path = try NoteCommands.requirePath(arguments, usage)
        guard let title = arguments["title"], !title.isEmpty else {
            throw CommandError("uso: perg \(usage)", code: .usage)
        }
        let lines = try lineRange(arguments["lines"], usage: usage)
        let session = try await Writing.session(arguments, command: "note extract")
        let summary = try await VaultAPI.extractToNote(
            session, at: path, fromLine: lines.from, toLine: lines.to,
            title: title, folder: arguments["folder"], topics: arguments["topic"]
        )
        if arguments.has("json") {
            Output.json(summary)
        } else {
            if let note = summary.note { Output.line(note) }
            if let refused = summary.sourceRefused { Output.error(refused) }
            report(applied: summary.applied, diffs: [summary.createdDiff, summary.sourceDiff], fallback: summary.created)
        }
        return Writing.finish(session)
    }

    /// `A-B` as two 1-based line numbers; anything else is a usage error.
    static func lineRange(_ raw: String?, usage: String) throws -> (from: Int, to: Int) {
        let parts = (raw ?? "").split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let from = Int(parts[0]), let to = Int(parts[1]) else {
            throw CommandError("--lines vuole due numeri di riga, come 10-12; uso: perg \(usage)", code: .usage)
        }
        return (from, to)
    }

    /// The diffs of a rehearsal, or one line for a real run.
    private static func report(applied: Bool, diffs: [String?], fallback: String) {
        guard !applied else {
            Output.line("scritto  \(fallback)")
            return
        }
        let shown = diffs.compactMap(\.self)
        guard !shown.isEmpty else {
            Output.line("niente da cambiare in \(fallback)")
            return
        }
        for diff in shown { Output.line(diff) }
        Output.line("")
        Output.line("prova: niente è stato scritto. Togli --dry-run per applicare.")
    }
}
