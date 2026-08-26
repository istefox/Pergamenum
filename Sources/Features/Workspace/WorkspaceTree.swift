import Foundation

/// Folds `NoteTree.build(fromPaths:)`'s output into one row per folder, the board that
/// folder owns drawn *on* that row rather than as a separate child (ADR-0024 §D2).
///
/// A value type with no SwiftUI in it, so the fold and the reads the sidebar needs can be
/// checked directly rather than through a view only a person can look at (ADR-0024 §D1).
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
        // The vault root's board, asked through the rule rather than restated here
        // (ADR-0024 §D2). Its file name is also the root row's name, derived the way
        // `NoteTree.build(fromPaths:)` derives a leaf's - so the synthesised row reads
        // exactly as the leaf it stands in for, whether or not that leaf exists.
        let rootBoard = boardPath("")
        let rootName = ((rootBoard as NSString).lastPathComponent as NSString)
            .deletingPathExtension

        var rows = NoteTree.build(fromPaths: boards).map { node -> Node in
            // ADR-0024 F7: `NoteTree` emits no node for the vault root, so the root board
            // arrives as a top-level leaf with no folder above it. That leaf *is* the row
            // for folder `""` - the one place this fold synthesises a folder instead of
            // folding one. Every other top-level leaf is a `.canvas` named after nothing,
            // and `fold` draws it as a `.foreignBoard` (§D3).
            guard node.kind == .note, node.id == rootBoard else {
                return fold(node, boardPath: boardPath)
            }
            return Node(
                id: "",
                name: rootName,
                kind: .workspace(board: node.id),
                children: [],
                boardCount: node.noteCount
            )
        }

        // The root row exists whether or not the file does. `open(folder: "")` is always
        // valid - it is what `attach` loads - so a root board reached from the breadcrumb
        // or a route has a row to light even before anything has been dropped on it,
        // which is the divergence ADR-0024 A3 rejected the board-path tag for. A root
        // with no `.canvas` yet is board-less exactly as any other grouping folder is
        // (§D5): its row selects, and opens nothing.
        if !rows.contains(where: { $0.id == "" }) {
            rows.append(
                Node(id: "", name: rootName, kind: .workspace(board: nil), children: [], boardCount: 0)
            )
        }
        return rows
    }

    /// One `NoteTree` node folded into a row.
    ///
    /// A folder keeps the board named after it *on* itself and drops that leaf from its
    /// children, which is the whole of R-01: one row per folder, never a second row
    /// beside it for the board it owns. Any other leaf is a `.canvas` not named after the
    /// folder holding it and becomes a `.foreignBoard` row of its own (ADR-0024 §D3).
    private static func fold(_ node: NoteTree.Node, boardPath: (String) -> String) -> Node {
        guard node.kind == .folder else {
            return Node(
                id: node.id,
                name: node.name,
                kind: .foreignBoard(path: node.id),
                children: [],
                boardCount: node.noteCount
            )
        }
        let own = boardPath(node.id)
        let children = node.children ?? []
        let ownsBoard = children.contains { $0.kind == .note && $0.id == own }
        return Node(
            id: node.id,
            name: node.name,
            kind: .workspace(board: ownsBoard ? own : nil),
            children: children
                .filter { !($0.kind == .note && $0.id == own) }
                .map { fold($0, boardPath: boardPath) },
            // `NoteTree.Node.noteCount` carried through unchanged (ADR-0024 §D2): the
            // fold moves a board onto its folder's row, it does not stop counting it.
            boardCount: node.noteCount
        )
    }

    /// Every `.workspace` node's id, including `""` for the vault root; no `.foreignBoard`
    /// path. Feeds the stale-selection drop (Task 4) and the setter's lookup (Task 3).
    static func folders(in nodes: [Node]) -> [String] {
        flattened(nodes).compactMap { row in
            guard case .workspace = row.node.kind else { return nil }
            return row.node.id
        }
    }

    /// Every node depth-first with its depth, root row included - the filtered list's
    /// input (R-09).
    static func flattened(_ nodes: [Node]) -> [(node: Node, depth: Int)] {
        var rows: [(node: Node, depth: Int)] = []
        func walk(_ nodes: [Node], depth: Int) {
            for node in nodes {
                rows.append((node: node, depth: depth))
                walk(node.children, depth: depth + 1)
            }
        }
        walk(nodes, depth: 0)
        return rows
    }

    /// Finds a node by id anywhere in the tree, or nil for an id no `.workspace` node
    /// carries (a `.foreignBoard` path included) - the selection setter's lookup (Task 3).
    ///
    /// A `.foreignBoard` is skipped rather than merely absent from the answer: its id is a
    /// board path, so a lookup that returned it would hand the setter something the
    /// selection's tag namespace does not contain (ADR-0024 §D3).
    static func node(withID id: String, in nodes: [Node]) -> Node? {
        for candidate in nodes {
            if case .workspace = candidate.kind, candidate.id == id { return candidate }
            if let found = node(withID: id, in: candidate.children) { return found }
        }
        return nil
    }
}
