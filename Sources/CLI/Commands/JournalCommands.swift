import Foundation

/// `perg journal log|undo` - the net under every write this tool made (ADR-0007 §D6).
enum JournalCommands {
    @MainActor
    static func run(_ arguments: Arguments) async throws -> ExitCode {
        switch arguments.word(1) {
        case "log", nil: return try log(arguments)
        case "undo": return try await undo(arguments)
        case let other?:
            throw CommandError("«journal \(other)» non esiste; ci sono log e undo", code: .usage)
        }
    }

    private static func log(_ arguments: Arguments) throws -> ExitCode {
        // Read before the vault is resolved: a malformed number is the caller's mistake and
        // is said first (ADR-0063 §D1).
        let limit = try VaultAPI.limit(parsing: arguments["limit"])
        let rows = try VaultAPI.journalLog(
            at: try VaultResolution.root(from: arguments),
            base: try VaultState.applicationSupportBase(),
            limit: limit
        )

        if arguments.has("json") {
            Output.json(rows)
        } else if rows.isEmpty {
            Output.line("nessuna scrittura registrata")
        } else {
            for row in rows {
                let verb = row.created ? "creato " : "scritto"
                Output.line("\(row.id)  \(verb)  \(row.path)   (\(row.command))")
            }
        }
        return .success
    }

    @MainActor
    private static func undo(_ arguments: Arguments) async throws -> ExitCode {
        guard let id = arguments.word(2) else {
            throw CommandError("uso: perg journal undo <id>", code: .usage)
        }
        let session = try await Writing.session(arguments, command: "journal undo \(id)")
        switch try await VaultAPI.undo(session, id: id) {
        case .single(let summary): Writing.report(summary, arguments: arguments)
        case .operation(let summary): Writing.report(summary, arguments: arguments)
        }
        return Writing.finish(session)
    }
}
