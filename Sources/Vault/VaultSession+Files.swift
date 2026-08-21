import Foundation

/// Renaming, moving and deleting a note, links and boards included.
///
/// The rules that decide *what* changes are `NoteFileOperations`'s `renamePlan`/`movePlan`/
/// `danglingLinks`; what performs it is here, inside `transaction`, so every write a rename or a
/// move makes carries one gesture id and `isDryRun` stops all of them at once rather than being a
/// flag each rule has to remember (ADR-0016 §D6). Here rather than on the facade because
/// `perg note rename` has to update backlinks exactly as the sidebar does (ADR-0007
/// §D3): a rename that leaves the links behind breaks wikilink.md W-08 whichever
/// process performed it.
extension VaultSession {
    private var operations: NoteFileOperations { NoteFileOperations(store: store) }

    /// Renames a note and every link that pointed at it (wikilink.md W-08).
    func renameNote(at relativePath: String, to newTitle: String) throws -> NoteFileOperations.Outcome {
        let plan = try operations.renamePlan(
            relativePath, to: newTitle, knownPaths: index.allNotes.map(\.relativePath)
        )
        var outcome = NoteFileOperations.Outcome(newPath: plan.newPath, failures: plan.failures)

        try transaction("note rename") {
            if plan.newPath != relativePath {
                try moveFile(from: relativePath, to: plan.newPath)
            }
            for change in plan.noteChanges {
                do {
                    try write(change.after, to: change.path)
                    outcome.rewrittenPaths.append(change.path)
                } catch {
                    outcome.failures.append("\(change.path): \(error)")
                }
            }
            for change in plan.boardChanges {
                do {
                    try writeFile(change.after, to: change.path)
                    outcome.rewrittenPaths.append(change.path)
                } catch {
                    outcome.failures.append("\(change.path): \(error)")
                }
            }
        }

        // The star is a path, so it moves with the file or it points at nothing (ADR-0012 D6).
        // Skipped on a dry run: nothing on disk moved, and moving the star for real would be the
        // one part of a rehearsal that was not a rehearsal.
        if !isDryRun {
            moveStar(from: relativePath, to: outcome.newPath)
        }
        return outcome
    }

    func moveNote(at relativePath: String, toFolder folder: String) throws -> NoteFileOperations.Outcome {
        let plan = try operations.movePlan(relativePath, toFolder: folder)
        var outcome = NoteFileOperations.Outcome(newPath: plan.newPath, failures: plan.failures)

        try transaction("note move") {
            if plan.newPath != relativePath {
                try moveFile(from: relativePath, to: plan.newPath)
            }
            for change in plan.boardChanges {
                do {
                    try writeFile(change.after, to: change.path)
                    outcome.rewrittenPaths.append(change.path)
                } catch {
                    outcome.failures.append("\(change.path): \(error)")
                }
            }
        }

        if !isDryRun {
            moveStar(from: relativePath, to: outcome.newPath)
        }
        return outcome
    }

    /// Moves a note to the Finder's trash and returns the notes now linking to nothing.
    ///
    /// The caller confirms first: this does the deleting, it does not ask.
    func trashNote(at relativePath: String) throws -> [String] {
        let knownPaths = index.allNotes.map(\.relativePath)
        try transaction("note trash") {
            try trashFile(at: relativePath)
        }
        let orphaned = operations.danglingLinks(for: relativePath, knownPaths: knownPaths)
        if !isDryRun {
            forgetStar(relativePath)
        }
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
