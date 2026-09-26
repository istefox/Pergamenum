import Foundation

/// What the tabs do after their note's file moved or went away.
///
/// Moved out of `VaultController+Tabs.swift` unchanged when ADR-0064 §D4's door took that file
/// past SwiftLint's 400 lines (ADR-0045's shape: a pure move into an extension of the same type).
extension VaultController {
    /// Follows a renamed or moved note in every tab that was showing it.
    ///
    /// Not "the open note" any more: before tabs there was one buffer to put back in step,
    /// and a rename now has to reach a note sitting in a tab nobody is looking at, or that
    /// tab keeps a path with no file behind it. Every column, not only the focused one: the
    /// same note can be open in both.
    func movedNote(from oldPath: String, to newPath: String) {
        // The recent list is paths, so a rename has to be followed here too - the same
        // follow-up `VaultSession.moveStar` performs for the star.
        if let index = recentNotePaths.firstIndex(of: oldPath) { recentNotePaths[index] = newPath }
        guard columns.contains(where: { $0.tabs.contains { $0.note.relativePath == oldPath } }),
              let note = readForEditing(newPath)
        else { return }
        updateTabs(showing: oldPath) { $0 = $0.showing(note) }
    }

    /// Closes every tab showing a note that is no longer there, in every column.
    func trashedNote(at relativePath: String) {
        // Ids first, then close: removing a tab shifts the indices a loop over the columns
        // would still be walking.
        let ids = columns.flatMap { column in
            column.tabs.filter { $0.note.relativePath == relativePath }.map(\.id)
        }
        closeTabs(ids, ofVanishedNote: relativePath)
    }

    /// Closes the given tabs because their note's file is gone: the one place a tab closes for
    /// that reason (ADR-0064 §D4).
    ///
    /// An in-app trash (`trashedNote(at:)`), an external deletion of a clean tab's file
    /// (`reconcile(_:)`) and «Scarta ed elimina» all come here, so the three cannot drift.
    /// The path leaves `closedTabPaths` and `recentNotePaths` even when `ids` is empty: a note
    /// that is gone is not one to offer back with Cmd+Shift+T, nor one to list among the recent
    /// ones - both would be a row that opens nothing.
    func closeTabs(_ ids: [NoteTab.ID], ofVanishedNote relativePath: String) {
        for id in ids {
            closeTab(id)
        }
        closedTabPaths.removeAll { $0 == relativePath }
        recentNotePaths.removeAll { $0 == relativePath }
    }
}
