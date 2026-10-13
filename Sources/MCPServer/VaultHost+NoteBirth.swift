import Foundation
import MCP

/// «Classifica» and «Estrai» (ADR-0085 §D10), chained from `writeNoteLinks`' `default:` the way
/// that file is chained itself. Reached only through `write(_:_:)`, so the session is already
/// armed with `dryRun` defaulting to true and the `--allow-write` lock has been checked.
extension VaultHost {
    func writeNoteBirth(_ name: String, _ arguments: ToolArguments) async throws -> CallTool.Result? {
        switch name {
        case "classify_note":
            return reply(try await VaultAPI.classifyNote(
                session, at: try arguments.required("path"),
                topics: try arguments.required("topics"), folder: arguments.string("folder")
            ))
        case "extract_to_note":
            return reply(try await VaultAPI.extractToNote(
                session, at: try arguments.required("path"),
                fromLine: try line("fromLine", arguments), toLine: try line("toLine", arguments),
                title: try arguments.required("title"), folder: arguments.string("folder"),
                topics: arguments.string("topics")
            ))
        default:
            return nil
        }
    }

    /// A 1-based line number, or a usage error naming the argument.
    private func line(_ name: String, _ arguments: ToolArguments) throws -> Int {
        guard let value = arguments.int(name) else {
            throw ConnectorError("«\(name)» vuole un numero di riga, da 1", usage: true)
        }
        return value
    }
}
