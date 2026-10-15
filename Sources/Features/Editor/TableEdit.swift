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
    /// Sets one column's alignment (ADR-0087 §D11). Setting the alignment a column already has, or
    /// an out-of-range column, is a refusal: the table comes back unchanged.
    case align(column: Int, GFMTable.Alignment)
    /// Reorders the body rows by one column (ADR-0087 §D11): `localizedStandardCompare`, empty
    /// cells last in both directions, stable, the header untouched.
    case sort(column: Int, ascending: Bool)

    /// The edit applied to `table`, or `table` itself unchanged when the edit does not
    /// apply cleanly (an out-of-range row/column, or a removal that would leave the table
    /// empty).
    ///
    /// `table.range` and `table.lineRanges` are carried through untouched, and deliberately:
    /// they describe the source this table was *read* from, and the commit re-derives them
    /// from `GFMTable.parse` over the live characters at write time (D8's reload guard,
    /// `NoteTextView+Tables.swift`). A pure function that tried to keep them current would be
    /// inventing indices into a string it has never seen.
    ///
    /// **Returning `table` unchanged is how a refusal is spelled**, rather than an optional
    /// or a throw: every caller here is a grid button whose only sane answer to "that would
    /// leave the table with no columns" is to do nothing, and the commit path already treats
    /// an unchanged table as nothing to write (R-10 - a malformed table must not exist, so it
    /// is never produced in the first place).
    func applied(to table: GFMTable) -> GFMTable {
        var result = table
        switch self {
        case .cell(let row, let column, let text):
            guard column >= 0, column < result.header.count else { return table }
            guard let row else {
                result.header[column] = text
                return result
            }
            guard row >= 0, row < result.rows.count else { return table }
            result.rows[row][column] = text

        case .addRow(let after):
            let index = after.map { $0 + 1 } ?? 0
            guard index >= 0, index <= result.rows.count else { return table }
            result.rows.insert(Array(repeating: "", count: result.header.count), at: index)

        case .removeRow(let index):
            // The last body row stays: a grid drawing zero rows has nothing left to hold
            // focus, and the person who wanted the table gone deletes its lines, which is
            // what `hidesMarkup` off is for (§D9).
            guard index >= 0, index < result.rows.count, result.rows.count > 1 else { return table }
            result.rows.remove(at: index)

        case .addColumn(let after):
            let index = after.map { $0 + 1 } ?? 0
            guard index >= 0, index <= result.header.count else { return table }
            result.header.insert("", at: index)
            // The delimiter row grows with the header or the result is not a table at all
            // (R-10: a delimiter row that disagrees with the header parses as nothing).
            // `.leading` is GFM's own default for a column that declares no alignment.
            result.alignments.insert(.leading, at: index)
            result.rows = result.rows.map { row in
                var grown = row
                grown.insert("", at: min(index, grown.count))
                return grown
            }

        case .removeColumn(let index):
            guard index >= 0, index < result.header.count, result.header.count > 1 else { return table }
            result.header.remove(at: index)
            result.alignments.remove(at: index)
            result.rows = result.rows.map { row in
                guard index < row.count else { return row }
                var shrunk = row
                shrunk.remove(at: index)
                return shrunk
            }

        case .align(let column, let alignment):
            guard column >= 0, column < result.alignments.count else { return table }
            result.alignments[column] = alignment

        case .sort(let column, let ascending):
            guard column >= 0, column < result.header.count else { return table }
            result.rows = Self.sorted(result.rows, by: column, ascending: ascending)
        }
        return result
    }

    /// `rows` ordered by one column's text through `localizedStandardCompare`, so `2` sorts before
    /// `10`. Empty cells go last in both directions, and rows with equal keys keep their order: the
    /// original position breaks every tie, so stability does not rest on the library's sort.
    private static func sorted(_ rows: [[String]], by column: Int, ascending: Bool) -> [[String]] {
        func key(_ row: [String]) -> String {
            column < row.count ? row[column].trimmingCharacters(in: .whitespaces) : ""
        }
        return rows.enumerated().sorted { lhs, rhs in
            let left = key(lhs.element), right = key(rhs.element)
            if left.isEmpty != right.isEmpty { return right.isEmpty }
            let order = left.localizedStandardCompare(right)
            if order == .orderedSame || left.isEmpty { return lhs.offset < rhs.offset }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }.map(\.element)
    }
}
