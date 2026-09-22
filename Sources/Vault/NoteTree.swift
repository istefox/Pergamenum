import Foundation

/// The vault's notes arranged the way they sit on disk.
///
/// The sidebar used to show one flat list of every note with its folder printed
/// underneath, which says where a note is but not what the vault looks like. This is
/// the folder view of SPEC §4.1: the structure the app respects rather than imposes,
/// shown as it actually is.
///
/// A value type with no SwiftUI in it, so the ordering and the grouping can be checked
/// directly rather than through a view that only a person can look at.
enum NoteTree {
    struct Node: Identifiable, Equatable, Sendable {
        enum Kind: Equatable, Sendable { case folder, note }

        /// The path relative to the vault root: `01 Progetti` for a folder,
        /// `01 Progetti/Nota.md` for a note. Unique across the tree, which is what
        /// makes it usable as both the identity and the expansion key.
        var id: String
        /// What the row shows: the folder name, or the note's title.
        var name: String
        var kind: Kind
        /// Nil for a note, so the outline draws no disclosure triangle on a leaf.
        var children: [Node]?
        /// Notes at or below this node, which is what the folder row counts.
        var noteCount: Int
    }

    /// Builds the tree from the index alone - every folder it draws holds at least one
    /// note, `folders: []` below.
    static func build(from notes: [NoteRecord]) -> [Node] {
        build(from: notes, folders: [])
    }

    /// Builds the tree from the index **and** the vault's real folder list (2026-08-28,
    /// the toolbar's "Nuova cartella" chain): with `folders: []` this is byte-identical
    /// to the note-only tree above - a folder containing only PDFs or only canvases and
    /// nothing else still does not appear, which is a real limit of the folder view and
    /// not a rendering bug. `folders` is what lets a folder with **nothing** in it (an
    /// empty one just created) hold a row anyway, the same reason `WorkspaceTree.build
    /// (folders:boards:)` takes a folder list of its own rather than deriving folders
    /// from boards alone (R-10).
    static func build(from notes: [NoteRecord], folders: [String]) -> [Node] {
        var root = Builder()
        for folder in folders {
            root.insertFolder(components: folder.split(separator: "/").map(String.init))
        }
        for note in notes {
            root.insert(
                Builder.Leaf(path: note.relativePath, name: note.title),
                components: note.relativePath.split(separator: "/").map(String.init)
            )
        }
        return root.nodes(prefix: "")
    }

    /// A folder or a note by its id, depth-first - `WorkspaceTree.node(withID:in:)`'s own
    /// shape, needed here now that a folder row is a selectable thing this pane has to
    /// resolve rather than only draw.
    static func node(withID id: String, in tree: [Node]) -> Node? {
        for candidate in tree {
            if candidate.id == id { return candidate }
            if let children = candidate.children, let found = node(withID: id, in: children) {
                return found
            }
        }
        return nil
    }

    /// Builds the tree from a flat list of vault-relative paths rather than from the
    /// index - the Workspace browser's entry point, over the same private `Builder`.
    ///
    /// ADR-0021 D10: `.canvas` files never enter `IndexSnapshot`, so `CanvasStore
    /// .allBoards()` hands this a plain `[String]` instead of `[NoteRecord]`. A leaf's
    /// `name` is its file name with the extension stripped, the same rule `title` is
    /// always under for a note (frontmatter has no `title` key to override it, SPEC
    /// §4.3) - so the two entry points produce the same folder shape for the same
    /// layout. `Node.kind` is **not** extended: a board row is a `.note` leaf here too
    /// (D10), and the Workspace browser draws its own icon over it.
    ///
    static func build(fromPaths paths: [String]) -> [Node] {
        var root = Builder()
        for path in paths {
            let fileName = (path as NSString).lastPathComponent
            root.insert(
                Builder.Leaf(path: path, name: (fileName as NSString).deletingPathExtension),
                components: path.split(separator: "/").map(String.init)
            )
        }
        return root.nodes(prefix: "")
    }

    /// The folders on the path from the root down to `path`, which is what has to be
    /// open for a note to be visible.
    ///
    /// `01 Progetti/A/Nota.md` yields `01 Progetti` and `01 Progetti/A`.
    static func ancestors(of path: String) -> [String] {
        let components = path.split(separator: "/").dropLast()
        var result: [String] = []
        var accumulated: [String] = []
        for component in components {
            accumulated.append(String(component))
            result.append(accumulated.joined(separator: "/"))
        }
        return result
    }

    /// What must be added to the tree's expanded set for `path` to become visible
    /// (`NoteListPane`'s two reveal call sites, ADR-0053 seam #11). Over `ancestors(of:)`
    /// alone: a revealed folder's own row must stay open too, not just what leads down to
    /// it, so it unions with `path` itself; a revealed note has no row of its own to open,
    /// so its ancestors are all that is asked for.
    static func revealed(_ path: String, isFolder: Bool) -> Set<String> {
        let folders = Set(ancestors(of: path))
        return isFolder ? folders.union([path]) : folders
    }

    /// Accumulates one folder's contents while the leaves are walked.
    ///
    /// A leaf is a `(path, name)` pair rather than a `NoteRecord`, which is the whole of
    /// what the tree ever read out of one: the path is the identity and the name is the
    /// row. Holding the pair is what lets `build(fromPaths:)` reach the same algorithm
    /// with `.canvas` paths that carry no record anywhere (ADR-0021 D10) instead of a
    /// second tree implementation beside this one.
    private struct Builder {
        struct Leaf {
            var path: String
            var name: String
        }

        var folders: [String: Builder] = [:]
        var leaves: [Leaf] = []

        mutating func insert(_ leaf: Leaf, components: [String]) {
            guard let first = components.first, components.count > 1 else {
                leaves.append(leaf)
                return
            }
            folders[first, default: Builder()].insert(leaf, components: Array(components.dropFirst()))
        }

        /// A folder that arrives on its own rather than only as a prefix of some note's
        /// path (R-10) - `WorkspaceTree.Builder.insertFolder`'s own shape. `[folders[
        /// first, default: Builder()]` alone, with no leaf appended anywhere, is what
        /// gives an empty folder a `Builder` (and so a `Node`) even when no note or
        /// deeper folder is ever inserted under it.
        mutating func insertFolder(components: [String]) {
            guard let first = components.first else { return }
            folders[first, default: Builder()].insertFolder(components: Array(components.dropFirst()))
        }

        /// This folder's rows: its own notes first, then subfolders, each group in the
        /// order the Finder would use - so `9 Note` sorts before `10 Note` and accents
        /// do not push a note to the end of the list. A note that lives directly in
        /// this folder sits right under the folder's own row, not after every
        /// subfolder's row and its (possibly expanded) contents - Stefano's own
        /// correction, 2026-08-28, against the "folders first" convention this file
        /// carried until then.
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
                        noteCount: children.reduce(0) { $0 + $1.noteCount }
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            let leafNodes = leaves
                .map { leaf in
                    Node(id: leaf.path, name: leaf.name, kind: .note, children: nil, noteCount: 1)
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            return leafNodes + folderNodes
        }
    }
}
