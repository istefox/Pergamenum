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
/// **Declared by the tester.** `runs(in:from:outside:)`, `parse(_:)` and `serialised()` are
/// stubbed below to return nothing at all, which is what keeps every
/// `Tests/GFMTableTests.swift` assertion genuinely red. The coder fills the grammar,
/// extracted from `MarkdownBlockParser.table(header:consuming:)` without changing its
/// observable behaviour: the existing `Tests/MarkdownReadingTests.swift` table assertions
/// must stay green, unmodified, once this is wired in.
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
        []
    }

    /// One table starting at `lines.first`, or nil when these lines are not one - GFM's own
    /// rule: a header line needs a delimiter row of the same column count directly under it
    /// (R-10). Ranges on the returned value are relative to `lines.joined(separator: "\n")`
    /// as its own self-contained text, not to any larger note `lines` may have been sliced
    /// from - which is what makes `parse(serialised().lines) == self` a meaningful
    /// round-trip rather than one that only holds by accident of position.
    static func parse(_ lines: ArraySlice<String>) -> GFMTable? {
        nil
    }

    /// This table's own markdown source, header line through the last body row - what a
    /// structural edit (Task 5) writes back in place of `range`.
    func serialised() -> String {
        ""
    }
}
