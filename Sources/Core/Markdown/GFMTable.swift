import Foundation

/// One GFM pipe table's grammar, extracted from `MarkdownBlockParser.table(header:consuming:)`
/// (ADR-0029 §D2; plan `2026-09-02-editor-wysiwyg-unification`, Task 3) so the reading view's
/// `MarkdownBlock.Table` and the editor's live grid (Task 4) parse the *same* grammar instead
/// of two that could silently drift.
///
/// `Sources/Core/**` is a `sharedSources` glob (`Project.swift:73`): compiled into `perg` and
/// `pergamenum-mcp` too, so this file stays Foundation-only (ADR-0001 §D1) - no AppKit, no
/// SwiftUI.
///
/// The grammar is `MarkdownBlockParser.table(header:consuming:)`'s, moved here rather than
/// copied: that parser now calls `parsed(header:rest:)` below for its own cells, so there
/// is one implementation of "what is a table" and the reading view and the editor cannot
/// start disagreeing about a line of pipes.
struct GFMTable: Equatable, Sendable {
    enum Alignment: Equatable, Sendable { case leading, center, trailing }

    var header: [String]
    /// One per column, taken from the delimiter row - always `header.count` long, since a
    /// delimiter row that disagrees with the header is not a table at all (R-10).
    var alignments: [Alignment]
    /// Every row already padded or truncated to `header.count`, GFM's own rule
    /// (`fit(_:to:)` in `MarkdownBlockParser`, unchanged by this extraction).
    var rows: [[String]]
    /// The whole table's source range - the header line through the last body row, the
    /// blank line or first non-table line after it excluded (R-05).
    var range: Range<String.Index>
    /// Each source line's own range, in order: header, delimiter, then one per body row.
    /// Kept apart from `range` because a structural edit (Task 5) rewrites one line, or
    /// inserts/removes one, without necessarily touching every other line's range.
    var lineRanges: [Range<String.Index>]

    /// Every table found in `text` from `start` onward, skipping any range inside `fences`
    /// (fenced code - R-09), the same way `MarkdownStyler.wikilinkSpans(in:from:outside:)`
    /// already skips a `[[wikilink]]` written inside one.
    static func runs(in text: String, from start: String.Index, outside fences: [CodeFence.Region]) -> [GFMTable] {
        let ranges = lineRanges(in: text, from: start)
        let lines = ranges.map { String(text[$0]) }
        var result: [GFMTable] = []
        var index = 0

        while index < ranges.count {
            guard let parsed = parsed(header: lines[index], rest: lines[(index + 1)...]) else {
                index += 1
                continue
            }
            let consumed = Array(ranges[index...(index + parsed.bodyLines)])
            // Every line of it, not only the header: a fence opening in the middle of what
            // otherwise reads as a table would leave half of it inside code (R-09).
            guard !consumed.contains(where: { line in fences.contains { $0.range.overlaps(line) } }) else {
                index += 1
                continue
            }
            result.append(GFMTable(
                header: parsed.header,
                alignments: parsed.alignments,
                rows: parsed.rows,
                range: consumed[0].lowerBound..<consumed[consumed.count - 1].upperBound,
                lineRanges: consumed
            ))
            index += parsed.bodyLines + 1
        }
        return result
    }

    /// One table starting at `lines.first`, or nil when these lines are not one - GFM's own
    /// rule: a header line needs a delimiter row of the same column count directly under it
    /// (R-10). Ranges on the returned value are relative to `lines.joined(separator: "\n")`
    /// as its own self-contained text, not to any larger note `lines` may have been sliced
    /// from - which is what makes `parse(serialised().lines) == self` a meaningful
    /// round-trip rather than one that only holds by accident of position.
    static func parse(_ lines: ArraySlice<String>) -> GFMTable? {
        guard let head = lines.first,
              let parsed = parsed(header: head, rest: lines.dropFirst())
        else { return nil }

        let text = lines.joined(separator: "\n")
        let ranges = lineRanges(in: text, from: text.startIndex)
        guard ranges.count > parsed.bodyLines else { return nil }
        let consumed = Array(ranges[0...parsed.bodyLines])
        return GFMTable(
            header: parsed.header,
            alignments: parsed.alignments,
            rows: parsed.rows,
            range: consumed[0].lowerBound..<consumed[consumed.count - 1].upperBound,
            lineRanges: consumed
        )
    }

    /// This table's own markdown source, header line through the last body row - what a
    /// structural edit (Task 5) writes back in place of `range`.
    ///
    /// The delimiter row is written without padding (`|---|:-:|--:|`) and every other row
    /// with one space inside each pipe, which is both what `EditorCommand.table` already
    /// writes and what makes `parse(serialised()) == self` hold for a table read out of an
    /// ordinary note: a wider or narrower spelling of the same cells would round-trip the
    /// values and not the ranges.
    func serialised() -> String {
        var lines = [Self.serialised(row: header)]
        lines.append("|" + alignments.map(\.delimiter).joined(separator: "|") + "|")
        lines.append(contentsOf: rows.map(Self.serialised(row:)))
        return lines.joined(separator: "\n")
    }

    private static func serialised(row cells: [String]) -> String {
        // Only the pipe is escaped on the way out, which is the exact inverse of what
        // `cells(in:)` unescapes on the way in: a backslash with nothing to escape after it
        // is a Windows path and is left alone.
        "| " + cells.map { $0.replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |"
    }

    // MARK: The grammar, shared with `MarkdownBlockParser`

    /// One table's cells, with no ranges attached: what both entry points above and
    /// `MarkdownBlockParser.table(header:consuming:)` are three different ways of asking
    /// for.
    ///
    /// Rangeless on purpose. The block parser walks an array of lines and has no indices
    /// into any string at all; giving it a `GFMTable` would mean inventing ranges it cannot
    /// use, and giving the editor a `MarkdownBlock.Table` would mean parsing twice. What the
    /// two genuinely share is this - the column count rule, the alignment forms, the escape
    /// rule and where a table stops - and it is spelled once.
    struct Parsed: Equatable, Sendable {
        var header: [String]
        var alignments: [Alignment]
        var rows: [[String]]
        /// How many lines *after* the header this table takes: the delimiter row plus one
        /// per body row. What the block parser drops from its own slice.
        var bodyLines: Int
    }

    static func parsed(header line: some StringProtocol, rest: ArraySlice<String>) -> Parsed? {
        let head = line.trimmingCharacters(in: .whitespaces)
        guard head.contains("|") else { return nil }
        guard let delimiter = rest.first?.trimmingCharacters(in: .whitespaces) else { return nil }
        let columns = cells(in: head)
        guard let alignments = alignments(in: delimiter), alignments.count == columns.count else {
            return nil
        }

        var rows: [[String]] = []
        var remaining = rest.dropFirst()
        // The table runs to the first blank line or the first line with no pipe in it,
        // which is where GFM ends one.
        while let next = remaining.first?.trimmingCharacters(in: .whitespaces),
              !next.isEmpty, next.contains("|") {
            remaining = remaining.dropFirst()
            rows.append(fit(cells(in: next), to: columns.count))
        }
        return Parsed(header: columns, alignments: alignments, rows: rows, bodyLines: 1 + rows.count)
    }

    /// The column alignments a delimiter row declares, or nil when the line is not one.
    static func alignments(in line: String) -> [Alignment]? {
        let parts = cells(in: line)
        guard !parts.isEmpty else { return nil }
        var result: [Alignment] = []
        for part in parts {
            let left = part.hasPrefix(":")
            let right = part.hasSuffix(":")
            let dashes = part.dropFirst(left ? 1 : 0).dropLast(right && part.count > 1 ? 1 : 0)
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            switch (left, right) {
            case (true, true): result.append(.center)
            case (false, true): result.append(.trailing)
            default: result.append(.leading)
            }
        }
        return result
    }

    /// Splits a row on its unescaped pipes, dropping the optional outer ones.
    static func cells(in row: String) -> [String] {
        var body = row.trimmingCharacters(in: .whitespaces)[...]
        if body.hasPrefix("|") { body = body.dropFirst() }
        if body.hasSuffix("|"), !body.hasSuffix("\\|") { body = body.dropLast() }

        var result: [String] = []
        var current = ""
        var escaped = false
        for character in body {
            if escaped {
                // Only `\|` is an escape here; anything else keeps its backslash,
                // so a Windows path in a cell survives the trip.
                if character != "|" { current.append("\\") }
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    /// Pads a short row and drops a long one's extra cells, as GFM specifies.
    static func fit(_ row: [String], to width: Int) -> [String] {
        if row.count == width { return row }
        if row.count > width { return Array(row.prefix(width)) }
        return row + Array(repeating: "", count: width - row.count)
    }

    /// Line ranges from `start`, the newline excluded and **empty lines kept** - unlike
    /// `MarkdownStyler`'s own helper, which skips them because it has nothing to style on
    /// one. Here a blank line is load-bearing: it is where a table ends.
    private static func lineRanges(in text: String, from start: String.Index) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var lineStart = start
        while lineStart <= text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            ranges.append(lineStart..<lineEnd)
            guard lineEnd < text.endIndex else { break }
            lineStart = text.index(after: lineEnd)
        }
        return ranges
    }
}

extension GFMTable.Alignment {
    /// How this alignment is written in a delimiter row. Three characters whichever it is,
    /// which is what keeps `serialised()` the same width as the source it came from.
    var delimiter: String {
        switch self {
        case .leading: "---"
        case .center: ":-:"
        case .trailing: "--:"
        }
    }
}
