import Foundation

/// The Workspace sidebar's verbs, performed here rather than in the browser because they
/// all need this view's `WorkspaceController` (ADR-0022 §D10).
extension WorkspaceView {
    var folderActions: WorkspaceFolderActions {
        WorkspaceFolderActions(
            createBoard: { name, parent in createBoard(named: name.value, in: parent.value) },
            createFolder: { name, parent in createFolder(named: name.value, in: parent.value) },
            rename: { folder, newName in renameWorkspace(folder.value, to: newName.value) },
            delete: { folder in deleteWorkspace(folder.value) },
            renameBoard: { board, newName in renameBoard(board.value, to: newName.value) },
            deleteBoard: { board in deleteBoard(board.value) },
            move: { items, destination in moveItems(items, into: destination.value) },
            recordDesync: { message in workspace.recordProblem(message) }
        )
    }

    /// Moves a batch of rows into `destination` and keeps the open board on screen where
    /// it landed (R-01 … R-05, R-13). Answers with every reason the batch refused, empty
    /// when it committed - the browser has the dialog R-07 asks for.
    ///
    /// `performBoardVerb`'s bracket, and its first line for the same reason: **flush
    /// first**. The board autosaves about a second after a change, and that write would
    /// otherwise land on the pre-move path and recreate the file the move just relocated
    /// (ADR-0022 §F10, paid for once already by rename and delete). It is not expressed
    /// *through* `performBoardVerb` because a batch's landing rule takes the moves it
    /// performed rather than one path, and because a refusal has to travel back up.
    ///
    /// `VaultController.moveItems` asks `VaultMoveBatch.plan` once, internally, and hands
    /// back the full `MoveBatchOutcome` (PG-083) - this used to plan a second time here
    /// just to get the conflicting names and the moved list back, because the call
    /// answered only a `Bool`. Asking twice against the same disk in the same run-loop
    /// turn is gone along with the reason for it.
    ///
    /// The unsaved-note guard (ADR-0026 §D10) now runs *inside* `vault.moveItems`, before
    /// the plan: a batch that both trips it and collides on a name reports the unsaved
    /// note, not the collision. That guard has to be cleared before disk either way.
    private func moveItems(_ items: [VaultItemRef], into destination: String) -> [String] {
        flushBoard()
        // `undoManager` is the **window's**, read from the environment and handed down as
        // an argument (ADR-0026 §D8) - the same stack `NSTextView` registers text edits
        // on, so Cmd+Z means "undo the last thing I did in this window" whatever had
        // focus. Nil is not silently tolerated: `moveItems` records that the move cannot
        // be taken back.
        let outcome = vault.moveItems(items, into: destination, undo: undoManager)
        guard outcome.didMove else { return outcome.refusals + outcome.failures }
        // Landing somewhere only means something if a board is actually open - moving a
        // row that is merely selected in the tree moves no document on screen.
        guard workspace.isShowingBoard else { return [] }

        // `outcome.moves`, not a separately-planned list: an item that failed on disk
        // mid-batch is not in it, so the open board does not chase a path nothing wrote.
        let landed = WorkspaceFolderNavigation.boardAfterMove(open: workspace.board, moves: outcome.moves)
        guard landed != workspace.board else { return [] }
        // Reopened rather than left alone: the document on screen was read from a file
        // that has moved, and `open(board:)` is what re-reads it, refreshes the folder's
        // contents and redraws the breadcrumb - so the board never flickers closed (R-13).
        workspace.open(board: landed)
        return []
    }

    /// Writes a board and opens it, creating no folder (R-02).
    ///
    /// `CanvasStore.createBoard(named:in:)` refuses a `.canvas` the name already belongs
    /// to and creates no directory, and the sheet has already blocked on the collision -
    /// `parent` is a folder the tree drew, so it is there.
    ///
    /// Not expressed through `performFolderVerb` below: a creation opens the thing it has
    /// just made, where rename and delete only follow the one that moved out from under
    /// them.
    private func createBoard(named name: String, in parent: String) {
        guard let root = vault.root else { return }
        flushBoard()
        do {
            let created = try CanvasStore(root: root).createBoard(named: name, in: parent)
            workspace.open(board: created)
            Task { await vault.rescan() }
        } catch {
            // The board on screen is still usable and the name can be retried, so this is
            // a line in the problem list rather than a modal - the same treatment the
            // "Cartella" tool gives a rejected name.
            vault.recordProblem("nuova board: \(error)")
        }
    }

    /// Creates the folder and selects it. **It writes no board inside it** (R-01).
    ///
    /// That absence is the decision, not an omission: this verb used to run
    /// `save(.empty, folder: created)` straight after the directory, because the sidebar
    /// was built from `allBoards()` alone and a folder with nothing in it had no row to
    /// appear as. The tree is built from `allFolders()` *and* `allBoards()` now
    /// (ADR-0025 §D2), so an empty folder is a row of its own and the second write has
    /// nothing left to compensate for - it only ever produced a `.canvas` nobody asked
    /// for, named after its folder, which is the identification this chain removes.
    ///
    /// `select(.folder(created))` rather than `open(board:)`: there is no board to open,
    /// and the tag the tree lights for a folder row is the folder's own path (§D3).
    private func createFolder(named name: String, in parent: String) {
        guard let root = vault.root else { return }
        flushBoard()
        do {
            let created = try CanvasStore(root: root).createFolder(named: name, in: parent)
            workspace.select(.folder(created))
            Task { await vault.rescan() }
        } catch {
            vault.recordProblem("nuova cartella: \(error)")
        }
    }

    /// Renames the folder and keeps the open board on it (R-05, R-08).
    ///
    /// The destination is read from the rename outcome (PG-052) - `FolderFileOperations
    /// .renamePlan` already computed it, `normalized()` trim included, so this no longer
    /// keeps a second, looser spelling of the same rule beside it.
    private func renameWorkspace(_ folder: String, to newName: String) {
        performFolderVerb(
            { vault.renameFolder(at: folder, to: newName) },
            landing: { open, newPath in
                WorkspaceFolderNavigation.folderAfterRename(
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
            { vault.trashFolder(at: folder) ? folder : nil },
            landing: { open, deleted in
                WorkspaceFolderNavigation.folderAfterDelete(open: open, deleted: deleted)
            }
        )
    }

    /// Renames the board file and follows it when it is the one on screen (R-08).
    ///
    /// The destination is read from the rename outcome (PG-052), the same as
    /// `renameWorkspace` above - `BoardFileOperations.renamePlan` already computes the
    /// new file name under the same folder.
    private func renameBoard(_ board: String, to newName: String) {
        performBoardVerb(
            { vault.renameBoard(at: board, to: newName) },
            landing: { open, newPath in
                WorkspaceFolderNavigation.boardAfterRename(open: open, renamed: board, to: newPath)
            }
        )
    }

    /// Trashes the board file and lands on its folder when what went was on screen (R-08).
    ///
    /// The confirmation happened in the browser; by the time this runs the question has
    /// been answered.
    private func deleteBoard(_ board: String) {
        performBoardVerb(
            { vault.trashBoard(at: board) ? board : nil },
            landing: { open, deleted in
                WorkspaceFolderNavigation.boardAfterDelete(open: open, deleted: deleted)
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
    ///   - mutate: the vault call, answering with whatever the landing rule needs (a
    ///     destination path, PG-052) or `nil` if it refused.
    ///   - landing: where the open board goes, given the folder it is on now and what
    ///     `mutate` answered with.
    private func performFolderVerb<T>(_ mutate: () -> T?, landing: (_ open: String, _ result: T) -> String) {
        flushBoard()
        guard let result = mutate() else { return }
        // Landing somewhere only means something if a board is actually open - with
        // nothing chosen there is nothing to move.
        guard workspace.isShowingBoard else { return }

        let destination = landing(workspace.folder, result)
        guard destination != workspace.folder else { return }
        // A board is a file with a name of its own (ADR-0025 §D1), so it follows its
        // folder under that name rather than being derived from where the folder landed.
        // Reopened rather than moved in place: the document on screen was read from a
        // file that has moved, and `open(board:)` is what re-reads it, refreshes the
        // folder's contents and redraws the breadcrumb.
        let fileName = (workspace.board as NSString).lastPathComponent
        let moved = destination.isEmpty ? fileName : "\(destination)/\(fileName)"
        guard let store = workspace.store, FileManager.default.fileExists(
            atPath: store.url(forBoard: moved).path(percentEncoded: false)
        ) else {
            // Nothing followed: a delete put the board in the Trash, so the surviving
            // parent is selected and no board is drawn - the answer §D5 gives a folder
            // that has no board, rather than a reopen that would only report a miss.
            workspace.select(destination.isEmpty ? nil : .folder(destination))
            return
        }
        workspace.open(board: moved)
    }

    /// The shape a **board** verb has, in the same order and for the same reason.
    ///
    /// `flushBoard()` first, exactly as above: the ~1s autosave would otherwise land on
    /// the path the rename just moved away from and write the file back into existence
    /// (ADR-0022 §F10) - or, after a delete, resurrect from the Trash something the user
    /// asked to throw away.
    ///
    /// What differs from `performFolderVerb` is only the landing, and it is simpler: the
    /// rule answers with a whole `WorkspaceSelection` rather than with a folder path to
    /// reconstruct a file name under, because a board *is* the path (ADR-0025 §D3). The
    /// root's `.folder("")` selects nothing: the vault root is the list itself and has no
    /// row of its own (§D2), so there is nothing there to light.
    ///
    /// - Parameters:
    ///   - mutate: the vault call, answering with whatever the landing rule needs (a
    ///     destination path, PG-052) or `nil` if it refused.
    ///   - landing: where the selection goes, given the board that is open now and what
    ///     `mutate` answered with.
    private func performBoardVerb<T>(
        _ mutate: () -> T?, landing: (_ open: String, _ result: T) -> WorkspaceSelection
    ) {
        flushBoard()
        guard let result = mutate() else { return }
        // Landing somewhere only means something if a board is actually open - a rename
        // of one that is merely selected in the tree moves no document on screen.
        guard workspace.isShowingBoard else { return }

        switch landing(workspace.board, result) {
        case .board(let path):
            // Reopened rather than left alone: the document on screen was read from a file
            // that has moved, and `open(board:)` is what re-reads it, refreshes the
            // folder's contents and redraws the breadcrumb.
            guard path != workspace.board else { return }
            workspace.open(board: path)
        case .folder(let folder):
            workspace.select(folder.isEmpty ? nil : .folder(folder))
        }
    }

    /// Everything the board still owes the disk, written now.
    ///
    /// The crop is ended before the flush rather than left to `open(board:)`, which ends
    /// it on the way out (ADR-0020 §D5): confirming a crop is a `mutate`, and a `mutate`
    /// after the folder has moved is a write to a path that is no longer there - the
    /// autosave problem of §F10 arriving through the other door. Ended here, its write
    /// goes to the folder that still exists.
    private func flushBoard() {
        workspace.endCrop(confirm: true)
        workspace.flushPendingSave()
    }
}
