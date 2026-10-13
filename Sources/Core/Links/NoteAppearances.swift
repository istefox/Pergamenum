import Foundation

// ADR-0084 §D6 (PG-386, N3 session A).

/// Where a note is used outside notes: the boards and the pratiche that point at it.
struct NoteAppearances: Equatable, Sendable {
    struct Board: Equatable, Sendable {
        let path: String
        let name: String
    }

    struct Pratica: Equatable, Sendable {
        let folder: String
        let title: String
        let linksNote: Bool
        let messages: [String]
    }

    let boards: [Board]
    let pratiche: [Pratica]
    let unreadableBoards: Int

    static let empty = NoteAppearances(boards: [], pratiche: [], unreadableBoards: 0)

    /// The pure join over facts already read off the files.
    ///
    /// A board appears once when any `.file` node's path equals the note's path exactly - a node
    /// names a path, so it is never ambiguous. A pratica or message reference is claimed only
    /// when `candidates` (the index's `resolve(title:)`) answers this note's path alone,
    /// `PraticaLinkResolver.note(candidates:)`'s `unique`: an ambiguous reference is claimed by
    /// nobody. A message is grouped under its pratica's folder, which need not link the note
    /// itself. Everything is sorted by path.
    static func build(
        notePath: String,
        boards: [(path: String, filePaths: [String])],
        unreadableBoards: Int,
        praticaLinks: [(folder: String, references: [String])],
        messageLinks: [(path: String, folder: String, reference: String)],
        candidates: (String) -> [String]
    ) -> NoteAppearances {
        let boardRows = boards
            .filter { $0.filePaths.contains(notePath) }
            .map { Board(path: $0.path, name: boardName(of: $0.path)) }
            .sorted { $0.path < $1.path }

        func claims(_ reference: String) -> Bool {
            PraticaLinkResolver.note(candidates: candidates(reference)) == .unique(notePath)
        }
        var linking: Set<String> = []
        for pratica in praticaLinks where pratica.references.contains(where: claims) {
            linking.insert(pratica.folder)
        }
        var messages: [String: [String]] = [:]
        for message in messageLinks where claims(message.reference) {
            messages[message.folder, default: []].append(message.path)
        }
        let pratiche = linking.union(messages.keys).sorted().map { folder in
            Pratica(
                folder: folder,
                title: praticaTitle(ofFolder: folder),
                linksNote: linking.contains(folder),
                messages: (messages[folder] ?? []).sorted()
            )
        }
        return NoteAppearances(boards: boardRows, pratiche: pratiche, unreadableBoards: unreadableBoards)
    }

    /// The board's file name without `.canvas`, as the Workspace browser names it.
    private static func boardName(of path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// A pratica's title is its folder's own last component, as `VaultAPI.praticaTitle(ofFolder:)`
    /// reads it.
    private static func praticaTitle(ofFolder folder: String) -> String {
        folder.split(separator: "/").last.map(String.init) ?? folder
    }
}
