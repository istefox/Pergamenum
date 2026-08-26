import Foundation

/// Folds `NoteTree.build(fromPaths:)`'s output into one row per folder, the board that
/// folder owns drawn *on* that row rather than as a separate child (ADR-0024 §D2).
///
/// A value type with no SwiftUI in it, so the fold and the reads the sidebar needs can be
/// checked directly rather than through a view only a person can look at (ADR-0024 §D1).
///
/// STUB (Task 1, plan `2026-08-25-workspace-board-tree-single-selection`): the five
/// functions below are placeholders so `Tests/WorkspaceTreeTests.swift` can be red on its
/// assertions rather than on a build error. Their real bodies are Task 1's GREEN, written
/// by the coder next - never a `fatalError()` and never a force-unwrap in the meantime.
enum WorkspaceTree {
    struct Node {
        /// `.workspace` is an ordinary folder row, with or without a board of its own
        /// (`board == nil` for a folder that only groups, ADR-0024 §D5/R-05).
        /// `.foreignBoard` is a `.canvas` not named after the folder holding it - drawn,
        /// but carrying no `.tag`, so it is structurally unselectable (ADR-0024 §D3).
        enum Kind: Equatable {
            case workspace(board: String?)
            case foreignBoard(path: String)
        }

        /// The folder path for a `.workspace` node, `""` for the vault root; the board
        /// path for a `.foreignBoard` node. The `List`'s selection tag and the row's
        /// identity, one string (ADR-0024 §D2).
        let id: String
        /// What the row shows: the folder name, or the foreign board's file name.
        let name: String
        let kind: Kind
        let children: [Node]
        /// `NoteTree.Node.noteCount` carried through unchanged (ADR-0024 §D2).
        let boardCount: Int
    }

    /// Folds `NoteTree.build(fromPaths: boards)` into one row per folder, the board it
    /// owns (if any) drawn on that row rather than as a separate child.
    ///
    /// `boardPath` is a closure so the folder↔board naming rule is asked, never restated
    /// (ADR-0024 §D2) - the caller passes `CanvasStore.boardPath(forFolder:)` itself.
    static func build(boards: [String], boardPath: (String) -> String) -> [Node] {
        []
    }

    /// Every `.workspace` node's id, including `""` for the vault root; no `.foreignBoard`
    /// path. Feeds the stale-selection drop (Task 4) and the setter's lookup (Task 3).
    static func folders(in nodes: [Node]) -> [String] {
        []
    }

    /// Every node depth-first with its depth, root row included - the filtered list's
    /// input (R-09).
    static func flattened(_ nodes: [Node]) -> [(node: Node, depth: Int)] {
        []
    }

    /// Finds a node by id anywhere in the tree, or nil for an id no `.workspace` node
    /// carries (a `.foreignBoard` path included) - the selection setter's lookup (Task 3).
    static func node(withID id: String, in nodes: [Node]) -> Node? {
        nil
    }
}
