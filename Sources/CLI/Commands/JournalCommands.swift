import Foundation

/// `perg journal log|undo` - the net under every write this tool made (ADR-0007 §D6).
enum JournalCommands {
    struct Row: Encodable {
        let id: String
        let timestamp: Date
        let command: String
        let path: String
        let created: Bool
    }

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
        let journal = WriteJournal(root: try VaultResolution.root(from: arguments))
        let limit = arguments["limit"].flatMap(Int.init) ?? 20
        let entries = journal.entries().suffix(limit)

        if arguments.has("json") {
            Output.json(entries.map {
                Row(id: $0.id, timestamp: $0.timestamp, command: $0.command,
                    path: $0.path, created: $0.textBefore == nil)
            })
        } else if entries.isEmpty {
            Output.line("nessuna scrittura registrata")
        } else {
            for entry in entries {
                let verb = entry.textBefore == nil ? "creato " : "scritto"
                Output.line("\(entry.id)  \(verb)  \(entry.path)   (\(entry.command))")
            }
        }
        return .success
    }

    @MainActor
    private static func undo(_ arguments: Arguments) async throws -> ExitCode {
        guard let id = arguments.word(2) else {
            throw CommandError("uso: perg journal undo <id>", code: .usage)
        }
        let root = try VaultResolution.root(from: arguments)
        let journal = WriteJournal(root: root)
        guard let entry = journal.entry(id: id) else {
            throw CommandError("nessuna scrittura con id \(id); guarda «perg journal log»")
        }

        let session = await VaultResolution.session(at: root)

        // Refuse when the file has moved on since. Undoing onto somebody else's later
        // edit is worse than declining to undo at all: it would silently destroy work
        // this journal knows nothing about.
        let current = try? session.read(entry.path)
        guard let current else {
            throw CommandError("«\(entry.path)» non c'è più: non ripristino su un file assente")
        }
        guard current.record.contentHash == entry.hashAfter else {
            throw CommandError(
                """
                «\(entry.path)» è cambiato dopo quella scrittura: non lo tocco. \
                Il journal ripristina solo ciò che ha scritto lui.
                """
            )
        }

        guard let textBefore = entry.textBefore else {
            throw CommandError(
                """
                quella scrittura ha creato «\(entry.path)»: annullarla vuol dire \
                cancellare il file, e questo comando non cancella. Rimuovilo a mano.
                """
            )
        }

        session.isDryRun = arguments.has("dry-run")
        session.journalCommand = "journal undo \(id)"
        session.journal = session.isDryRun ? nil : journal
        let result = try session.write(textBefore, to: entry.path)
        Writing.report(result, session: session, arguments: arguments)
        return Writing.finish(session)
    }
}
