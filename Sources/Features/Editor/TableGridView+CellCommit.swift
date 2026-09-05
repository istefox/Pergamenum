import AppKit

/// The `NSTextFieldDelegate` write path for `TableGridView` (ADR-0029 §D4/§D6/§D7): committing
/// a cell edit, the structural row/column buttons, and reading the grid's current state back
/// (which cell is focused, what a control's original value was). Kept together because the
/// commit path and the read-back helpers call into each other constantly.
extension TableGridView {
    func controlTextDidBeginEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        focused = position(of: field)
    }

    /// The one place a cell edit becomes a commit: Tab, Shift-Tab, Enter and losing focus all
    /// end the field editor's session and arrive here, so there is a single write path rather
    /// than four that agree today (§D7).
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              let position = position(of: field), let table
        else { return }
        let current = value(at: position, in: table)
        guard field.stringValue != current else { return }
        let row: Int? = position.row == 0 ? nil : position.row - 1
        let edit = TableEdit.cell(row: row, column: position.column, text: field.stringValue)
        guard onCommit?(edit) == true else {
            // Refused by D8's reload guard: the note is what it was, so the cell says what
            // the note says. Leaving the typed value on screen would be a grid claiming an
            // edit that is in no file.
            field.stringValue = current
            return
        }
    }

    /// Tab from the last cell, Shift-Tab from the first, Enter and Escape - the four that
    /// leave the grid. Every other selector is handed back to AppKit, which is what walks the
    /// `nextKeyView` chain built in `rebuildFields()` and needs no help here.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let flat = fields.flatMap { $0 }
        switch selector {
        case #selector(NSResponder.insertTab(_:)):
            guard control === flat.last else { return false }
            resignToTextView?()
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            guard control === flat.first else { return false }
            resignToTextView?()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            // Enter commits and leaves, rather than inserting a newline a GFM cell cannot
            // hold: a row is a line, so a cell with a `\n` in it is not a cell.
            resignToTextView?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            restoreValue(of: control)
            resignToTextView?()
            return true
        default:
            return false
        }
    }

    @objc func addRowTapped() { commit(.addRow(after: rowAnchor)) }

    @objc func removeRowTapped() {
        guard let row = rowAnchor else { return }
        commit(.removeRow(row))
    }

    @objc func addColumnTapped() { commit(.addColumn(after: columnAnchor)) }

    @objc func removeColumnTapped() {
        guard let column = columnAnchor else { return }
        commit(.removeColumn(column))
    }

    /// Which body row a structural edit is aimed at: the one last edited, or - with the caret
    /// in the header row or nowhere in this grid at all - the last one, so a click with
    /// nothing focused adds at the end rather than silently at the top.
    private var rowAnchor: Int? {
        if let focused, focused.row > 0 { return focused.row - 1 }
        guard let table, !table.rows.isEmpty else { return nil }
        return table.rows.count - 1
    }

    private var columnAnchor: Int? {
        if let focused { return focused.column }
        guard let table, !table.header.isEmpty else { return nil }
        return table.header.count - 1
    }

    private func commit(_ edit: TableEdit) {
        // A cell still being typed into commits first. Clicking a button does not end a field
        // editor's session by itself, so without this the structural edit would be computed
        // against a table the pending cell has not reached yet - and then the cell's own
        // commit would arrive second and be refused for a shape that had moved under it.
        window?.endEditing(for: nil)
        _ = onCommit?(edit)
    }

    private func position(of control: NSControl) -> (row: Int, column: Int)? {
        for (rowIndex, line) in fields.enumerated() {
            if let columnIndex = line.firstIndex(where: { $0 === control }) {
                return (rowIndex, columnIndex)
            }
        }
        return nil
    }

    private func value(at position: (row: Int, column: Int), in table: GFMTable) -> String {
        let values: [String]
        if position.row == 0 {
            values = table.header
        } else {
            guard position.row - 1 < table.rows.count else { return "" }
            values = table.rows[position.row - 1]
        }
        guard position.column < values.count else { return "" }
        return values[position.column]
    }

    private func restoreValue(of control: NSControl) {
        guard let field = control as? NSTextField,
              let position = position(of: field), let table
        else { return }
        field.stringValue = value(at: position, in: table)
    }

    /// Read by `+Rendering`'s `update(with:theme:)` to decide whether a reshape needs to
    /// restore first responder afterward.
    var isEditingACell: Bool {
        fields.contains { line in line.contains { $0.currentEditor() != nil } }
    }

    /// Called by `+Rendering`'s `update(with:theme:)` right after a reshape that dropped first
    /// responder, to put it back as close as possible to where it was.
    func restoreFocus(near previous: (row: Int, column: Int)?) {
        guard let previous, !fields.isEmpty else { return }
        let row = min(previous.row, fields.count - 1)
        guard !fields[row].isEmpty else { return }
        let column = min(previous.column, fields[row].count - 1)
        window?.makeFirstResponder(fields[row][column])
    }

    /// A borderless square button, tinted from a token and kept out of the cells' own Tab
    /// chain: `refusesFirstResponder` is what stops Tab from a cell landing on a button
    /// instead of on the next cell.
    ///
    /// The title is a fallback for a symbol the running system does not have, rather than a
    /// second design: a button with neither image nor title is a button nobody can find.
    ///
    /// Called from the base file's own lazy button properties, which is why this cannot stay
    /// `private`.
    func makeControl(
        symbol: String, title: String, tooltip: String, identifier: String, action: Selector
    ) -> NSButton {
        let button: NSButton
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) {
            button = NSButton(image: image, target: self, action: action)
        } else {
            button = NSButton(title: title, target: self, action: action)
        }
        button.isBordered = false
        button.bezelStyle = .accessoryBarAction
        button.toolTip = tooltip
        button.refusesFirstResponder = true
        button.setAccessibilityLabel(tooltip)
        button.setAccessibilityIdentifier(identifier)
        return button
    }

    /// A static, non-editable, non-selectable text label ("Riga"/"Colonna") naming the pair
    /// of buttons that follows it - not a fifth `NSControl` in the Tab chain, and not itself
    /// an accessibility element (`isAccessibilityElement(false)`): `controlButtons` already
    /// carry the same name as their tooltip/accessibility label, so a screen reader would
    /// otherwise hear it twice.
    ///
    /// Called from the base file's own lazy label properties, which is why this cannot stay
    /// `private`.
    func makeGroupLabel(text: String, identifier: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        label.textColor = controlLabelColor
        label.setAccessibilityElement(false)
        label.setAccessibilityIdentifier(identifier)
        return label
    }
}
