import AppKit

/// A table column's menu (ADR-0087 §D11): the three alignments, the column's own one ticked, then
/// the two sorts, from `TableColumnMenu.entries(current:)`. The same menu is the column control's
/// (`editor-table-column-menu`, at `columnAnchor`) and each header cell's right-click. An entry
/// goes through `commit(_:)`, so it is one replacement and one undo step like every structural
/// button, and the alignment the column already has writes nothing.
extension TableGridView {
    /// Rebuilt on every `update(with:theme:)`: the ticked alignment is the table's current one.
    func refreshColumnMenus() {
        guard let table else { return }
        for (column, field) in (fields.first ?? []).enumerated() where column < table.alignments.count {
            field.menu = columnMenu(for: column, current: table.alignments[column])
        }
        columnMenuButton.menu = columnAnchor.flatMap { column in
            column < table.alignments.count ? columnMenu(for: column, current: table.alignments[column]) : nil
        }
    }

    @objc func columnMenuTapped(_ sender: NSButton) {
        // Rebuilt first: the anchor follows the cell last edited, which no update reports.
        refreshColumnMenus()
        guard let menu = sender.menu else { return }
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: sender.bounds.maxY), in: sender)
    }

    @objc func columnMenuChosen(_ item: NSMenuItem) {
        guard let column = item.representedObject as? Int, let table, column < table.alignments.count else { return }
        let entries = TableColumnMenu.entries(current: table.alignments[column])
        guard entries.indices.contains(item.tag),
              let edit = TableColumnMenu.edit(for: entries[item.tag], column: column)
        else { return }
        commit(edit)
    }

    private func columnMenu(for column: Int, current: GFMTable.Alignment) -> NSMenu {
        let menu = NSMenu()
        let entries = TableColumnMenu.entries(current: current)
        for (index, entry) in entries.enumerated() {
            if case .sort = entry, index > 0, case .align = entries[index - 1] { menu.addItem(.separator()) }
            let item = NSMenuItem(
                title: TableColumnMenu.title(of: entry), action: #selector(columnMenuChosen(_:)), keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.representedObject = column
            if case .align(_, isCurrent: true) = entry { item.state = .on }
            menu.addItem(item)
        }
        return menu
    }
}
