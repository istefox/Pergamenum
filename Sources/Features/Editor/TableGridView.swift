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
///
/// Split across three files, all `TableGridView` itself (`type_body_length` error, > 350
/// lines, size-only move): this file (class declaration, stored state, sizing, and the
/// `draw(_:)` override - which cannot live in an extension), `+Rendering` (rebuilding and
/// laying out the cells and control pills), and `+CellCommit` (the `NSTextFieldDelegate`
/// write path, the structural row/column buttons, and reading the grid back). Properties
/// below are `internal` rather than `private` wherever a sibling file needs them - Swift's
/// `private` is file-scoped, and a stored property can only be declared here.
final class TableGridView: NSView, NSTextFieldDelegate {
    enum Metrics {
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
    var table: GFMTable?
    /// Row 0 is the header; every later entry is a body row. Rebuilt only when the shape
    /// changes - a rebuild costs first responder, and a styling pass runs on every keystroke
    /// anywhere in the note.
    var fields: [[NSTextField]] = []
    var widths: [CGFloat] = []
    /// The rounded background each group's label-plus-buttons sits on, last computed by
    /// `layoutGrid()` and read back by `draw(_:)` - the same "layout writes, draw reads"
    /// split the grid lines already keep with `widths`. A filled pill per group, the Pages/
    /// Numbers/Keynote table-toolbar shape, replaced a bare 1px divider line that read as
    /// nothing next to the row of small icon buttons it was meant to separate.
    var rowPillRect: NSRect = .zero
    var columnPillRect: NSRect = .zero
    /// The cell last edited, which is what a structural button aims at.
    var focused: (row: Int, column: Int)?

    var gridColor: NSColor = .separatorColor
    var cellColor: NSColor = .labelColor
    var headerColor: NSColor = .secondaryLabelColor
    /// Opaque `labelColor`, not `tertiaryLabelColor` - the dim tint the icons themselves keep
    /// is fine for a glanced-at control, but the "Riga"/"Colonna" text exists specifically to
    /// be read, so it uses this instead.
    var controlColor: NSColor = .tertiaryLabelColor
    var controlLabelColor: NSColor = .labelColor
    /// The pill fill behind each group - `decorations.badgeBackground`'s own token
    /// (`.backgroundTertiary`), so a caption badge and this control group read as the same
    /// family of "quiet chrome" rather than two unrelated designs.
    var pillColor: NSColor = .clear
    /// The page's own body face, pushed in from `font.prose` by `update(with:theme:)` exactly
    /// the way the colours above are (ADR-0030 §D2/§D13): a table is part of the note, so its
    /// cells are drawn in the note's face rather than in the 13pt interface font this grid used
    /// before. The default is what a grid built and never updated draws with.
    var proseFont: NSFont = .systemFont(ofSize: 13)
    /// The same family's bold face, for the header row - `ProseTypography.proseBold` falls back
    /// to the upright face of the *right* family rather than to a bold of a different one, so a
    /// header never diverges from its own body cells.
    var proseBoldFont: NSFont = .systemFont(ofSize: 13, weight: .semibold)

    lazy var rowLabel = makeGroupLabel(text: "Riga", identifier: "editor-table-row-label")
    lazy var columnLabel = makeGroupLabel(text: "Colonna", identifier: "editor-table-column-label")
    lazy var addRowButton = makeControl(
        symbol: "plus.square", title: "+r", tooltip: "Aggiungi una riga",
        identifier: "editor-table-add-row", action: #selector(addRowTapped)
    )
    lazy var removeRowButton = makeControl(
        symbol: "minus.square", title: "-r", tooltip: "Rimuovi la riga",
        identifier: "editor-table-remove-row", action: #selector(removeRowTapped)
    )
    lazy var addColumnButton = makeControl(
        symbol: "plus.rectangle", title: "+c", tooltip: "Aggiungi una colonna",
        identifier: "editor-table-add-column", action: #selector(addColumnTapped)
    )
    lazy var removeColumnButton = makeControl(
        symbol: "minus.rectangle", title: "-c", tooltip: "Rimuovi la colonna",
        identifier: "editor-table-remove-column", action: #selector(removeColumnTapped)
    )
    var controlButtons: [NSButton] {
        [addRowButton, removeRowButton, addColumnButton, removeColumnButton]
    }
    var controlLabels: [NSTextField] { [rowLabel, columnLabel] }

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

    /// Grid lines and the "Riga"/"Colonna" pills, painted from what `+Rendering`'s
    /// `layoutGrid()` last computed (`widths`, `rowPillRect`, `columnPillRect`). Stays here,
    /// not in `+Rendering.swift`, because a superclass override cannot live in an extension.
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
}
