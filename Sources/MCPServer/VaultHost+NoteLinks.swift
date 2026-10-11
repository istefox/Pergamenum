import Foundation
import MCP

/// «Collega» and «Scollega» (ADR-0084 §D3, §D4), chained from `writeMessageLinks`' `default:`
/// the way that file chains its own tables. Reached only through `write(_:_:)`, so the session
/// is already armed with `dryRun` defaulting to true and the `--allow-write` lock has been
/// checked.
extension VaultHost {
    func writeNoteLinks(_ name: String, _ arguments: ToolArguments) async throws -> CallTool.Result? {
        switch name {
        case "link_mention":
            return reply(try await VaultAPI.linkMention(
                session, in: try arguments.required("path"), title: try arguments.required("title")
            ))
        case "remove_structural_link":
            return reply(try await VaultAPI.removeStructuralLink(
                session, from: try arguments.required("path"), to: try arguments.required("target")
            ))
        default:
            return nil
        }
    }
}
