import Foundation

/// `perg view list` and `perg view run <nota>` - a saved query, from a shell (ADR-0009 §D4).
///
/// The engine is the app's own: the same parser, the same evaluator, the same closed field
/// list. A second implementation here would be a second answer to the same block.
enum ViewCommands {
    @MainActor
    static func run(_ arguments: Arguments) async throws -> ExitCode {
        switch arguments.word(1) {
        case "list": return try await list(arguments)
        case "run": return try await runOne(arguments)
        default:
            throw CommandError("«perg view» vuole «list» o «run»; prova «perg help»", code: .usage)
        }
    }

    @MainActor
    private static func list(_ arguments: Arguments) async throws -> ExitCode {
        let session = await VaultResolution.session(at: try VaultResolution.root(from: arguments))
        let views = VaultAPI.views(session)

        if arguments.has("json") {
            Output.json(views)
        } else {
            for view in views {
                Output.line("\(view.path)#\(view.ordinal)    \(view.render ?? "—")")
                if let error = view.error { Output.line("    \(error)") }
            }
        }
        return .success
    }

    @MainActor
    private static func runOne(_ arguments: Arguments) async throws -> ExitCode {
        let session = await VaultResolution.session(at: try VaultResolution.root(from: arguments))
        guard let path = arguments.word(2) else {
            throw CommandError("«perg view run» vuole il percorso di una nota", code: .usage)
        }
        let run = try VaultAPI.runView(session, at: path, ordinal: arguments["ordinal"].flatMap(Int.init))

        if arguments.has("json") {
            Output.json(run)
        } else {
            print(run)
        }
        return .success
    }

    /// One line per row, the columns in the order the block wrote them, groups named when there
    /// is more than one. A table drawn in characters would need the terminal's width and would
    /// still be wrong in a pipe.
    private static func print(_ run: VaultAPI.ViewRun) {
        Output.line("\(run.view.render ?? "vista") · \(run.total) note")
        for group in run.groups {
            if run.groups.count > 1 {
                Output.line("  [\(group.label ?? run.absentLabel)]")
            }
            for row in group.rows {
                // The first column is the row's own label, printed already: repeating it made
                // every line read «Vibrofer    Vibrofer · …».
                let cells = run.view.columns
                    .dropFirst()
                    .compactMap { row.values[$0] }
                    .joined(separator: " · ")
                Output.line("  \(row.title)\(cells.isEmpty ? "" : "    \(cells)")")
            }
        }
    }
}
