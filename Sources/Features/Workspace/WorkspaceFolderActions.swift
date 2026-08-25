import Foundation

/// The two navigation rules Task 7's GREEN wiring needs after a rename or a delete
/// (ADR-0022 §D10), kept pure so they are testable without `WorkspaceController` or a
/// view.
///
/// **RED placeholder.** This task (the tester, dispatched ahead of the coder per
/// ADR-0049 §D1) declares the signatures so the target builds; the bodies below are
/// deliberately wrong and `Tests/WorkspaceFolderNavigationTests.swift` is red on their
/// assertions. The coder's GREEN work adds the `create(name:parent:)`,
/// `rename(folder:to:)` and `delete(folder:)` closures ADR-0022 §D10 describes, wires
/// `WorkspaceView`'s `flushPendingSave()`-then-vault-call-then-navigate sequencing, and
/// the delete `.confirmationDialog` - none of that belongs in this file yet.
struct WorkspaceFolderActions {
    /// Where the open board should point once `renamed` has become `to`: unchanged
    /// outside the renamed subtree, exact-substituted when `open` *is* `renamed`, and
    /// prefix-substituted when it sits inside it (R-08, ADR-0022 §D10 - "`workspace.folder`
    /// is the renamed folder or sits under it").
    ///
    /// PLACEHOLDER (RED): returns `open` unchanged.
    static func folderAfterRename(open: String, renamed: String, to: String) -> String {
        open
    }

    /// Where the open board should land once `deleted` has been trashed: the deleted
    /// folder's own parent when the open board is it or sits under it, unchanged
    /// otherwise (R-12, ADR-0022 §D10 - "the nearest surviving parent, which always
    /// survives").
    ///
    /// PLACEHOLDER (RED): returns `open` unchanged.
    static func folderAfterDelete(open: String, deleted: String) -> String {
        open
    }
}
