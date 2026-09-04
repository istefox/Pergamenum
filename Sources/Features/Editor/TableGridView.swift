import AppKit
import SwiftUI

/// The GFM table grid (ADR-0029 §D4/§D6/§D7; plan `2026-09-02-editor-wysiwyg-unification`,
/// Task 4/5) - an `NSView` behind `NSTextAttachmentViewProvider`, created and owned on the
/// main actor by `TableGridStore` and handed to `TableAttachment` as a finished value.
///
/// One `NSTextField` per cell, laid out by hand rather than by Auto Layout: the shape changes
/// with every add/remove row and column, and a constraint set rebuilt each time is a second
/// description of a geometry that is already fully determined by the table's own cells. The
/// same reason `intrinsicContentSize` is computed here rather than read off a fitting size -
/// `TableAttachment` asks for it while laying out the line the grid has not been placed in
/// yet (§D16 probe 3).
///
/// **Nothing here writes to the note.** A commit is a `TableEdit` handed to `onCommit`, which
/// the Coordinator turns into one `replaceAtomically` over the table's whole source range -
/// so a structural edit is one `Cmd+Z` whatever moved (§D7), and this view never learns what
/// an `NSTextStorage` is.
final class TableGridView: NSView, NSTextFieldDelegate {
    private enum Metrics {
        static let rowHeight: CGFloat = 24
        /// Breathing room inside a cell, on each side - the grid lines are drawn at the
        /// column's own edges, so this is what keeps the text off them.
        static let cellInset: CGFloat = 6
        static let minimumColumn: CGFloat = 72
        /// Wider than this and a cell truncates rather than pushing the note's own column
        /// off the side - `MarkdownBlocksView.table`'s own bargain, one surface over.
        static let maximumColumn: CGFloat = 220
        static let controlSide: CGFloat = 18
        static let controlGap: CGFloat = 3
        static let controlRow: CGFloat = 24
        /// The gap on each side of a group's text label, between it and the pair of buttons
        /// it names.
        static let controlLabelGap: CGFloat = 4
        /// The gap between the row group and the column group, wider than `controlGap` on
        /// purpose - `plus.square`/`minus.square` and `plus.rectangle`/`minus.rectangle` read
        /// nearly identically at 18pt, so a "Riga"/"Colonna" text label in front of each pair
        /// (plus the divider `draw(_:)` paints at this gap's midpoint) is what actually says
        /// which is which without a hover - a first pass at this used spacing and a dim
        /// tertiary-tinted divider alone, both too faint to read at a glance.
        static let controlGroupGap: CGFloat = 14
        /// Horizontal breathing room between a pill's own edge and the label/buttons it
        /// holds - the same reason `cellInset` exists for a cell's own text.
        static let pillPadding: CGFloat = 6
        static let pillVerticalInset: CGFloat = 2
        static let pillCornerRadius: CGFloat = 6
        static let labelWidthSlop: CGFloat = 3
    }

    /// Called on Tab from the last cell, Enter, and Escape - the return path to the enclosing
    /// `CompletingTextView`, set by `TableGridStore` when the grid is built, the same
    /// closure-ownership shape `onEmbedResize` already uses: "this view has exactly one
    /// owner, and a closure makes that owner's identity a non-issue" (ADR §D6).
    var resignToTextView: (() -> Void)?
    /// One committed edit on its way to the note's own characters, answering whether it was
    /// written. `false` is a real answer and not a failure to report: D8's reload guard
    /// refuses a commit whose table has moved, and a cell whose edit was refused is put back
    /// to what the note still says rather than left showing a value nothing holds.
    var onCommit: ((TableEdit) -> Bool)?

    /// The table this grid is currently drawing, as of the last styling pass.
    private var table: GFMTable?
    /// Row 0 is the header; every later entry is a body row. Rebuilt only when the shape
    /// changes - a rebuild costs first responder, and a styling pass runs on every keystroke
    /// anywhere in the note.
    private var fields: [[NSTextField]] = []
    private var widths: [CGFloat] = []
    /// The rounded background each group's label-plus-buttons sits on, last computed by
    /// `layoutGrid()` and read back by `draw(_:)` - the same "layout writes, draw reads"
    /// split the grid lines already keep with `widths`. A filled pill per group, the Pages/
    /// Numbers/Keynote table-toolbar shape, replaced a bare 1px divider line that read as
    /// nothing next to the row of small icon buttons it was meant to separate.
    private var rowPillRect: NSRect = .zero
    private var columnPillRect: NSRect = .zero
    /// The cell last edited, which is what a structural button aims at.
    private var focused: (row: Int, column: Int)?

    private var gridColor: NSColor = .separatorColor
    private var cellColor: NSColor = .labelColor
    private var headerColor: NSColor = .secondaryLabelColor
    /// Opaque `labelColor`, not `tertiaryLabelColor` - the dim tint the icons themselves keep
    /// is fine for a glanced-at control, but the "Riga"/"Colonna" text exists specifically to
    /// be read, so it uses this instead.
    private var controlColor: NSColor = .tertiaryLabelColor
    private var controlLabelColor: NSColor = .labelColor
    /// The pill fill behind each group - `decorations.badgeBackground`'s own token
    /// (`.backgroundTertiary`), so a caption badge and this control group read as the same
    /// family of "quiet chrome" rather than two unrelated designs.
    private var pillColor: NSColor = .clear
    /// The page's own body face, pushed in from `font.prose` by `update(with:theme:)` exactly
    /// the way the colours above are (ADR-0030 §D2/§D13): a table is part of the note, so its
    /// cells are drawn in the note's face rather than in the 13pt interface font this grid used
    /// before. The default is what a grid built and never updated draws with.
    private var proseFont: NSFont = .systemFont(ofSize: 13)
    /// The same family's bold face, for the header row - `ProseTypography.proseBold` falls back
    /// to the upright face of the *right* family rather than to a bold of a different one, so a
    /// header never diverges from its own body cells.
    private var proseBoldFont: NSFont = .systemFont(ofSize: 13, weight: .semibold)

    private lazy var rowLabel = makeGroupLabel(text: "Riga", identifier: "editor-table-row-label")
    private lazy var columnLabel = makeGroupLabel(text: "Colonna", identifier: "editor-table-column-label")
    private lazy var addRowButton = makeControl(
        symbol: "plus.square", title: "+r", tooltip: "Aggiungi una riga",
        identifier: "editor-table-add-row", action: #selector(addRowTapped)
    )
    private lazy var removeRowButton = makeControl(
        symbol: "minus.square", title: "-r", tooltip: "Rimuovi la riga",
        identifier: "editor-table-remove-row", action: #selector(removeRowTapped)
    )
    private lazy var addColumnButton = makeControl(
        symbol: "plus.rectangle", title: "+c", tooltip: "Aggiungi una colonna",
        identifier: "editor-table-add-column", action: #selector(addColumnTapped)
    )
    private lazy var removeColumnButton = makeControl(
        symbol: "minus.rectangle", title: "-c", tooltip: "Rimuovi la colonna",
        identifier: "editor-table-remove-column", action: #selector(removeColumnTapped)
    )
    private var controlButtons: [NSButton] {
        [addRowButton, removeRowButton, addColumnButton, removeColumnButton]
    }
    private var controlLabels: [NSTextField] { [rowLabel, columnLabel] }

    override init(frame: NSRect) {
        super.init(frame: frame)
        // R-05's UI test (`DesignAndReadingUITests`) finds the grid by this identifier, never
        // by the words in a cell - the working agreement every UI test in this repo keeps
        // ("prose grows").
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Tabella")
        setAccessibilityIdentifier("editor-table")
        for label in controlLabels { addSubview(label) }
        for button in controlButtons { addSubview(button) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Top-down, so a row's index and its `y` grow together and the layout arithmetic below
    /// reads the way the table does.
    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let cells = widths.reduce(0, +)
        let rows = CGFloat(max(fields.count, 1)) * Metrics.rowHeight
        return NSSize(
            width: max(max(cells, controlsWidth), Metrics.minimumColumn),
            height: rows + Metrics.controlRow
        )
    }

    private var controlsWidth: CGFloat {
        Metrics.controlGroupGap
            + groupWidth(labelWidth: rowLabel.intrinsicContentSize.width + Metrics.labelWidthSlop, buttonCount: 2)
            + groupWidth(labelWidth: columnLabel.intrinsicContentSize.width + Metrics.labelWidthSlop, buttonCount: 2)
    }

    /// The width of one pill: padding on both sides, its label, the gap before the buttons,
    /// then the buttons themselves - the one formula `controlsWidth` (before layout) and
    /// `layout(label:buttons:startingAt:y:)` (during layout) both have to agree on, so it is
    /// written once here rather than kept in sync by hand in two places.
    private func groupWidth(labelWidth: CGFloat, buttonCount: Int) -> CGFloat {
        Metrics.pillPadding * 2 + labelWidth + Metrics.controlLabelGap
            + CGFloat(buttonCount) * (Metrics.controlSide + Metrics.controlGap * 2)
    }

    // MARK: Drawing what the note says

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
        // Before the rebuild below, so a cell made by `makeCell` is born with the right face
        // rather than corrected a line later - and read again on every update, because a theme
        // change reaches a grid whose shape has not moved and so is never rebuilt.
        proseFont = ProseTypography.prose(theme)
        proseBoldFont = ProseTypography.proseBold(theme)

        let reshaped = self.table.map {
            $0.header.count != table.header.count || $0.rows.count != table.rows.count
        } ?? true
        // Read before the rebuild, which is what would drop it.
        let regainsFocus = reshaped && isEditingACell
        let previous = focused

        self.table = table
        if reshaped { rebuildFields() }
        applyCellValues()
        applyFonts()
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
        field.font = isHeader ? proseBoldFont : proseFont
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

    /// The counterpart of `applyColours()` for the faces: `makeCell` sets one on a cell it
    /// creates, and a rebuild only happens when the *shape* changed - so without this, a theme
    /// whose `font.prose` moved would repaint a table in the right colour and the wrong face
    /// until somebody added a row.
    private func applyFonts() {
        for (rowIndex, line) in fields.enumerated() {
            for field in line { field.font = rowIndex == 0 ? proseBoldFont : proseFont }
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
        // `width(of:isHeader:)` never hits because a table cell has room to spare.
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
            var widest = width(of: table.header[column], isHeader: true)
            for row in table.rows where column < row.count {
                widest = max(widest, width(of: row[column], isHeader: false))
            }
            return min(Metrics.maximumColumn, max(Metrics.minimumColumn, widest + Metrics.cellInset * 2))
        }
    }

    /// How wide a cell's text is *in the face that cell is drawn in* - `isHeader` rather than a
    /// weight, and an instance method rather than a static one, precisely so the two cannot
    /// diverge: measuring at a fixed 13pt while drawing at the theme's own `font.prose` sizes
    /// every column for a page nobody is looking at (ADR-0030 §D2, R-13).
    private func width(of text: String, isHeader: Bool) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return (text as NSString)
            .size(withAttributes: [.font: isHeader ? proseBoldFont : proseFont])
            .width
    }

    private static func alignment(_ column: GFMTable.Alignment) -> NSTextAlignment {
        switch column {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !fields.isEmpty, !widths.isEmpty else { return }
        gridColor.setFill()
        let totalWidth = widths.reduce(0, +)
        let totalHeight = CGFloat(fields.count) * Metrics.rowHeight
        for row in 0...fields.count {
            let y = min(CGFloat(row) * Metrics.rowHeight, totalHeight - 1)
            NSRect(x: 0, y: y, width: totalWidth, height: 1).fill()
        }
        var x: CGFloat = 0
        for width in widths {
            NSRect(x: x, y: 0, width: 1, height: totalHeight).fill()
            x += width
        }
        NSRect(x: totalWidth - 1, y: 0, width: 1, height: totalHeight).fill()

        // The "Riga"/"Colonna" pills - a filled, gently-bordered rounded rect per group, the
        // Pages/Numbers/Keynote table-toolbar shape. A first pass tried a single 1px divider
        // line between the two groups and it read as nothing next to the icons it was meant
        // to separate; grouping by an actual background, the way the rest of macOS groups a
        // named pair of controls, is what reads at a glance instead of only on hover.
        guard controlButtons.count == 4 else { return }
        for pill in [rowPillRect, columnPillRect] {
            let path = NSBezierPath(
                roundedRect: pill, xRadius: Metrics.pillCornerRadius, yRadius: Metrics.pillCornerRadius
            )
            pillColor.setFill()
            path.fill()
            gridColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    // MARK: Committing a cell

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

    // MARK: The structural affordances

    @objc private func addRowTapped() { commit(.addRow(after: rowAnchor)) }

    @objc private func removeRowTapped() {
        guard let row = rowAnchor else { return }
        commit(.removeRow(row))
    }

    @objc private func addColumnTapped() { commit(.addColumn(after: columnAnchor)) }

    @objc private func removeColumnTapped() {
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

    // MARK: Reading the grid back

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

    private var isEditingACell: Bool {
        fields.contains { line in line.contains { $0.currentEditor() != nil } }
    }

    private func restoreFocus(near previous: (row: Int, column: Int)?) {
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
    private func makeControl(
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
    private func makeGroupLabel(text: String, identifier: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        label.textColor = controlLabelColor
        label.setAccessibilityElement(false)
        label.setAccessibilityIdentifier(identifier)
        return label
    }
}
