import Foundation

/// The pause check behind the unsaved mark (ADR-0095 §D3 and §D4, PG-406).
extension VaultController {
    /// Clears the mark of every tab, in every column, whose text is back to what the disk holds.
    ///
    /// Every tab and not only the one typed in: a tab undone back to its saved text and left for
    /// the other column would otherwise keep its dot. A tab whose mark is off is not asked, and a
    /// tab still dirty is not written back, so a pause over dirty buffers mutates nothing and
    /// invalidates no view.
    func settleUnsavedMarks() {
        for columnIndex in columns.indices {
            for tabIndex in columns[columnIndex].tabs.indices
            where columns[columnIndex].tabs[tabIndex].note.hasUnsavedChanges {
                unsavedMarkChecks += 1
                var note = columns[columnIndex].tabs[tabIndex].note
                if note.settleUnsavedMark() {
                    columns[columnIndex].tabs[tabIndex].note = note
                }
            }
        }
    }
}
