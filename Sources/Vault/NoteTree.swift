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
            root.insert(note, components: note.relativePath.split(separator: "/").map(String.init))
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

    /// Accumulates one folder's contents while the notes are walked.
    private struct Builder {
        var folders: [String: Builder] = [:]
        var notes: [NoteRecord] = []

        mutating func insert(_ note: NoteRecord, components: [String]) {
            guard let first = components.first, components.count > 1 else {
                notes.append(note)
                return
            }
            folders[first, default: Builder()].insert(note, components: Array(components.dropFirst()))
        }

        /// This folder's rows: subfolders first, then notes, each group in the order
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

            let noteNodes = notes
                .map { note in
                    Node(id: note.relativePath, name: note.title, kind: .note, children: nil, noteCount: 1)
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            return folderNodes + noteNodes
        }
    }
}
