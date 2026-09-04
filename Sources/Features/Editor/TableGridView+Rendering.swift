import AppKit
import SwiftUI

/// The reshape/apply/layout pass for `TableGridView` (ADR-0029 §D4/§D6/§D7) - the
/// styling-pass entry point (`update(with:theme:)`) plus everything it calls to keep the
/// `NSTextField` grid and the "Riga"/"Colonna" control pills in sync with the table's shape.
/// `draw(_:)` stays in `TableGridView.swift` instead of here, because a superclass override
/// cannot live in an extension.
extension TableGridView {
    /// Redraws the grid for `table`, keeping the cells - and therefore first responder -
    /// wherever the shape allows it.
    ///
    /// Called from the Coordinator's own table pass on every styling pass, which is every
    /// keystroke anywhere in the note. The two things that make that affordable are here:
    /// the fields are rebuilt only when the number of rows or columns changed, and a cell
    /// currently being typed into is never written over.
    ///
    /// Colours arrive as theme tokens, pushed in the way `decorations.badgeColor` and
    /// `decorations.handleColor` already are - a view that uses a colour without going
    /// through a token does not pass review (CLAUDE.md).
    func update(with table: GFMTable, theme: Theme) {
        gridColor = NSColor(theme.color(.borderSubtle))
        cellColor = NSColor(theme.color(.textPrimary))
        headerColor = NSColor(theme.color(.textSecondary))
        controlColor = NSColor(theme.color(.textTertiary))
        controlLabelColor = NSColor(theme.color(.textPrimary))
        pillColor = NSColor(theme.color(.backgroundTertiary))
        for label in controlLabels { label.textColor = controlLabelColor }

        let reshaped = self.table.map {
            $0.header.count != table.header.count || $0.rows.count != table.rows.count
        } ?? true
        // Read before the rebuild, which is what would drop it.
        let regainsFocus = reshaped && isEditingACell
        let previous = focused

        self.table = table
        if reshaped { rebuildFields() }
        applyCellValues()
        applyColours()
        layoutGrid()
        if regainsFocus { restoreFocus(near: previous) }
    }

    private func rebuildFields() {
        for field in fields.flatMap({ $0 }) { field.removeFromSuperview() }
        fields = []
        guard let table, !table.header.isEmpty else { return }
        for row in 0...table.rows.count {
            var line: [NSTextField] = []
            for _ in 0..<table.header.count {
                let field = makeCell(isHeader: row == 0)
                addSubview(field)
                line.append(field)
            }
            fields.append(line)
        }
        // Tab and Shift-Tab between cells come from AppKit walking this chain, both ways -
        // `previousKeyView` is set implicitly by assigning `nextKeyView`, which is what makes
        // Shift-Tab need no code of its own here.
        let flat = fields.flatMap { $0 }
        for (index, field) in flat.enumerated() where index + 1 < flat.count {
            field.nextKeyView = flat[index + 1]
        }
    }

    private func makeCell(isHeader: Bool) -> NSTextField {
        let field = NSTextField(string: "")
        field.delegate = self
        field.isBordered = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.font = NSFont.systemFont(ofSize: 13, weight: isHeader ? .semibold : .regular)
        field.setAccessibilityIdentifier(isHeader ? "editor-table-header-cell" : "editor-table-cell")
        return field
    }

    private func applyCellValues() {
        guard let table else { return }
        for (rowIndex, line) in fields.enumerated() {
            let values = rowIndex == 0 ? table.header : table.rows[rowIndex - 1]
            for (columnIndex, field) in line.enumerated() where columnIndex < values.count {
                field.alignment = Self.alignment(table.alignments[columnIndex])
                // Never over a cell being typed into: a styling pass fires on every SwiftUI
                // update of the pane, and writing the note's value back mid-word would take
                // the word with it.
                guard field.currentEditor() == nil else { continue }
                if field.stringValue != values[columnIndex] { field.stringValue = values[columnIndex] }
            }
        }
    }

    private func applyColours() {
        for (rowIndex, line) in fields.enumerated() {
            for field in line { field.textColor = rowIndex == 0 ? headerColor : cellColor }
        }
        for button in controlButtons { button.contentTintColor = controlColor }
        needsDisplay = true
    }

    private func layoutGrid() {
        widths = computedWidths()
        var y: CGFloat = 0
        for line in fields {
            var x: CGFloat = 0
            for (columnIndex, field) in line.enumerated() {
                let width = columnIndex < widths.count ? widths[columnIndex] : Metrics.minimumColumn
                field.frame = NSRect(
                    x: x + Metrics.cellInset, y: y,
                    width: max(1, width - Metrics.cellInset * 2), height: Metrics.rowHeight
                )
                x += width
            }
            y += Metrics.rowHeight
        }
        // Flush with the grid's own left edge (x=0, the leftmost vertical grid line) rather
        // than centred under it - the row of pills reads as belonging to the table only when
        // it starts where the table itself starts.
        var x: CGFloat = 0
        // "Riga" [+][-]  ␣  "Colonna" [+][-] - the label goes in front of the pair it names,
        // not above or below it, so no second line is needed and the row stays `controlRow`
        // tall regardless of which font the system hands back for it.
        (x, rowPillRect) = layout(label: rowLabel, buttons: [addRowButton, removeRowButton], startingAt: x, y: y)
        x += Metrics.controlGroupGap
        (_, columnPillRect) = layout(
            label: columnLabel, buttons: [addColumnButton, removeColumnButton], startingAt: x, y: y
        )
        invalidateIntrinsicContentSize()
        setFrameSize(intrinsicContentSize)
    }

    /// Places one group's label followed by its buttons, left to right, and returns both the
    /// x just past the last button - what the caller needs to place the next group - and the
    /// padded bounding pill `draw(_:)` fills behind the whole group.
    private func layout(
        label: NSTextField, buttons: [NSButton], startingAt startX: CGFloat, y: CGFloat
    ) -> (nextX: CGFloat, pill: NSRect) {
        var x = startX + Metrics.pillPadding
        // `NSTextField.intrinsicContentSize` measures the string a hair narrower than the
        // cell actually needs to draw its last glyph without truncating - the same rounding
        // `Self.width(of:weight:)` never hits because a table cell has room to spare.
        let labelWidth = label.intrinsicContentSize.width + Metrics.labelWidthSlop
        label.frame = NSRect(
            x: x, y: y + (Metrics.controlRow - label.intrinsicContentSize.height) / 2,
            width: labelWidth, height: label.intrinsicContentSize.height
        )
        x += labelWidth + Metrics.controlLabelGap
        for button in buttons {
            button.frame = NSRect(
                x: x, y: y + Metrics.controlGap,
                width: Metrics.controlSide, height: Metrics.controlSide
            )
            x += Metrics.controlSide + Metrics.controlGap * 2
        }
        let pill = NSRect(
            x: startX, y: y + Metrics.pillVerticalInset,
            width: x - startX + Metrics.pillPadding, height: Metrics.controlRow - Metrics.pillVerticalInset * 2
        )
        return (x + Metrics.pillPadding, pill)
    }

    /// One width per column, from the widest cell in it - clamped at both ends so a column of
    /// empty cells is still clickable and a paragraph-length cell truncates instead of
    /// pushing the rest of the table off the side of the editor.
    private func computedWidths() -> [CGFloat] {
        guard let table else { return [] }
        return table.header.indices.map { column in
            var widest = Self.width(of: table.header[column], weight: .semibold)
            for row in table.rows where column < row.count {
                widest = max(widest, Self.width(of: row[column], weight: .regular))
            }
            return min(Metrics.maximumColumn, max(Metrics.minimumColumn, widest + Metrics.cellInset * 2))
        }
    }

    private static func width(of text: String, weight: NSFont.Weight) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return (text as NSString)
            .size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: weight)])
            .width
    }

    private static func alignment(_ column: GFMTable.Alignment) -> NSTextAlignment {
        switch column {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
    }
}
