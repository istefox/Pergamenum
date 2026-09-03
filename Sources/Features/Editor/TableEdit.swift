import Foundation

/// One structural or cell edit a `TableGridView` cell can make to the `GFMTable` it draws
/// (ADR-0029 §D7; plan `2026-09-02-editor-wysiwyg-unification`, Task 5).
///
/// `Sources/Features/Editor/**` is not a `sharedSources` glob, but this type is
/// Foundation-only anyway (it operates on `GFMTable`, itself Foundation-only per Task 3) -
/// there is nothing AppKit about *what* an edit changes, only about *when* one commits
/// (Tab/Shift-Tab/Enter/blur, `NoteTextView+Tables.swift`'s own job).
///
/// `row: Int?`/`after: Int?` read `nil` as "the header row" / "before every body row" -
/// never a `-1` sentinel, since `GFMTable.rows` is already a plain `[[String]]` with no
/// room for a sentinel index of its own.
enum TableEdit: Equatable, Sendable {
    /// Overwrites one cell's text - `row: nil` for the header, `row: 0` for the first body
    /// row, and so on. `column` is always in `0..<table.header.count`.
    case cell(row: Int?, column: Int, text: String)
    /// Inserts an empty body row - `after: nil` inserts before every existing body row,
    /// `after: 0` inserts right after the first one.
    case addRow(after: Int?)
    /// Removes one body row, by its index into `table.rows`. Refused by D8's reload guard
    /// when it would leave the table with no body rows at all (R-10's own "a table needs a
    /// header and at least one delimiter row" does not require a body row, but a grid
    /// drawing zero rows has nothing left to hold focus, so the guard keeps at least one).
    case removeRow(Int)
    /// Inserts an empty column - `after: nil` inserts before every existing column,
    /// `after: 0` inserts right after the first one. Every row, the header included, grows
    /// by one empty cell.
    case addColumn(after: Int?)
    /// Removes one column, by its index into `table.header`. Refused, the same way
    /// `removeRow` is, when it would leave the table with no columns at all.
    case removeColumn(Int)

    /// The edit applied to `table`, or `table` itself unchanged when the edit does not
    /// apply cleanly (an out-of-range row/column, or a removal that would leave the table
    /// empty).
    ///
    /// Stub for Task 5 (tester): the identity function, so every positive test below is red
    /// until the coder fills in the five cases - reading and writing `table.header`/
    /// `table.rows`/`table.alignments` directly, since a `TableEdit` never touches
    /// `table.range`/`table.lineRanges` (those are `NoteTextView+Tables.swift`'s own
    /// concern, re-derived from `GFMTable.parse` at commit time per D8's reload guard, not
    /// carried through this pure function at all).
    func applied(to table: GFMTable) -> GFMTable {
        table
    }
}
