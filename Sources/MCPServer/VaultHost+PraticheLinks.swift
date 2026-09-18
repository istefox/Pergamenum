import Foundation
import MCP

/// The pratica/message link writes (ADR-0049 §D12, R-01, R-02, R-03), split out of
/// `VaultHost.swift` for the same reason `ToolCatalogue+Writing.swift`'s own header
/// gives: left in place, this class's body crossed SwiftLint's `type_body_length`
/// warning (ADR-0045's shape). `session` and `reply(_:)` widen from `private` to
/// internal on `VaultHost` itself for this file to reach them.
extension VaultHost {
    /// The pratica's three general relations, link and unlink (ADR-0049 §D12, R-01).
    /// A table of its own for the reason every other split in this file already
    /// states: one more switch pushed past what SwiftLint allows.
    func writePraticaLinks(_ name: String, _ arguments: ToolArguments) async throws -> CallTool.Result? {
        switch name {
        case "pratica_link_note":
            return reply(try await VaultAPI.linkPraticaNote(
                session, pratica: try arguments.required("pratica"), title: try arguments.required("title")
            ))
        case "pratica_unlink_note":
            return reply(try await VaultAPI.unlinkPraticaNote(
                session, pratica: try arguments.required("pratica"), title: try arguments.required("title")
            ))
        case "pratica_link_board":
            return reply(try await VaultAPI.linkPraticaBoard(
                session, pratica: try arguments.required("pratica"), board: try arguments.required("board")
            ))
        case "pratica_unlink_board":
            return reply(try await VaultAPI.unlinkPraticaBoard(
                session, pratica: try arguments.required("pratica"), board: try arguments.required("board")
            ))
        case "pratica_link_task":
            return reply(try await VaultAPI.linkPraticaTask(
                session, pratica: try arguments.required("pratica"), task: try arguments.required("task")
            ))
        case "pratica_unlink_task":
            return reply(try await VaultAPI.unlinkPraticaTask(
                session, pratica: try arguments.required("pratica"), task: try arguments.required("task")
            ))
        default:
            return try await writePraticaCreate(name, arguments)
        }
    }

    /// Create-then-link (R-03): a note, a task or a board, each pre-tagged with the
    /// pratica's own context before the link itself is written.
    private func writePraticaCreate(_ name: String, _ arguments: ToolArguments) async throws -> CallTool.Result? {
        switch name {
        case "pratica_create_note":
            return reply(try await VaultAPI.createAndLinkPraticaNote(
                session,
                pratica: try arguments.required("pratica"),
                title: try arguments.required("title"),
                folder: arguments.string("folder")
            ))
        case "pratica_create_task":
            return reply(try await VaultAPI.createAndLinkPraticaTask(
                session, pratica: try arguments.required("pratica"), text: try arguments.required("text")
            ))
        case "pratica_create_board":
            return reply(try await VaultAPI.createAndLinkPraticaBoard(
                session,
                pratica: try arguments.required("pratica"),
                name: try arguments.required("name"),
                folder: arguments.string("folder")
            ))
        default:
            return try await writeMessageLinks(name, arguments)
        }
    }

    /// The message's own 0/1 relation (R-02, §D6): link, unlink, or create-then-link.
    private func writeMessageLinks(_ name: String, _ arguments: ToolArguments) async throws -> CallTool.Result? {
        switch name {
        case "message_link_note":
            return reply(try await VaultAPI.linkMessageNote(
                session, message: try arguments.required("message"), title: try arguments.required("title")
            ))
        case "message_unlink_note":
            return reply(try await VaultAPI.unlinkMessageNote(session, message: try arguments.required("message")))
        case "message_create_note":
            return reply(try await VaultAPI.createAndLinkMessageNote(
                session, message: try arguments.required("message"), title: try arguments.required("title")
            ))
        default:
            return nil
        }
    }
}
