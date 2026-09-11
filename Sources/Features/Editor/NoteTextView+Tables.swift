import AppKit

/// A table the editor is drawing right now: the grid vended for it and the shape that grid
/// was built from, as of the last styling pass.
///
/// Declared beside the Coordinator's table half rather than in `NoteTextView+Coordinator.swift`
/// for the reason `EmbedDrag` is declared beside the resize gesture: the three phases that
/// fill, read and clear it are all in this file, and the stored property that holds them is
/// only a place to keep a value between two of them.
struct DrawnTable {
    let grid: TableGridView
    let table: GFMTable
}

/// The Coordinator's own half of the table grid (ADR-0029 §D5/§D6/§D7/§D8; plan
/// `2026-09-02-editor-wysiwyg-unification`, Task 4/5): the styling pass that recognises a
/// table and vends its grid, and the commit that writes a cell back into the note's own
/// characters.
///
/// The commit is on the exact model `NoteTextView+EmbedCaret.swift`'s
/// `replaceAtomically(_:with:in:)` already set: one atomic
/// `shouldChangeText`/`beginEditing`/`replaceCharacters`/`endEditing` write, never a second
/// path, so a structural table edit is one `Cmd+Z` regardless of which cell moved.
extension NoteTextView.Coordinator {
    // MARK: The styling pass (ADR §D5/§D6)

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
    func applyTables(to textView: NSTextView, runs: [NSRange], markers: inout [Int: [HiddenMarker]]) {
        guard parent.hidesMarkup else {
            clearTables()
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
            var start = 0, end = 0, contentsEnd = 0
            text.getParagraphStart(
                &start, end: &end, contentsEnd: &contentsEnd,
                for: NSRange(location: header, length: 0)
            )
            guard contentsEnd > start else { continue }
            // Anchored at the header paragraph's own start and covering its pipes alone, the
            // convention `.list` and `.blockquote` already use - never the whole run, which
            // spans paragraphs the delegate is asked about one at a time.
            markers[header, default: []].append(
                HiddenMarker(range: NSRange(location: 0, length: contentsEnd - start), kind: .table)
            )
            found.append((header, recognised.table))

            var cursor = end
            while cursor < NSMaxRange(recognised.range) {
                rows.insert(cursor)
                headerOfRow[cursor] = header
                var rowStart = 0, rowEnd = 0, rowContentsEnd = 0
                text.getParagraphStart(
                    &rowStart, end: &rowEnd, contentsEnd: &rowContentsEnd,
                    for: NSRange(location: cursor, length: 0)
                )
                guard rowEnd > cursor else { break }
                cursor = rowEnd
            }
        }

        let grids = tableGrids.views(for: found.map(\.header), in: textView)
        decorations.apply(tableViews: grids)
        var drawn: [Int: DrawnTable] = [:]
        for entry in found {
            guard let grid = grids[entry.header] else { continue }
            // Re-set on every pass rather than once at build time: the closure carries the
            // header offset, and an edit above the table moves it. A grid holding last
            // pass's offset would commit against a range that has since become someone
            // else's - which D8's guard would refuse, correctly and uselessly.
            grid.onCommit = { [weak self, weak textView] edit in
                guard let self, let textView else { return false }
                return self.commitTable(edit, at: entry.header, in: textView)
            }
            drawn[entry.header] = DrawnTable(grid: grid, table: entry.table)
        }
        drawnTables = drawn

        guard rows != lastTableRows else { return }
        lastTableRows = rows
        decorations.apply(tableRows: rows)
        pendingTableCaret = tableCaretRescue(in: textView, rows: rows, headers: headerOfRow)
    }

    /// Draws each grid the note currently holds, and takes the caret out of a row that has
    /// just left the layout.
    ///
    /// **After `storage.endEditing()`, never inside it.** Both halves reach outside the text
    /// storage - a grid resizes itself, and a caret rescue moves the selection - and doing
    /// either while an editing transaction is open asks TextKit to lay out a document it has
    /// been told is mid-change.
    func refreshTableGrids(in textView: NSTextView, theme: Theme) {
        for drawn in drawnTables.values {
            drawn.grid.update(with: drawn.table, theme: theme)
        }
        guard let offset = pendingTableCaret else { return }
        pendingTableCaret = nil
        textView.setSelectedRange(NSRange(location: offset, length: 0))
        textView.scrollRangeToVisible(NSRange(location: offset, length: 0))
    }

    /// `rescueCaret(in:from:)`'s table twin (§D5): a caret inside a row that has just become
    /// hidden is an insertion point with nowhere to be drawn and nowhere to type. It goes to
    /// the table's own header offset, which is where a person would look for it - and where
    /// the grid is.
    private func tableCaretRescue(
        in textView: NSTextView, rows: Set<Int>, headers: [Int: Int]
    ) -> Int? {
        guard !rows.isEmpty else { return nil }
        let text = textView.string as NSString
        let caret = textView.selectedRange().location
        guard caret <= text.length else { return nil }
        let line = text.paragraphRange(for: NSRange(location: caret, length: 0)).location
        guard rows.contains(line) else { return nil }
        return headers[line]
    }

    private func clearTables() {
        drawnTables = [:]
        decorations.apply(tableViews: [:])
        guard !lastTableRows.isEmpty else { return }
        lastTableRows = []
        decorations.apply(tableRows: [])
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
        return replaceAtomically(live.range, with: edited.serialised(), in: textView)
    }
}
