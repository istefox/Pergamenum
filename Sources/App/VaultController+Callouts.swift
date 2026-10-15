import Foundation

extension VaultController {
    /// Flips one callout's fold in the focused tab (ADR-0087 §D8), keyed by its title line's UTF-16
    /// offset - `toggleFold`'s shape. A view of the note, not part of it: the file is not dirtied.
    func toggleCallout(_ offset: Int) {
        updateFocusedTab { tab in
            if tab.toggledCallouts.contains(offset) {
                tab.toggledCallouts.remove(offset)
            } else {
                tab.toggledCallouts.insert(offset)
            }
        }
    }

    /// Replaces the flipped callouts of one column's front tab with the offsets an edit moved them
    /// to (ADR-0091 §D6): the tab's text is written to the same tab, and its title offsets must
    /// follow it.
    ///
    /// By column, never through the focused facade, in `recordOutlineEntry(_:inColumn:)`'s shape:
    /// the report comes from the editor whose text changed, and a programmatic edit (an undo after
    /// the focus moved, a replacement batch) can post it from a column that is not the focused one.
    func setToggledCallouts(_ offsets: Set<Int>, inColumn columnIndex: Int) {
        guard columns.indices.contains(columnIndex),
              let id = columns[columnIndex].activeID,
              let index = columns[columnIndex].tabs.firstIndex(where: { $0.id == id })
        else { return }
        columns[columnIndex].tabs[index].toggledCallouts = offsets
    }
}
