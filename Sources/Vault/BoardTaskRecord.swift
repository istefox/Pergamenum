import Foundation

/// The tasks a `.canvas` board's own To Do card(s) carry (SPEC §6.4 tool 8, PG-074; plan
/// `2026-08-31-pg-074-give-the-to-do-tool-an-interactiv` Section 4).
///
/// A sibling of `NoteRecord`, never the same type: a board is not a note (ADR-0025's own
/// separation), so this carries only what a board actually has - no `frontmatter`, no
/// `linkTargets`, no `embedTargets`, which are note concepts a `.canvas` file has no syntax
/// for. One record per board, not per card: a board can hold several To Do cards, and their
/// tasks are told apart from each other by `TaskItem.nodeID`, not by a separate record each.
struct BoardTaskRecord: Identifiable, Equatable, Sendable {
    /// Vault-relative path of the `.canvas` file, e.g. `01 Progetti/Lavagna.canvas`.
    var relativePath: String
    /// Every task line found across the board's own task-bearing `.text` nodes, each carrying
    /// `nodeID` so a write-back knows which node's text to rewrite (VaultSession+Tasks.swift).
    var tasks: [TaskItem]
    var modifiedAt: Date
    var byteSize: Int
    /// SHA-256 of the file's contents as last read by the scanner - `NoteRecord.contentHash`'s
    /// own reason: the cache trusts a row only as long as it still describes the file on disk.
    var contentHash: String

    var id: String { relativePath }
}
