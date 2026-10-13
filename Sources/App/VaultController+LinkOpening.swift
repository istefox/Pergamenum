import Foundation

// ADR-0083 §D1, §D3, §D5, §D7 (PG-386, N3 session B). A file of its own because
// `VaultController+Tabs.swift`, where `openNote(at:)` and `addColumn()` are, is past the file-length
// warning.

/// The doors a followed link goes through once its target is a path, and the editor's report of the
/// link under the caret.
extension VaultController {
    /// Opens a note where the how says (ADR-0083 §D1): over the focused tab, in a tab of its own,
    /// or in the other column.
    func openNote(at relativePath: String, how: LinkOpening) {
        switch how {
        case .replace: openNote(at: relativePath)
        case .newTab: openNoteInNewTab(at: relativePath)
        case .otherColumn: openNoteInOtherColumn(at: relativePath)
        }
    }

    /// Opens a note in the other column (ADR-0083 §D1). With one column the second is added with
    /// `addColumn()`, not `splitEditor()`, which would copy the source note into it. The note lands
    /// in front of that column: a tab already showing it is focused rather than opened twice, and
    /// otherwise it gets a tab of its own, so what the other column was showing stays there.
    ///
    /// Not `openNote(at:)` alone (ADR-0083 §D1 as amended): its `show(_:)` would put the target
    /// over that column's preview tab, and the note the other column was showing would be gone.
    func openNoteInOtherColumn(at relativePath: String) {
        if columns.count == 1 { addColumn() }
        guard columns.count == 2 else { return }
        focusColumn(focusedColumnIndex == 0 ? 1 : 0)
        if tabs.contains(where: { $0.note.relativePath == relativePath }) {
            openNote(at: relativePath)
        } else {
            openNoteInNewTab(at: relativePath)
        }
    }

    /// Records the followable link under the caret in the front tab of one column (ADR-0083 §D3),
    /// in `recordOutlineEntry(_:inColumn:)`'s shape and for its reason: the report arrives from
    /// either column without moving the focus.
    func recordLinkAtCaret(_ url: URL?, inColumn columnIndex: Int) {
        guard columns.indices.contains(columnIndex),
              let id = columns[columnIndex].activeID,
              let index = columns[columnIndex].tabs.firstIndex(where: { $0.id == id }),
              columns[columnIndex].tabs[index].linkAtCaret != url
        else { return }
        columns[columnIndex].tabs[index].linkAtCaret = url
    }

    /// The followable link under the caret in the focused tab (ADR-0083 §D3).
    var linkAtCaret: URL? { focusedTab?.linkAtCaret }

    /// Where a `[[target]]` goes (ADR-0083 §D5): the index's answer for a title, the board
    /// resolver's `unique` answer for a `.canvas` name, through the one rule both feed.
    func linkDestination(for target: String) -> LinkDestination {
        LinkDestination.resolve(
            target,
            notePaths: { index.resolve(title: $0) },
            board: { name in
                guard let root else { return nil }
                guard case .unique(let path) = WorkspaceBoardResolver.resolve(
                    name, in: CanvasStore(root: root).allBoards()
                ) else { return nil }
                return path.value
            }
        )
    }

    /// What the Cmd+hover preview shows for a target (ADR-0083 §D7). An external address has
    /// none: it is not a title, whatever the index says about it.
    func linkPreviewContent(for target: String, section: String?) -> LinkPreviewContent? {
        if let url = MarkdownAttributedText.targetURL(for: target),
           case .external = MarkdownAttributedText.clickTarget(for: url) {
            return nil
        }
        // A board is named, not resolved: resolving walks every board in the vault, a disk-derived
        // list ADR-0072 §D7 forbids keeping across hovers (ADR-0083 §D7).
        let destination = LinkDestination.resolve(
            target, notePaths: { index.resolve(title: $0) }, board: { $0 }
        )
        return LinkPreviewContent.make(
            for: destination, section: section,
            noteText: { path in try? session?.read(path).text }
        )
    }
}
