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
    ///
    /// A refusal here (ADR-0046 §D1/§D6) is a stale wikilink that re-running the rename cannot
    /// repair, unlike the tag path: once the file has moved, `oldTitle` is derived from the
    /// *new* file name, so a second call computes `from: X, to: X` and rewrites nothing.
    func renameNote(at relativePath: String, to newTitle: String) async throws -> NoteFileOperations.Outcome {
        let plan = try operations.renamePlan(
            relativePath, to: newTitle, knownPaths: index.allNotes.map(\.relativePath)
        )
        var outcome = NoteFileOperations.Outcome(newPath: plan.newPath, failures: plan.failures)

        try await transaction("note rename") {
            if plan.newPath != relativePath {
                try await moveFile(from: relativePath, to: plan.newPath)
            }
            let notes = await VaultPlanApplication.apply(plan.noteChanges, writing: writeGuarded)
            // A `.canvas` goes through `writeFile` rather than `write`: it is journalled like a
            // note but leaves the index and the per-note history alone, because a board is not a
            // note - the reason `apply` takes the writer instead of assuming it (ADR-0041 §D4).
            let boards = await VaultPlanApplication.apply(plan.boardChanges, writing: writeFileGuarded)
            outcome.rewrittenPaths.append(contentsOf: notes.rewrittenPaths + boards.rewrittenPaths)
            outcome.failures.append(contentsOf: notes.failures + boards.failures)
            outcome.refusals.append(contentsOf: notes.refusals + boards.refusals)
        }

        // The star is a path, so it moves with the file or it points at nothing (ADR-0012 D6).
        // `moveFile` itself carries the star along now (PG-238/#526), the same door it already
        // carries the note id through - so this also reaches a connector undo of the move.
        return outcome
    }

    /// Moves a note between folders. Boards only: a wikilink names a note by title, not by
    /// path, so a move touches no note text (wikilink.md W-01) and a refusal here (ADR-0046
    /// §D6) is a `.canvas` card left pointing at the old path.
    func moveNote(at relativePath: String, toFolder folder: String) async throws -> NoteFileOperations.Outcome {
        let plan = try operations.movePlan(relativePath, toFolder: folder)
        var outcome = NoteFileOperations.Outcome(newPath: plan.newPath, failures: plan.failures)

        try await transaction("note move") {
            if plan.newPath != relativePath {
                try await moveFile(from: relativePath, to: plan.newPath)
            }
            let boards = await VaultPlanApplication.apply(plan.boardChanges, writing: writeFileGuarded)
            outcome.rewrittenPaths.append(contentsOf: boards.rewrittenPaths)
            outcome.failures.append(contentsOf: boards.failures)
            outcome.refusals.append(contentsOf: boards.refusals)
        }

        return outcome
    }

    /// Moves a note to the Finder's trash and returns the notes now linking to nothing.
    ///
    /// The caller confirms first: this does the deleting, it does not ask.
    func trashNote(at relativePath: String) async throws -> [String] {
        let knownPaths = index.allNotes.map(\.relativePath)
        try await transaction("note trash") {
            try await trashFile(at: relativePath)
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
            var prefix = ""
            for component in folder.split(separator: "/") {
                prefix = prefix.isEmpty ? String(component) : prefix + "/" + component
                result.insert(prefix)
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
