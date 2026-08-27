import Foundation

/// The three folder verbs of the Workspace sidebar, and the two navigation rules they
/// need once the disk has moved on (ADR-0022 §D10).
///
/// A value carrying closures rather than a type with behaviour: the browser decides
/// *when* a verb runs, `WorkspaceView` performs it. All three need the
/// `WorkspaceController` - `flushPendingSave()` before anything touches disk, or the
/// ~1s autosave lands on the old path afterwards and recreates what was just renamed
/// away (§F10), and `open(board:)` after, so the board follows what moved - and the
/// browser has no business holding that controller.
///
/// The two rules below are static and pure on purpose. Where the open board lands after
/// a rename or a delete is a question about two paths: it needs no controller, no vault
/// and no view, and `Tests/WorkspaceFolderNavigationTests.swift` asks it that way.
struct WorkspaceFolderActions {
    /// Creates a folder called `name` inside `parent` and opens its board (R-02).
    let create: (_ name: String, _ parent: String) -> Void

    /// Renames `folder` to `newName`, keeping the open board on it (R-05, R-08).
    let rename: (_ folder: String, _ newName: String) -> Void

    /// Moves `folder` to the Trash. The caller has already confirmed: this does not ask
    /// (R-11, R-12).
    let delete: (_ folder: String) -> Void

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
}
