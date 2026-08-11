import Foundation

/// Renaming, moving and deleting a note from the sidebar (SPEC §10, context menus).
///
/// An extension over its own `NoteStore` rather than new members on the controller:
/// these three need nothing from its private state, and the controller is already the
/// largest type in the app.
extension VaultController {
    /// Refuses while the note has unsaved edits.
    ///
    /// Moving a file out from under the editor would either lose the buffer or raise
    /// the external-change prompt for a change the app itself made. Asking the user to
    /// save first is the honest version of both.
    private func canOperate(on relativePath: String) -> Bool {
        guard let note = openNote, note.relativePath == relativePath, note.hasUnsavedChanges
        else { return true }
        recordProblem("salva la nota prima di rinominarla, spostarla o eliminarla")
        return false
    }

    private var operations: NoteFileOperations? {
        root.map { NoteFileOperations(store: NoteStore(root: $0)) }
    }

    /// Renames a note and every link that pointed at it (wikilink.md W-08).
    @discardableResult
    func renameNote(at relativePath: String, to newTitle: String) -> Bool {
        guard let operations, canOperate(on: relativePath) else { return false }
        let wasOpen = openNote?.relativePath == relativePath

        do {
            let outcome = try operations.rename(
                relativePath, to: newTitle, knownPaths: index.allNotes.map(\.relativePath)
            )
            for failure in outcome.failures {
                recordProblem("link non aggiornato in \(failure)")
            }
            Task {
                await rescan()
                if wasOpen { openNote(at: outcome.newPath) }
            }
            return true
        } catch {
            recordProblem("rinomina: \(error)")
            return false
        }
    }

    @discardableResult
    func moveNote(at relativePath: String, toFolder folder: String) -> Bool {
        guard let operations, canOperate(on: relativePath) else { return false }
        let wasOpen = openNote?.relativePath == relativePath

        do {
            let outcome = try operations.move(relativePath, toFolder: folder)
            Task {
                await rescan()
                if wasOpen { openNote(at: outcome.newPath) }
            }
            return true
        } catch {
            recordProblem("spostamento: \(error)")
            return false
        }
    }

    /// Moves a note to the Finder's trash and says what now links to nothing.
    ///
    /// The caller confirms first: this method does the deleting, it does not ask.
    @discardableResult
    func trashNote(at relativePath: String) -> Bool {
        guard let operations, canOperate(on: relativePath) else { return false }
        let wasOpen = openNote?.relativePath == relativePath

        do {
            let dangling = try operations.trash(
                relativePath, knownPaths: index.allNotes.map(\.relativePath)
            )
            if !dangling.isEmpty {
                // Not rewritten: the links are now broken, and silently deleting them
                // from other people's notes would destroy the only record that
                // something used to be there.
                let title = NoteName.title(
                    fromFileName: (relativePath as NSString).lastPathComponent
                )
                recordProblem("\(dangling.count) note linkavano «\(title)»: ora il link non risolve")
            }
            if wasOpen { closeOpenNote() }
            Task { await rescan() }
            return true
        } catch {
            recordProblem("eliminazione: \(error)")
            return false
        }
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
}
