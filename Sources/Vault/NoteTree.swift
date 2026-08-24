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

    /// Builds the tree from the index.
    ///
    /// Only notes: the index holds markdown and nothing else, so a folder containing
    /// only PDFs or only canvases does not appear. That is a real limit of the folder
    /// view and not a rendering bug - it is the same set the flat list showed.
    static func build(from notes: [NoteRecord]) -> [Node] {
        var root = Builder()
        for note in notes {
            root.insert(
                Builder.Leaf(path: note.relativePath, name: note.title),
                components: note.relativePath.split(separator: "/").map(String.init)
            )
        }
        return root.nodes(prefix: "")
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

        /// This folder's rows: subfolders first, then leaves, each group in the order
        /// the Finder would use - so `9 Note` sorts before `10 Note` and accents do
        /// not push a note to the end of the list.
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

            return folderNodes + leafNodes
        }
    }
}
