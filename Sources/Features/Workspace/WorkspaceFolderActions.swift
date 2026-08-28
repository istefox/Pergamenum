import Foundation

/// The Workspace sidebar's verbs - two creations, a rename and a delete for each of the
/// two kinds of row - and the two navigation rules they need once the disk has moved on
/// (ADR-0022 §D10, ADR-0025 §D7).
///
/// A value carrying closures rather than a type with behaviour: the browser decides
/// *when* a verb runs, `WorkspaceView` performs it. They all need the
/// `WorkspaceController` - `flushPendingSave()` before anything touches disk, or the
/// ~1s autosave lands on the old path afterwards and recreates what was just renamed
/// away (§F10), and `open(board:)` after, so the board follows what moved - and the
/// browser has no business holding that controller.
///
/// The four rules below are static and pure on purpose. Where the open board lands after
/// a rename or a delete is a question about two paths: it needs no controller, no vault
/// and no view, and `Tests/WorkspaceFolderNavigationTests.swift` asks it that way.
struct WorkspaceFolderActions {
    /// Writes a board called `<name>.canvas` inside `parent` and opens it (R-02).
    let createBoard: (_ name: String, _ parent: String) -> Void

    /// Creates a folder called `name` inside `parent` and selects it, **writing no board
    /// inside it** (R-01, ADR-0025 §D7).
    ///
    /// Two closures rather than one that branches, and the pairing with `createBoard`
    /// above is the point: they were one verb because a workspace was a folder *with a
    /// board named after it*, which is the identification this chain removes. A caller
    /// asks for the thing it wants, and neither verb makes the other's thing on the side.
    let createFolder: (_ name: String, _ parent: String) -> Void

    /// Renames `folder` to `newName`, keeping the open board on it (R-05, R-08).
    let rename: (_ folder: String, _ newName: String) -> Void

    /// Moves `folder` to the Trash. The caller has already confirmed: this does not ask
    /// (R-11, R-12).
    let delete: (_ folder: String) -> Void

    /// The same two verbs for a **board** file, by its own vault-relative `.canvas` path
    /// (ADR-0025 §D6, R-08). Separate closures rather than one that branches: a board
    /// rename repoints nodes and rewrites markers where a folder rename does neither, and
    /// the row that raises them already knows which kind it is.
    ///
    /// `(board, newName)` is `rename`'s own shape: the sheet asks for the name and the
    /// browser hands both across, so the extension is added in exactly one place
    /// (`BoardFileOperations.renamePlan`) and `newName` never carries one.
    let renameBoard: (_ board: String, _ newName: String) -> Void

    /// Moves the `.canvas` at `board` to the Trash. The caller has already confirmed:
    /// this does not ask - `delete`'s contract, for a file rather than a directory.
    let deleteBoard: (_ board: String) -> Void

    /// Moves `items` into `destination` - a folder path, the vault root spelled `""`
    /// (R-05) - and answers with what the batch **refused**, empty when it committed
    /// (ADR-0026 §D6, §D9).
    ///
    /// Refusals come back rather than being reported from inside, because R-07 asks for
    /// the conflicting name to be *shown*: the browser is the side with a dialog, and the
    /// strings are `VaultMoveBatch.plan`'s own, which already name the path that stopped
    /// the batch.
    ///
    /// One closure for both surfaces - a folder row's drop and «Sposta in» in every row's
    /// context menu - because they are two renderings of one command (ADR-0023 §D1).
    let move: (_ items: [VaultItemRef], _ destination: String) -> [String]

    /// Records a non-modal problem the browser found on its own, the same visible channel
    /// `WorkspaceController.recordProblem` already gives rename/delete (ADR-0022 §F-note) -
    /// so a tree/click desync (a `.tag`ed id the tree no longer resolves, e.g. a rescan
    /// racing the click) leaves a trace instead of silently reading as an ordinary
    /// board-less folder (ADR-0024 Gate 5.06 finding).
    let recordDesync: (_ message: String) -> Void

    /// Where the open board should point once `renamed` has become `to`: unchanged
    /// outside the renamed subtree, exact-substituted when `open` *is* `renamed`, and
    /// prefix-substituted when it sits inside it (R-08, ADR-0022 §D10 - "`workspace.folder`
    /// is the renamed folder or sits under it").
    ///
    /// The prefix tested is `<renamed>/` and never `<renamed>`, the same rule
    /// `FolderFileOperations.repointing` follows and for the same reason: a sibling
    /// folder called `a-altro` starts with the same characters as `a` and has nothing to
    /// do with this rename.
    static func folderAfterRename(open: String, renamed: String, to: String) -> String {
        if open == renamed { return to }
        guard open.hasPrefix("\(renamed)/") else { return open }
        return to + String(open.dropFirst(renamed.count))
    }

    /// Where the open board should land once `deleted` has been trashed: the deleted
    /// folder's own parent when the open board is it or sits under it, unchanged
    /// otherwise (R-12, ADR-0022 §D10 - "the nearest surviving parent, which always
    /// survives").
    ///
    /// The parent of a folder directly under the vault root is `""`, which is the root's
    /// own board - always there, since the root is the one folder this feature cannot
    /// delete (R-09).
    static func folderAfterDelete(open: String, deleted: String) -> String {
        guard open == deleted || open.hasPrefix("\(deleted)/") else { return open }
        return (deleted as NSString).deletingLastPathComponent
    }

    /// Where the open selection should point once `renamed` has become `to`: unchanged when
    /// the open board is not the one being renamed, `.board(path: to)` when it is (R-08,
    /// ADR-0025 §D6 - "after a board rename, if the open board is the renamed one,
    /// `open(board: newPath)`").
    ///
    /// Unlike `folderAfterRename`, there is no prefix case: a board is a file, not a
    /// directory, so nothing can sit "inside" it. One comparison, and the equality is the
    /// whole rule.
    static func boardAfterRename(open: String, renamed: String, to: String) -> WorkspaceSelection {
        .board(path: open == renamed ? to : open)
    }

    /// Where the open selection should land once `deleted` has been trashed: unchanged when
    /// the open board is not the one deleted, `.folder(containing)` when it is (R-09,
    /// ADR-0025 §D6 - "after a board delete, if the open board was the deleted one,
    /// `select(.folder(containing))`").
    ///
    /// The containing folder of a board at the vault root is `""`, which is the root
    /// itself - the one folder this feature cannot delete, so the landing always exists
    /// (`folderAfterDelete`'s own argument, for a file).
    static func boardAfterDelete(open: String, deleted: String) -> WorkspaceSelection {
        guard open == deleted else { return .board(path: open) }
        return .folder((deleted as NSString).deletingLastPathComponent)
    }

    /// Where the open board should land once a drag-move batch has completed: unchanged
    /// when `open` is none of the moved items, exact-substituted when `open` *is* one of
    /// them, prefix-substituted when it sits inside a moved folder (R-13, ADR-0026 §D10).
    ///
    /// A pure function over `[VaultMove]` rather than one move, because a batch can carry
    /// several items in one drop and the open board only ever matches at most one of
    /// them - the first match answers, and looking further would be looking for a second
    /// one that cannot exist (an item and its own ancestor are never both in a batch,
    /// `VaultMoveBatch.plan` rule 1).
    ///
    /// The prefix tested is `<moved>/` and never `<moved>`, `folderAfterRename`'s rule
    /// above and `FolderFileOperations.repointing`'s: a sibling called `a-altro` starts
    /// with the same characters as `a` and has nothing to do with this move.
    static func boardAfterMove(open: String, moves: [VaultMove]) -> String {
        for move in moves {
            // Where this item landed: its own last component inside `move.to`, because a
            // move never renames (ADR-0026 §D5, "reject means reject").
            let name = (move.item.path as NSString).lastPathComponent
            let moved = move.to.isEmpty ? name : "\(move.to)/\(name)"
            if open == move.item.path { return moved }
            if open.hasPrefix("\(move.item.path)/") {
                return moved + String(open.dropFirst(move.item.path.count))
            }
        }
        return open
    }
}
