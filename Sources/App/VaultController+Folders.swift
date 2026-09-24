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
    ///
    /// Not `private`, since ADR-0026 §D10: "a folder move reuses `canOperateOnFolder`,
    /// whose guard is already written for exactly this".
    ///
    /// Asks of every column, like `canOperate(on:)` (`VaultController+Files.swift`) already
    /// does — not only `openNote` (ADR-0056 §D7): `renameFolder`/`trashFolder` now reach a
    /// note in any column through `movedNote`/`trashedNote`, so a dirty tab this check
    /// missed in another column would have its buffer silently replaced or its tab closed
    /// with no dialogue.
    func canOperateOnFolder(_ relativePath: String) -> Bool {
        let folder = relativePath.trimmingCharacters(in: .pathSlashes)
        let hasDirtyTab = columns.contains { column in
            column.tabs.contains { tab in
                tab.note.hasUnsavedChanges
                    && (tab.note.relativePath == folder || tab.note.relativePath.hasPrefix("\(folder)/"))
            }
        }
        guard !hasDirtyTab else {
            recordProblem(Self.unsavedNoteInFolderRefusal)
            return false
        }
        return true
    }

    /// The exact sentence `canOperateOnFolder(_:)` records, kept as one value for the
    /// same reason as `unsavedNoteRefusal` in `VaultController+Files.swift`.
    static let unsavedNoteInFolderRefusal = "salva la nota prima di rinominare o eliminare la cartella"

    /// Renames a folder and repoints every card that pointed inside it (R-05, R-06,
    /// R-07). It renames no board file: that is `renameBoard` below (ADR-0025 §D6).
    ///
    /// Answers with the outcome's own `newPath` rather than a bare `Bool`, so a caller
    /// navigating to where the folder landed reads it from here instead of recomputing
    /// the same arithmetic `FolderFileOperations.renamePlan` already did (PG-052).
    @discardableResult
    func renameFolder(at relativePath: String, to newName: String) -> String? {
        guard let session, canOperateOnFolder(relativePath) else { return nil }
        do {
            let outcome = try session.renameFolder(at: relativePath, to: newName)
            for failure in outcome.failures {
                recordProblem("riferimento non aggiornato: \(failure)")
            }
            for refusal in outcome.refusals {
                recordProblem(VaultWriteRefusal.movedOn(refusal).description)
            }
            for moved in outcome.movedNotes {
                movedNote(from: moved.old, to: moved.new)
            }
            // Covers renaming an *ancestor* folder (e.g. `01 Progetti` itself), which
            // orphans a descendant pratica the same way a move does (ADR-0026 §D7) -
            // `moveItems`' own `follow(_:)` hook does not run for a rename.
            didRelocateFolders?([MovedNote(old: relativePath, new: outcome.newPath)])
            Task { await rescan() }
            return outcome.newPath
        } catch {
            recordProblem("rinomina cartella: \(error)")
            return nil
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
            // The deletion twin of `renameFolder`'s `didRelocateFolders` call (ADR-0026 §D7,
            // 2026-09-19 amendment, PG-169). Trimmed the way `canOperateOnFolder` trims one
            // line above the `do`, so a caller that ever passes "F/" cannot leave a key
            // behind for the subscriber to miss.
            didTrashFolder?(relativePath.trimmingCharacters(in: .pathSlashes))
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
    /// `canOperateOnFolder` check - true of the *editor*, which holds no unsaved buffer
    /// on a `.canvas` at all, but false of the *app*: the open Workspace board holds
    /// unsaved edits to a `.canvas` for a second at a time, dozens of times a session.
    /// That race is real (ADR-0054 §D6) and this is where its refusal surfaces, not where
    /// it is prevented - `canOperateOnFolder`'s "ask before" shape does not apply to a
    /// board autosave nothing here schedules or waits on. No `movedNote` pass either,
    /// because renaming a board moves no note. What is left: report what could not be
    /// repointed and what refused because the board changed since the plan was read, then
    /// rescan so the browser tree rebuilds around the new name.
    @discardableResult
    func renameBoard(at relativePath: String, to newName: String) -> String? {
        guard let session else { return nil }
        do {
            let outcome = try session.renameBoard(at: relativePath, to: newName)
            for failure in outcome.failures {
                recordProblem("riferimento non aggiornato: \(failure)")
            }
            for refusal in outcome.refusals {
                recordProblem(VaultWriteRefusal.movedOn(refusal).description)
            }
            Task { await rescan() }
            return outcome.newPath
        } catch {
            recordProblem("rinomina board: \(error)")
            return nil
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

    /// Whether `name` is free inside `parent`, read-only - `true` with no vault open,
    /// matching every other "nothing to check yet" default in this file (PG-051).
    func nameIsAvailable(_ name: String, in parent: String) -> Bool {
        session?.nameIsAvailable(name, in: parent) ?? true
    }

    /// A folder's content counts (R-10), read-only - `nil` with no vault open or an
    /// unreadable folder, exactly as `FolderFileOperations.contentCounts` itself answers
    /// (PG-051).
    func contentCounts(at folder: String) -> (notes: Int, subfolders: Int)? {
        session?.contentCounts(at: folder)
    }
}
