import SwiftUI

/// Where a creation lands, and the create/rename/delete verbs (ADR-0022 §D10, ADR-0025
/// §D6/§D7/§D8). Split out of `WorkspaceBrowser.swift` to keep its `type_body_length` under
/// the configured warning threshold (PG-055) - a location split only, not a behavioural one.
extension WorkspaceBrowser {
    /// The folder a **creation** lands in: the selected row's own folder, which for a
    /// board row is the folder holding it, so a new board or folder is made *beside* what
    /// is selected rather than inside it (ADR-0025 §D7). `""` - the vault root - with
    /// nothing selected.
    ///
    /// The rule is asked here rather than restated: `selection?.folder ?? ""` would be a
    /// second spelling of `target(for:)` below, and two spellings of one rule are what
    /// R-06 is about in the first place.
    var targetFolder: String {
        Self.target(for: selection)
    }

    /// ADR-0025 §D7 / R-06: where a creation lands, read as one expression with no branch
    /// on which case the selection is - the whole content of "the toolbar cannot aim
    /// anywhere the visible row is not."
    ///
    /// `""` for nothing selected is the vault root, which is where a new board or folder
    /// belongs when no row says otherwise. Whether the two *mutating* verbs are offered
    /// at all is a different question with a different rule
    /// (`WorkspaceBrowserToolbar.canMutate(_:)`, §D8), asked of the selection rather than
    /// of this string - so nothing selected disables them there rather than aiming them
    /// here.
    static func target(for selection: WorkspaceSelection?) -> String {
        selection?.folder ?? ""
    }

    /// The collision predicate both sheets block on, live, so a name that is already
    /// taken is refused before anything is created rather than reported afterwards
    /// (ADR-0022 §D11, R-03).
    ///
    /// The same function the performing code guards with
    /// (`FolderFileOperations.nameIsAvailable`), read through `VaultController` (PG-051) -
    /// not a second spelling of the rule for the sheet to disagree with.
    func nameIsAvailable(_ name: String, in parent: String) -> Bool {
        vault.nameIsAvailable(name, in: parent)
    }

    /// The same predicate asked about the kind of thing being named (ADR-0025 §D7):
    /// `CanvasStore.boardNameIsAvailable` for a board, the folder rule above for a folder.
    /// Read by both sheets - a rename collides with exactly what a creation collides with.
    ///
    /// Two rules and not one, because the two collisions are different ones: a board is
    /// refused by a `.canvas` of that name and by nothing else, so a *folder* called
    /// `prova` does not stop a `prova.canvas` beside it (R-04) - a file and a directory
    /// may share a name in one directory, and the old fold is what made that look like a
    /// clash. A folder is still refused by anything of that name, file or directory,
    /// which is what `FolderFileOperations.nameIsAvailable` asks the file system.
    ///
    /// Each is the very function the performing verb guards with, so the sheet cannot
    /// enable a «Crea» that `createBoard`/`createFolder` will then refuse (ADR-0022 §D11).
    func nameIsAvailable(
        _ name: String, in parent: String, for kind: WorkspaceItemKind
    ) -> Bool {
        switch kind {
        case .board: canvasStore?.boardNameIsAvailable(name, in: parent) ?? true
        case .folder: nameIsAvailable(name, in: parent)
        }
    }

    // MARK: Verbs
    //
    // The browser decides, `WorkspaceView` performs (ADR-0022 §D10): create and rename
    // hand the sheet's answer straight to `actions`, which is where `flushPendingSave()`
    // and `open(board:)` bracket the vault call. Rename and delete both stop here first,
    // and for the row each one is about rather than for a decision - delete because how
    // much is inside a folder is a walk of its subtree, rename because the row is
    // whatever the click named. Each has a board arm and a folder arm, and the two never
    // share a verb: a board rename repoints nodes and rewrites markers where a folder
    // rename does neither (ADR-0025 §D6).

    /// Opens the rename sheet on the folder the caller names - the toolbar's target, or
    /// the row a context menu was opened on. Nothing here reads the selection back.
    func requestRename(of folder: String) {
        renameTarget = PendingWorkspaceRename(kind: .folder, path: folder)
    }

    /// The same, for a board row: the `.canvas` path the row drew (ADR-0025 §D6).
    func requestRenameBoard(of board: String) {
        renameTarget = PendingWorkspaceRename(kind: .board, path: board)
    }

    /// Reads the counts once, at the click, and shows the dialog (R-10). Once, rather
    /// than in the dialog's own body: `contentCounts` enumerates the whole subtree and a
    /// view body is evaluated as often as SwiftUI likes.
    func confirmDelete(of folder: String) {
        pendingDelete = .folder(path: folder, counts: vault.contentCounts(at: folder))
    }

    /// The same dialog for a board, with nothing to count: deleting one removes one file
    /// and leaves the folder holding it exactly as it was (ADR-0025 §D6).
    func confirmDeleteBoard(of board: String) {
        pendingDelete = .board(path: board)
    }

    /// The toolbar's «Rinomina», dispatched on the selection's case onto the same two
    /// entry points a row's context menu calls (ADR-0025 §D8).
    ///
    /// The `nil` arm is unreachable while the button is disabled by `canMutate(_:)`, and
    /// is written rather than forced: the two surfaces share the rule, not the guarantee
    /// that it was asked.
    func renameSelection() {
        switch selection {
        case .folder(let folder): requestRename(of: folder)
        case .board(let path): requestRenameBoard(of: path)
        case .none: break
        }
    }

    /// The toolbar's «Elimina», the same dispatch as `renameSelection()` above.
    func deleteSelection() {
        switch selection {
        case .folder(let folder): confirmDelete(of: folder)
        case .board(let path): confirmDeleteBoard(of: path)
        case .none: break
        }
    }
}
