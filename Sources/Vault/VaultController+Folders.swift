import Foundation

/// Renaming and deleting a folder from the sidebar - the facade half (ADR-0022 §D1, §D10).
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

    /// Renames a folder, its board file and every reference that named either
    /// (R-05, R-06, R-07).
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

    /// Renames a board file (ADR-0025 §D6, R-08).
    ///
    /// TODO(ADR-0025 Task 7): placeholder only - `BoardFileOperations` does not exist
    /// yet and there is no session half to call through. Declared now so the target
    /// builds while `Tests/BoardFileOperationsTests.swift` is red on its assertions
    /// rather than on a missing symbol; the coder fills in the real body beside
    /// `renameFolder` above, mirroring its `canOperate`/`recordProblem`/`rescan` shape.
    @discardableResult
    func renameBoard(at relativePath: String, to newName: String) -> Bool {
        recordProblem("rinomina board: non ancora implementato (ADR-0025 Task 7)")
        return false
    }

    /// Moves a board file to the Finder's trash (ADR-0025 §D6, R-08). TODO(ADR-0025
    /// Task 7), see `renameBoard` above.
    @discardableResult
    func trashBoard(at relativePath: String) -> Bool {
        recordProblem("eliminazione board: non ancora implementato (ADR-0025 Task 7)")
        return false
    }
}
