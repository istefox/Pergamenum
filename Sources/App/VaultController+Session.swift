import Foundation

/// Remembering the arrangement, and finding it again (ADR-0012 D10).
extension VaultController {
    /// Writes the arrangement down, so the next launch finds it (ADR-0012 D10).
    ///
    /// Called by every door that changes which tabs exist or which is in front. Not by
    /// `updateTab`: typing does not rearrange anything, and the buffer is not what is kept.
    ///
    /// Internal rather than private only because the doors are in the other file, which is
    /// where the stored `columns` has to be.
    func rememberTabs() {
        guard let root else { return }
        openTabs.remember(
            OpenTabsStore.Session(
                columns: columns.map { column in
                    .init(
                        entries: column.tabs.map {
                            .init(path: $0.note.relativePath, isPreview: $0.isPreview)
                        },
                        activePath: column.active?.note.relativePath
                    )
                },
                focusedColumn: focusedColumnIndex
            ),
            for: root
        )
    }

    /// Reopens what was open when this vault was last closed.
    ///
    /// A note that is no longer there is skipped rather than reported: it was deleted between
    /// two launches, which is not a failure, and a dialog about it at every start would be.
    func restoreTabs() {
        guard let root, tabs.isEmpty else { return }
        let session = openTabs.session(for: root)
        for (index, column) in session.columns.enumerated() {
            // The first column exists already; the second is made only if the session had one,
            // so a desk that was not split does not come back split.
            if index > 0 { addColumn() }
            focusColumn(index)
            for entry in column.entries {
                guard let note = readForEditing(entry.path) else { continue }
                openTab(showing: note)
                if entry.isPreview, let id = focusedTab?.id { updateTab(id) { $0.isPreview = true } }
            }
            if let active = column.activePath,
               let tab = tabs.first(where: { $0.note.relativePath == active }) {
                focusTab(tab.id)
            }
        }
        focusColumn(session.focusedColumn)
    }
}
