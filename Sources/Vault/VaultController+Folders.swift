import Foundation

/// Renaming and deleting a folder or a board from the sidebar - the facade half
/// (ADR-0022 §D1, §D10, ADR-0025 §D6).
///
/// The file work is on `VaultSession` (ADR-0007 §D3), the same split
/// `VaultController+Files` makes for a note. Three things stay here, and all three are
/// about the window: refusing while a note under the target folder has unsaved edits,
/// following every note the operation moved or removed into the tabs and RECENTI that
/// were showing it, and rescanning so the browser tree rebuilds.
extension VaultController {
    /// Refuses while a note under the folder has unsaved edits.
    ///
    /// The folder-scoped twin of `canOperate(on:)` (`VaultController+Files.swift`),
    /// and refuses for the same reason: moving a file out from under the editor would
    /// either lose the buffer or raise the external-change prompt for a change the app
    /// itself made. Asking the user to save first is the honest version of both.
    private func canOperateOnFolder(_ relativePath: String) -> Bool {
        let folder = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let note = openNote, note.hasUnsavedChanges,
              note.relativePath == folder || note.relativePath.hasPrefix("\(folder)/")
        else { return true }
        recordProblem("salva la nota prima di rinominare o eliminare la cartella")
        return false
    }

    /// Renames a folder and repoints every card that pointed inside it (R-05, R-06,
    /// R-07). It renames no board file: that is `renameBoard` below (ADR-0025 §D6).
    @discardableResult
    func renameFolder(at relativePath: String, to newName: String) -> Bool {
        guard let session, canOperateOnFolder(relativePath) else { return false }
        do {
            let outcome = try session.renameFolder(at: relativePath, to: newName)
            for failure in outcome.failures {
                recordProblem("riferimento non aggiornato: \(failure)")
            }
            for moved in outcome.movedNotes {
                movedNote(from: moved.old, to: moved.new)
            }
            Task { await rescan() }
            return true
        } catch {
            recordProblem("rinomina cartella: \(error)")
            return false
        }
    }

    /// Moves a folder and everything inside it to the Finder's trash (R-11).
    ///
    /// The caller confirms first - `WorkspaceBrowser`'s dialog states the counts
    /// `FolderFileOperations.contentCounts` returned. This method does the deleting,
    /// it does not ask.
    @discardableResult
    func trashFolder(at relativePath: String) -> Bool {
        guard let session, canOperateOnFolder(relativePath) else { return false }
        do {
            let result = try session.trashFolder(at: relativePath)
            for path in result.trashedNotePaths {
                trashedNote(at: path)
            }
            Task { await rescan() }
            return true
        } catch {
            recordProblem("eliminazione cartella: \(error)")
            return false
        }
    }

    /// Renames a board file and repoints every reference that named it (ADR-0025 §D6,
    /// R-08).
    ///
    /// `renameFolder`'s shape above, minus the two follow-ups that belong to notes: no
    /// `canOperateOnFolder` check, because a `.canvas` is not a file the editor can hold
    /// unsaved edits to, and no `movedNote` pass, because renaming a board moves no note.
    /// What is left is the same one: report what could not be repointed, then rescan so
    /// the browser tree rebuilds around the new name.
    @discardableResult
    func renameBoard(at relativePath: String, to newName: String) -> Bool {
        guard let session else { return false }
        do {
            let outcome = try session.renameBoard(at: relativePath, to: newName)
            for failure in outcome.failures {
                recordProblem("riferimento non aggiornato: \(failure)")
            }
            Task { await rescan() }
            return true
        } catch {
            recordProblem("rinomina board: \(error)")
            return false
        }
    }

    /// Moves a board file to the Finder's trash (ADR-0025 §D6, R-08).
    ///
    /// The caller confirms first - `WorkspaceBrowser`'s dialog says the file goes to the
    /// Trash and that the app cannot undo it. This method does the deleting, it does not
    /// ask.
    @discardableResult
    func trashBoard(at relativePath: String) -> Bool {
        guard let session else { return false }
        do {
            try session.trashBoard(at: relativePath)
            Task { await rescan() }
            return true
        } catch {
            recordProblem("eliminazione board: \(error)")
            return false
        }
    }
}
