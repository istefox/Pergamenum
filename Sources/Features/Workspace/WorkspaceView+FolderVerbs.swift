import Foundation

/// The Workspace sidebar's verbs, performed here rather than in the browser because they
/// all need this view's `WorkspaceController` (ADR-0022 §D10).
extension WorkspaceView {
    var folderActions: WorkspaceFolderActions {
        WorkspaceFolderActions(
            createBoard: { name, parent in createBoard(named: name, in: parent) },
            createFolder: { name, parent in createFolder(named: name, in: parent) },
            rename: { folder, newName in renameWorkspace(folder, to: newName) },
            delete: { folder in deleteWorkspace(folder) },
            renameBoard: { board, newName in renameBoard(board, to: newName) },
            deleteBoard: { board in deleteBoard(board) },
            move: { items, destination in moveItems(items, into: destination) },
            recordDesync: { message in workspace.recordProblem(message) }
        )
    }

    /// Moves a batch of rows into `destination` and keeps the open board on screen where
    /// it landed (R-01 … R-05, R-13). Answers with what the batch refused, empty when it
    /// committed - the browser has the dialog R-07 asks for.
    ///
    /// `performBoardVerb`'s bracket, and its first line for the same reason: **flush
    /// first**. The board autosaves about a second after a change, and that write would
    /// otherwise land on the pre-move path and recreate the file the move just relocated
    /// (ADR-0022 §F10, paid for once already by rename and delete). It is not expressed
    /// *through* `performBoardVerb` because a batch's landing rule takes the moves it
    /// performed rather than one path, and because a refusal has to travel back up.
    ///
    /// `VaultMoveBatch.plan` is asked here for what to **say** and again inside
    /// `VaultSession.moveItems` for what to **do**. One function asked twice in the same
    /// run-loop turn against the same disk, never a second rule: `VaultController
    /// .moveItems` reports its refusals to the problem list and answers `Bool`, and R-07
    /// needs the conflicting name in a dialog. The moves it returns are also what
    /// `boardAfterMove` needs, which the `Bool` cannot carry either.
    private func moveItems(_ items: [VaultItemRef], into destination: String) -> [String] {
        flushBoard()
        guard let session = vault.session else { return [] }
        let planned: [VaultMove]
        switch VaultMoveBatch.plan(items, into: destination, exists: { session.exists($0) }) {
        case .refused(let reasons): return reasons
        case .moves(let moves): planned = moves
        }
        // `undoManager` is the **window's**, read from the environment and handed down as
        // an argument (ADR-0026 §D8) - the same stack `NSTextView` registers text edits
        // on, so Cmd+Z means "undo the last thing I did in this window" whatever had
        // focus. Nil is not silently tolerated: `moveItems` records that the move cannot
        // be taken back.
        guard vault.moveItems(items, into: destination, undo: undoManager) else { return [] }
        // Landing somewhere only means something if a board is actually open - moving a
        // row that is merely selected in the tree moves no document on screen.
        guard workspace.isShowingBoard else { return [] }

        let landed = WorkspaceFolderActions.boardAfterMove(open: workspace.board, moves: planned)
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

    /// Renames the board file and follows it when it is the one on screen (R-08).
    private func renameBoard(_ board: String, to newName: String) {
        // The destination `BoardFileOperations.renamePlan` computes for itself: a new file
        // name under the same folder, with the extension added there rather than here so
        // the check and the write cannot disagree about which file they mean.
        let folder = (board as NSString).deletingLastPathComponent
        let fileName = "\(newName).\(CanvasStore.fileExtension)"
        let newPath = folder.isEmpty ? fileName : "\(folder)/\(fileName)"
        performBoardVerb(
            { vault.renameBoard(at: board, to: newName) },
            landing: { open in
                WorkspaceFolderActions.boardAfterRename(open: open, renamed: board, to: newPath)
            }
        )
    }

    /// Trashes the board file and lands on its folder when what went was on screen (R-08).
    ///
    /// The confirmation happened in the browser; by the time this runs the question has
    /// been answered.
    private func deleteBoard(_ board: String) {
        performBoardVerb(
            { vault.trashBoard(at: board) },
            landing: { open in
                WorkspaceFolderActions.boardAfterDelete(open: open, deleted: board)
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
    ///   - mutate: the vault call, returning whether it happened.
    ///   - landing: where the selection goes, given the board that is open now.
    private func performBoardVerb(
        _ mutate: () -> Bool, landing: (String) -> WorkspaceSelection
    ) {
        flushBoard()
        guard mutate() else { return }
        // Landing somewhere only means something if a board is actually open - a rename
        // of one that is merely selected in the tree moves no document on screen.
        guard workspace.isShowingBoard else { return }

        switch landing(workspace.board) {
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
