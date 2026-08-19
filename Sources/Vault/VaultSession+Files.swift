import Foundation

/// Renaming, moving and deleting a note, links and boards included.
///
/// The rules are `NoteFileOperations`; what this adds is the vault they act on and the
/// list of paths they need to rewrite links in. Here rather than on the facade because
/// `perg note rename` has to update backlinks exactly as the sidebar does (ADR-0007
/// §D3): a rename that leaves the links behind breaks wikilink.md W-08 whichever
/// process performed it.
extension VaultSession {
    private var operations: NoteFileOperations { NoteFileOperations(store: store) }

    /// Renames a note and every link that pointed at it (wikilink.md W-08).
    func renameNote(at relativePath: String, to newTitle: String) throws -> NoteFileOperations.Outcome {
        let outcome = try operations.rename(
            relativePath, to: newTitle, knownPaths: index.allNotes.map(\.relativePath)
        )
        // The star is a path, so it moves with the file or it points at nothing (ADR-0012 D6).
        moveStar(from: relativePath, to: outcome.newPath)
        return outcome
    }

    func moveNote(at relativePath: String, toFolder folder: String) throws -> NoteFileOperations.Outcome {
        let outcome = try operations.move(relativePath, toFolder: folder)
        moveStar(from: relativePath, to: outcome.newPath)
        return outcome
    }

    /// Moves a note to the Finder's trash and returns the notes now linking to nothing.
    ///
    /// The caller confirms first: this does the deleting, it does not ask.
    func trashNote(at relativePath: String) throws -> [String] {
        let orphaned = try operations.trash(relativePath, knownPaths: index.allNotes.map(\.relativePath))
        forgetStar(relativePath)
        return orphaned
    }

    /// Every folder in the vault, for the "Sposta in…" menu.
    var folders: [String] {
        var result = Set<String>()
        for note in index.allNotes {
            let folder = (note.relativePath as NSString).deletingLastPathComponent
            guard !folder.isEmpty else { continue }
            // Every ancestor too, so a folder holding only subfolders is still offered.
            var accumulated: [String] = []
            for component in folder.split(separator: "/") {
                accumulated.append(String(component))
                result.insert(accumulated.joined(separator: "/"))
            }
        }
        return result.sorted()
    }

    /// The notes under `Templates/`, title-sorted, for the composer's own menu
    /// (ADR-0011 D5).
    ///
    /// Read off the index rather than the disk, so this costs a filter and is current
    /// the moment a template is created like any other note.
    var templates: [NoteRecord] {
        index.allNotes
            .filter { NoteTemplate.isTemplate($0.relativePath) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
