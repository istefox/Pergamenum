import Foundation

/// Folds `NoteTree.build(fromPaths:)`'s output into one row per folder, the board that
/// folder owns drawn *on* that row rather than as a separate child (ADR-0024 §D2).
///
/// A value type with no SwiftUI in it, so the fold and the reads the sidebar needs can be
/// checked directly rather than through a view only a person can look at (ADR-0024 §D1).
enum WorkspaceTree {
    struct Node {
        /// `.workspace` and `.foreignBoard` are ADR-0024's cases, superseded by ADR-0025
        /// §D2 but kept here **alongside** the two new ones below rather than removed:
        /// `WorkspaceBrowser.swift`'s five exhaustive switches over `Kind` (`selection`,
        /// `identifier`, `taggedRow`, `accessibilityLabel`, `icon`) and the whole of
        /// `WorkspaceController.swift` still build a tree through the old
        /// `build(boards:boardPath:)` below and read only these two cases; deleting them
        /// now would break every one of those call sites, which Tasks 3 and 5 own, not
        /// Task 2. `.folder`/`.board(path:)` are additive placeholders reachable only
        /// through the new `build(folders:boards:)` overload this task's tests exercise.
        /// The coder's GREEN phase (this task) re-cases `identifier(for:)`/
        /// `selection(for:)`; Task 5 re-cases the other three switches and this whole
        /// doc comment is rewritten once `.workspace`/`.foreignBoard` are finally deleted.
        ///
        /// `.workspace` is an ordinary folder row, with or without a board of its own
        /// (`board == nil` for a folder that only groups, ADR-0024 §D5/R-05).
        /// `.foreignBoard` is a `.canvas` not named after the folder holding it - drawn,
        /// but carrying no `.tag`, so it is structurally unselectable (ADR-0024 §D3).
        ///
        /// ADR-0025 §D2's real shape: `.folder` is an ordinary folder row (a board it
        /// owns is now a sibling `.board` row of its own, never drawn on it); `.board`
        /// carries the board file's own path, and is an ordinary row whoever wrote the
        /// file - there is no more "foreign" board (ADR-0024 §D3 superseded in full).
        enum Kind: Equatable {
            case workspace(board: String?)
            case foreignBoard(path: String)
            case folder
            case board(path: String)
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

    /// ADR-0025 §D2's real builder (Task 2, RED: placeholder). Folders and boards are
    /// two flat lists here, not one `NoteTree` fold: `NoteTree.build(fromPaths:)` makes a
    /// folder node only from a leaf's path components, so an empty folder (R-10) would
    /// vanish, which is why this does not call it (§D2's fourth bullet). GREEN walks both
    /// lists into one nested structure, folders first then leaves at every depth by
    /// `localizedStandardCompare`, with **no synthesized root row** - the top level is
    /// simply the vault root's own contents (R-11).
    ///
    /// Placeholder body only: returns `[]` regardless of input, so every test built on
    /// top of it is red on its `#expect`/`#require`, never on a build error.
    static func build(folders: [String], boards: [String]) -> [Node] {
        []
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
