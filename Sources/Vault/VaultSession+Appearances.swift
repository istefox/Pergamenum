import Foundation

// ADR-0084 §D6 (PG-386, N3 session A). App only: no connector exposes it, so it is not in
// `sharedSources`.
extension VaultSession {
    /// The boards and the pratiche that point at the note at `path`, read off the files.
    ///
    /// Synchronous and on request, like `unlinkedMentions(for:)`: the pratiche half reads every
    /// message file's frontmatter. Boards through `CanvasStore`, one that will not load counted
    /// rather than fatal. Pratiche through `VaultAPI.praticaNotes`/`messageNotes`, called rather
    /// than copied, and each link read off its file - never off `NoteRecord.frontmatter.foreignKeys`,
    /// which is empty on a cache-reused record (ADR-0049 §D4). The join is `NoteAppearances.build`.
    func noteAppearances(of path: String) -> NoteAppearances {
        let canvases = CanvasStore(root: root)
        var boards: [(path: String, filePaths: [String])] = []
        var unreadableBoards = 0
        for board in canvases.allBoards() {
            guard let document = try? canvases.load(board: board) else {
                unreadableBoards += 1
                continue
            }
            let filePaths = document.nodes.compactMap { node -> String? in
                if case .file(let filePath, _) = node.kind { return filePath }
                return nil
            }
            boards.append((path: board, filePaths: filePaths))
        }

        let notes = index.allNotes
        let found = VaultAPI.praticaNotes(among: notes, vaultRoot: root)
        let praticaLinks = found.compactMap { pratica -> (folder: String, references: [String])? in
            guard let url = try? store.url(for: pratica.note.relativePath) else { return nil }
            return (folder: pratica.folder, references: PraticaLinks.parse(praticaFileAt: url).notes)
        }
        var messageLinks: [(path: String, folder: String, reference: String)] = []
        let messages = VaultAPI.messageNotes(among: notes, folders: Set(found.map(\.folder)))
        for (folder, records) in messages {
            for record in records {
                guard let text = try? read(record.relativePath).text,
                      let linked = MessageDocument.parse(text)?.frontmatter.linkedNote,
                      case .wikilink(let title)? = PraticaLinkReference(parsing: linked)
                else { continue }
                messageLinks.append((path: record.relativePath, folder: folder, reference: title))
            }
        }

        return NoteAppearances.build(
            notePath: path,
            boards: boards,
            unreadableBoards: unreadableBoards,
            praticaLinks: praticaLinks,
            messageLinks: messageLinks,
            candidates: index.resolve(title:)
        )
    }
}
