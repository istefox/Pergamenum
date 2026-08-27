import Foundation

/// The Workspace sidebar's rows: a folder row per folder and a board row per `.canvas`,
/// two different things and never one folded into the other (ADR-0025 §D2).
///
/// A value type with no SwiftUI in it, so the shape and the reads the sidebar needs can be
/// checked directly rather than through a view only a person can look at (ADR-0024 §D1).
enum WorkspaceTree {
    struct Node {
        /// ADR-0025 §D2's shape: `.folder` is a folder row and nothing else (a board it
        /// holds is a sibling `.board` row of its own, never drawn on it); `.board`
        /// carries the board file's own path and is an ordinary, openable row wherever the
        /// file lives and whatever it is called - there is no more "foreign" board
        /// (ADR-0024 §D3 superseded in full).
        enum Kind: Equatable {
            case folder
            case board(path: String)
        }

        /// The folder path for a `.folder` node, the board file's path for a `.board`
        /// one - never `""`, because there is no row for the vault root (ADR-0025 §D2).
        /// The `List`'s selection tag and the row's identity, one string.
        let id: String
        /// What the row shows: the folder name, or the board's file name without its
        /// extension.
        let name: String
        let kind: Kind
        let children: [Node]
        /// Boards at or below this row: one for a `.board`, the sum of its children for a
        /// `.folder` - `NoteTree.Node.noteCount`'s rule with boards counted instead.
        let boardCount: Int
    }

    /// ADR-0025 §D2's builder: folders and boards are two flat lists walked into one
    /// nested structure, never one `NoteTree` fold.
    ///
    /// `NoteTree.build(fromPaths:)` makes a folder node only out of a leaf's path
    /// components, so a folder holding no `.canvas` anywhere below it would simply vanish
    /// (R-10) - which is why this does not call it and carries a builder of its own
    /// (§D2). Both lists are vault-relative paths: a folder path names a row, a board path
    /// names a row *and* its own file. A folder and the board named after it are two
    /// sibling rows, and there is **no synthesized root row** - the top level is the vault
    /// root's own contents (R-01, R-11).
    ///
    /// Folders before boards at every depth, each group in `localizedStandardCompare`
    /// order - `NoteTree.Builder.nodes(prefix:)`'s own rule (`NoteTree.swift:123, 129`),
    /// so the two sidebars sort the same way.
    static func build(folders: [String], boards: [String]) -> [Node] {
        var root = Builder()
        for folder in folders {
            root.insertFolder(components: folder.split(separator: "/").map(String.init))
        }
        for board in boards {
            let components = board.split(separator: "/").map(String.init)
            guard let fileName = components.last else { continue }
            root.insertBoard(
                Builder.Leaf(path: board, name: (fileName as NSString).deletingPathExtension),
                components: Array(components.dropLast())
            )
        }
        return root.nodes(prefix: "")
    }

    /// Accumulates one folder's contents while both lists are walked - `NoteTree.Builder`'s
    /// shape with a second entry point, because a folder here arrives on its own rather
    /// than only as a prefix of some leaf's path (R-10).
    private struct Builder {
        struct Leaf {
            var path: String
            var name: String
        }

        var folders: [String: Builder] = [:]
        var boards: [Leaf] = []

        /// Walks a folder path into existence. The last component's `Builder` is created
        /// by the recursion's own subscript and then left empty, which is exactly what an
        /// empty folder is.
        mutating func insertFolder(components: [String]) {
            guard let first = components.first else { return }
            folders[first, default: Builder()]
                .insertFolder(components: Array(components.dropFirst()))
        }

        /// `components` is the board's **containing folder**, so a `.canvas` at the vault
        /// root lands here rather than under any folder row (R-11). A folder named only by
        /// a board's path still gets a row, so a board is never dropped for want of an
        /// entry in `folders`.
        mutating func insertBoard(_ leaf: Leaf, components: [String]) {
            guard let first = components.first else {
                boards.append(leaf)
                return
            }
            folders[first, default: Builder()]
                .insertBoard(leaf, components: Array(components.dropFirst()))
        }

        func nodes(prefix: String) -> [Node] {
            let folderNodes = folders
                .map { name, builder -> Node in
                    let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
                    let children = builder.nodes(prefix: path)
                    return Node(
                        id: path,
                        name: name,
                        kind: .folder,
                        children: children,
                        // Every board at or below this row, its own boards included -
                        // each board node counts one, the way a `NoteTree` leaf does.
                        boardCount: children.reduce(0) { $0 + $1.boardCount }
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            let boardNodes = boards
                .map { leaf in
                    Node(
                        id: leaf.path,
                        name: leaf.name,
                        kind: .board(path: leaf.path),
                        children: [],
                        boardCount: 1
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            return folderNodes + boardNodes
        }
    }

    /// Every folder row's id and no board path at all (ADR-0025 §D2) - what "Espandi
    /// tutto" opens, and the one question "which ids are expandable" is asked through.
    static func folders(in nodes: [Node]) -> [String] {
        flattened(nodes).compactMap { row in
            switch row.node.kind {
            case .folder: return row.node.id
            case .board: return nil
            }
        }
    }

    /// Every node depth-first with its depth - the filtered list's input (R-09). There is
    /// no root row to include: the top level is the vault root's own contents (§D2).
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

    /// Finds a node by id anywhere in the tree, whichever kind it is, or nil for an id no
    /// row carries - the selection setter's lookup and the stale-selection drop's
    /// question, one function.
    ///
    /// ADR-0024's `.foreignBoard` skip is gone with the concept (§D2/§D3 superseded):
    /// every row is selectable now, so a board path is an answer here rather than an id
    /// outside the selection's namespace.
    static func node(withID id: String, in nodes: [Node]) -> Node? {
        for candidate in nodes {
            if candidate.id == id { return candidate }
            if let found = node(withID: id, in: candidate.children) { return found }
        }
        return nil
    }
}
