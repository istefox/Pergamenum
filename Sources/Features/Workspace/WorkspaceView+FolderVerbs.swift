import Foundation

/// The Workspace sidebar's three verbs, performed here rather than in the browser
/// because all three need this view's `WorkspaceController` (ADR-0022 §D10).
extension WorkspaceView {
    var folderActions: WorkspaceFolderActions {
        WorkspaceFolderActions(
            create: { name, parent in createWorkspace(named: name, in: parent) },
            rename: { folder, newName in renameWorkspace(folder, to: newName) },
            delete: { folder in deleteWorkspace(folder) },
            recordDesync: { message in workspace.recordProblem(message) }
        )
    }

    /// Creates the folder, gives it its board, and opens it (R-02).
    ///
    /// `CanvasStore.createFolder(named:in:)` unchanged: it refuses a name that is taken
    /// and does not create intermediate directories, and the sheet has already blocked on
    /// both. The board file is written straight after because a workspace is a folder
    /// *with a board* - the sidebar tree is built from `allBoards()`, so a folder created
    /// without one would not appear in the pane it was created from.
    ///
    /// TODO(ADR-0025 Task 6): that second write is R-01's whole subject and Task 6
    /// **deletes** it, splitting this verb into "nuova board" and "nuova cartella"
    /// (§D7). Until then it is expressed as `createBoard(named:in:)` - the same file at
    /// the same path as the deleted `save(.empty, folder: created)` wrote, refusing
    /// rather than overwriting.
    ///
    /// Not expressed through `performFolderVerb` below: creation opens the folder it has
    /// just made, where the other two only follow the one that moved out from under them.
    private func createWorkspace(named name: String, in parent: String) {
        guard let root = vault.root else { return }
        flushBoard()
        do {
            let store = CanvasStore(root: root)
            let created = try store.createFolder(named: name, in: parent)
            _ = try store.createBoard(named: name, in: created)
            workspace.open(folder: created)
            Task { await vault.rescan() }
        } catch {
            // The board is still usable and the name can be retried, so this is a line in
            // the problem list rather than a modal - the same treatment the "Cartella"
            // tool gives a rejected name.
            vault.recordProblem("nuova workspace: \(error)")
        }
    }

    /// Renames the folder and keeps the open board on it (R-05, R-08).
    private func renameWorkspace(_ folder: String, to newName: String) {
        // The destination `FolderFileOperations.renamePlan` computed for itself: a rename
        // is a new last component under the same parent, never a move (SPEC, out of scope).
        let parent = (folder as NSString).deletingLastPathComponent
        let newPath = parent.isEmpty ? newName : "\(parent)/\(newName)"
        performFolderVerb(
            { vault.renameFolder(at: folder, to: newName) },
            landing: { open in
                WorkspaceFolderActions.folderAfterRename(
                    open: open, renamed: folder, to: newPath
                )
            }
        )
    }

    /// Trashes the folder and lands on its parent when what went was underfoot (R-11, R-12).
    ///
    /// The confirmation happened in the browser, which is where the counts are; by the
    /// time this runs the question has been answered.
    private func deleteWorkspace(_ folder: String) {
        performFolderVerb(
            { vault.trashFolder(at: folder) },
            landing: { open in
                WorkspaceFolderActions.folderAfterDelete(open: open, deleted: folder)
            }
        )
    }

    /// The shape a folder verb has, in the order it has to have it.
    ///
    /// The order is the whole of the decision: **flush first** - the board autosaves about
    /// a second after a change and that write would otherwise land on the old path,
    /// recreating the directory the rename moved or the delete trashed (§F10) - then the
    /// vault call, then the navigation rule that says where the open board goes next.
    /// Written once here so a third verb cannot copy one of the two and quietly get the
    /// order wrong.
    ///
    /// - Parameters:
    ///   - mutate: the vault call, returning whether it happened.
    ///   - landing: where the open board goes, given the folder it is on now.
    private func performFolderVerb(_ mutate: () -> Bool, landing: (String) -> String) {
        flushBoard()
        guard mutate() else { return }
        // Landing somewhere only means something if a board is actually open - with
        // nothing chosen there is nothing to move.
        guard workspace.isShowingBoard else { return }

        let destination = landing(workspace.folder)
        guard destination != workspace.folder else { return }
        // Reopened rather than moved in place: the document on screen was read from a
        // file that has moved, and `open(folder:)` is what re-reads it, refreshes the
        // folder's contents and redraws the breadcrumb from `workspace.folder`.
        workspace.open(folder: destination)
    }

    /// Everything the board still owes the disk, written now.
    ///
    /// The crop is ended before the flush rather than left to `open(folder:)`, which ends
    /// it on the way out (ADR-0020 §D5): confirming a crop is a `mutate`, and a `mutate`
    /// after the folder has moved is a write to a path that is no longer there - the
    /// autosave problem of §F10 arriving through the other door. Ended here, its write
    /// goes to the folder that still exists.
    private func flushBoard() {
        workspace.endCrop(confirm: true)
        workspace.flushPendingSave()
    }
}
