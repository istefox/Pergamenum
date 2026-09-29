import AppKit

/// A table the editor is drawing right now: the grid vended for it and the shape that grid
/// was built from, as of the last styling pass.
///
/// Declared beside the table half rather than in `NoteTextView+Coordinator.swift` for the
/// reason `EmbedDrag` is declared beside the resize gesture: the three phases that fill, read
/// and clear it are all in this file, and the stored property that holds them is only a place
/// to keep a value between two of them.
struct DrawnTable {
    let grid: TableGridView
    let table: GFMTable
}

/// The Coordinator's own half of the table grid (ADR-0029 §D5/§D6/§D7/§D8; plan
/// `2026-09-02-editor-wysiwyg-unification`, Task 4/5): the entry point `applyStyling` calls by
/// name, and the commit that writes a cell back into the note's own characters. The pass and
/// its state are `TableBlockController`'s, below (ADR-0071 §D2/§D5).
///
/// The commit is on the exact model `NoteTextView+EmbedCaret.swift`'s
/// `replaceAtomically(_:with:in:)` already set: one atomic
/// `shouldChangeText`/`beginEditing`/`replaceCharacters`/`endEditing` write, never a second
/// path, so a structural table edit is one `Cmd+Z` regardless of which cell moved.
extension NoteTextView.Coordinator {
    // MARK: The styling pass (ADR §D5/§D6)

    /// `TableBlockController.apply(to:runs:markers:commit:)`, kept here under the name
    /// `applyStyling` calls in its sequence (ADR-0071 §D5). A grid commits through
    /// `commitTable`, which stays on the Coordinator because it owns no state.
    func applyTables(to textView: NSTextView, runs: [NSRange], markers: inout [Int: [HiddenMarker]]) {
        tables.apply(to: textView, runs: runs, markers: &markers) { [weak self] edit, header, textView in
            self?.commitTable(edit, at: header, in: textView) ?? false
        }
    }

    // MARK: The commit (ADR §D7/§D8)

    /// Applies `edit` to the table whose header paragraph starts at `offset`, and writes the
    /// result back over the table's own source range - `false`, the buffer left untouched,
    /// when the table is not there to write over any more.
    ///
    /// **D8's reload guard, and what it is measured against.** A grid holds a shape read by a
    /// *styling* pass; a commit happens in a later one, and between them the buffer may have
    /// been replaced wholesale - an FSEvents reload, «Ricarica da disco», or `updateNSView`'s
    /// own `textView.string = text`. So nothing parsed is carried across: the table is re-read
    /// from the live characters here, and it is checked against the note as the *model* still
    /// spells it (`parent.text`, the binding the editor was last given). Those two agree on
    /// every ordinary keystroke - `textDidChange` writes the buffer straight back through the
    /// binding - and disagree exactly when the buffer has moved on under the grid, which is
    /// the case this guard exists for. A shape that no longer matches, or a table that has
    /// moved off `offset` entirely, refuses the commit rather than writing over the wrong
    /// lines; the next styling pass rebuilds the grid from whatever the new text says.
    ///
    /// `replaceAtomically(_:with:in:)` is the only mechanism this write may use (ADR-0019
    /// §D7's precedent) and its own stale-range check is the second lock behind this one.
    @discardableResult
    func commitTable(_ edit: TableEdit, at offset: Int, in textView: NSTextView) -> Bool {
        guard parent.hidesMarkup else { return false }
        guard let recorded = EditorDecorationDelegate.tableRun(
            in: parent.text as NSString, atParagraphStart: offset
        ),
            let live = EditorDecorationDelegate.tableRun(
                in: textView.string as NSString, atParagraphStart: offset
            ),
            live.table.header.count == recorded.table.header.count,
            live.table.rows.count == recorded.table.rows.count,
            live.range == recorded.range
        else { return false }

        let edited = edit.applied(to: live.table)
        // An edit `TableEdit` refused - the last column, the last body row, an index that no
        // longer exists - comes back as the table it was given, and a table that did not
        // change is not a write. Without this, Cmd+Z would have a step in it that undoes
        // nothing (R-08 is about one step per *change*, not one per click).
        guard edited != live.table else { return false }
        return Self.replaceAtomically(live.range, with: edited.serialised(), in: textView)
    }
}

// MARK: - The controller (ADR-0071 §D2/§D3)

/// The table half's state and passes (ADR-0029 §D5/§D6): the styling pass that recognises a
/// table and vends its grid, the grid refresh after `endEditing`, and the caret rescue a row
/// leaving the layout needs.
///
/// It holds no Coordinator (ADR-0071 §D3): the view's inputs come through `parent`, read at the
/// moment a pass uses them, and the commit a grid calls is handed in by `applyTables`.
@MainActor
final class TableBlockController {
    /// Read when a pass runs, never captured earlier (ADR-0071 §D3).
    private let parent: () -> NoteTextView?
    private let decorations: EditorDecorationDelegate

    /// The grid every table on screen is drawn with, by table identity (ADR-0029 §D6) - owned
    /// here for the reason `Coordinator.embeds` is: `EditorDecorationDelegate` cannot be
    /// `@MainActor` and so cannot build an `NSView`, and it is handed finished values through
    /// `decorations.apply(tableViews:)`. Grew out of the Step 4.5 tracer-bullet probe's single
    /// fixed `tableProbeGrid`, which answered §D16 probe 2 and is gone.
    let grids = TableGridStore()
    /// Each table on screen and the grid drawing it, by header offset - filled by `apply`
    /// inside the storage's editing transaction and read by `refresh` once it has closed.
    private(set) var drawn: [Int: DrawnTable] = [:]
    /// The delimiter and body rows already taken out of the layout, so an unchanged set does
    /// not re-invalidate it on every keystroke - the table pass's own change check, which
    /// `applyFolding`'s early return does not cover (§D5).
    private(set) var hiddenRows: Set<Int> = []
    /// Where the caret has to go once that transaction closes, when a row it was sitting in
    /// has just left the layout (`rescueCaret`'s table twin, §D5).
    private(set) var pendingCaret: Int?

    init(parent: @escaping () -> NoteTextView?, decorations: EditorDecorationDelegate) {
        self.parent = parent
        self.decorations = decorations
    }

    /// Registers everything a table needs drawn, from the `.tableRun` spans `applyStyling`
    /// has just walked: the header line's own `.table` marker, the delimiter and body rows
    /// that leave the layout, and one `TableGridView` per table.
    ///
    /// **Its own guard and its own change check**, because `applyFolding`'s early return does
    /// not cover tables and `apply(tableRows:)` is a fifth input that must never be merged
    /// into the fold's own set (§D5). `markers` is `inout` because the header's marker
    /// belongs in the same table `applyStyling` is about to hand over: a second
    /// `apply(hiddenMarkers:)` call would be a second producer on one setter, which is
    /// precisely what the delegate's own header forbids.
    ///
    /// With `hidesMarkup` off this registers nothing and clears what it registered before -
    /// D9's escape hatch, which has to reach the enumeration refusal too or the body rows
    /// would stay out of the layout with the pipes visible above them.
    ///
    /// `commit` is what a grid's `onCommit` calls with the header offset, i.e.
    /// `Coordinator.commitTable(_:at:in:)`.
    func apply(
        to textView: NSTextView, runs: [NSRange], markers: inout [Int: [HiddenMarker]],
        commit: @escaping (TableEdit, Int, NSTextView) -> Bool
    ) {
        guard parent()?.hidesMarkup == true else {
            clear()
            return
        }

        let text = textView.string as NSString
        var found: [(header: Int, table: GFMTable)] = []
        var rows: Set<Int> = []
        var headerOfRow: [Int: Int] = [:]

        for run in runs {
            guard NSMaxRange(run) <= text.length,
                  let recognised = EditorDecorationDelegate.tableRun(in: text, atParagraphStart: run.location)
            else { continue }
            let header = run.location
            // The header's own pipes are the marker; the delimiter and body rows are the
            // hidden lines (`HiddenBlockLines`, ADR-0071 §D8).
            let walked = HiddenBlockLines(text: text, anchor: header, range: recognised.range, kind: .table)
            guard let marker = walked.marker else { continue }
            markers[header, default: []].append(marker)
            found.append((header, recognised.table))
            for row in walked.starts {
                rows.insert(row)
                headerOfRow[row] = header
            }
        }

        let views = grids.views(for: found.map(\.header), in: textView)
        decorations.apply(tableViews: views)
        var drawn: [Int: DrawnTable] = [:]
        for entry in found {
            guard let grid = views[entry.header] else { continue }
            // Re-set on every pass rather than once at build time: the closure carries the
            // header offset, and an edit above the table moves it. A grid holding last
            // pass's offset would commit against a range that has since become someone
            // else's - which D8's guard would refuse, correctly and uselessly.
            grid.onCommit = { [weak textView] edit in
                guard let textView else { return false }
                return commit(edit, entry.header, textView)
            }
            drawn[entry.header] = DrawnTable(grid: grid, table: entry.table)
        }
        self.drawn = drawn

        guard rows != hiddenRows else { return }
        hiddenRows = rows
        decorations.apply(tableRows: rows)
        pendingCaret = caretRescue(in: textView, rows: rows, headers: headerOfRow)
    }

    /// Draws each grid the note currently holds, and takes the caret out of a row that has
    /// just left the layout.
    ///
    /// **After `storage.endEditing()`, never inside it.** Both halves reach outside the text
    /// storage - a grid resizes itself, and a caret rescue moves the selection - and doing
    /// either while an editing transaction is open asks TextKit to lay out a document it has
    /// been told is mid-change.
    func refresh(in textView: NSTextView, theme: Theme) {
        for table in drawn.values {
            table.grid.update(with: table.table, theme: theme)
        }
        guard let offset = pendingCaret else { return }
        pendingCaret = nil
        CaretRescue.place(offset, in: textView)
    }

    /// `rescueCaret(in:from:)`'s table twin (§D5): a caret inside a row that has just become
    /// hidden is an insertion point with nowhere to be drawn and nowhere to type. It goes to
    /// the table's own header offset, which is where a person would look for it - and where
    /// the grid is. The rule itself is `CaretRescue.target`'s; the owner is the header.
    private func caretRescue(
        in textView: NSTextView, rows: Set<Int>, headers: [Int: Int]
    ) -> Int? {
        CaretRescue.target(
            for: textView.selectedRange(), hidden: rows, in: textView.string as NSString
        ) { headers[$0] }
    }

    func clear() {
        drawn = [:]
        decorations.apply(tableViews: [:])
        guard !hiddenRows.isEmpty else { return }
        hiddenRows = []
        decorations.apply(tableRows: [])
    }
}
