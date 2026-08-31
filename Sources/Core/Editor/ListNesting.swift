import Foundation

/// CommonMark-correct list nesting depth (PG-085, ADR-0028 §D-Negative).
///
/// Foundation-only, alongside `ListContinuation.swift` - `Sources/Core/**` is compiled into
/// both `perg` and `pergamenum-mcp` (ADR-0001 §D1), so no AppKit/SwiftUI import here.
///
/// A line's own indentation alone cannot say how deeply it nests: CommonMark measures it
/// against each enclosing item's *content column* (marker start + marker width + the one
/// mandatory trailing space), which varies with marker width (`- ` is 2 columns, `12. ` is
/// 4). `level(in:lineStart:indent:)` is the shared answer both `MarkdownStyler`'s styling
/// pass and `EditorDecorationDelegate`'s layout-time re-read call, from live characters,
/// each on its own schedule - no caching, matching the existing no-stale-level invariant on
/// `HiddenMarker.Kind.list`.
enum ListNesting {
    /// The CommonMark-correct nesting level of a list item at `lineStart`, given its own
    /// indentation in columns (`indent`; a tab already counted as 4, matching both callers'
    /// existing column arithmetic). Walks backward through `text` from `lineStart` to
    /// reconstruct the stack of open ancestor list items and their content columns, then
    /// returns 1 plus the number of open ancestors whose content column is `<= indent`
    /// (CommonMark's tie-break: attach to the deepest list that still fits), capped at 6.
    static func level(in text: String, lineStart: String.Index, indent: Int) -> Int {
        let ancestors = ancestorContentColumns(in: text, before: lineStart)
        let openBelow = ancestors.filter { $0 <= indent }.count
        return min(1 + openBelow, 6)
    }

    /// The content columns of every list item still open just before `lineStart`, in
    /// document order (outermost first).
    ///
    /// `lineStart` is always the start of a line (indentation included, never mid-line) -
    /// both callers pass a value derived that way, so the character right before it is
    /// either `"\n"` or nothing (`lineStart == text.startIndex`).
    private static func ancestorContentColumns(in text: String, before lineStart: String.Index) -> [Int] {
        var candidates: [(indent: Int, contentColumn: Int)] = []

        var searchEnd = lineStart
        while searchEnd > text.startIndex {
            // The previous line ends right before `searchEnd`'s own leading "\n".
            let previousLineEnd = text.index(before: searchEnd)
            let beforePreviousLineEnd = text[text.startIndex..<previousLineEnd]
            let previousLineStart = beforePreviousLineEnd.lastIndex(of: "\n").map(text.index(after:))
                ?? text.startIndex

            let line = String(text[previousLineStart..<previousLineEnd])
            searchEnd = previousLineStart

            if line.isEmpty { continue }

            let indentPrefix = line.prefix(while: { $0 == " " || $0 == "\t" })
            let indentColumns = indentPrefix.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            let content = line.dropFirst(indentPrefix.count)

            if let marker = markerWidth(in: content) {
                candidates.append((indent: indentColumns, contentColumn: indentColumns + marker))
                continue
            }

            // A non-list, non-blank line: continuation text if it is itself indented (still
            // inside the nearest open item), or the boundary that closes every open list if
            // it sits at column 0.
            if indentColumns == 0 {
                break
            }
        }

        candidates.reverse()

        var stack: [Int] = []
        for candidate in candidates {
            while let top = stack.last, top > candidate.indent {
                stack.removeLast()
            }
            stack.append(candidate.contentColumn)
        }
        return stack
    }

    /// The width of a list marker (itself plus its one mandatory trailing space) at the
    /// start of `content`, restating `MarkdownStyler`'s private `listMarkerLength(in:)`
    /// grammar (accepted duplication, per `ListContinuation.swift`'s own precedent - the
    /// grammar is private to that file and this is a different file).
    private static func markerWidth(in content: some StringProtocol) -> Int? {
        guard let first = content.first else { return nil }
        if first == "-" || first == "*" || first == "+" {
            return content.dropFirst().hasPrefix(" ") ? 2 : nil
        }
        let digits = content.prefix(while: { $0.isASCII && $0.isNumber }).count
        guard digits > 0 else { return nil }
        let afterDigits = content.dropFirst(digits)
        guard let delimiter = afterDigits.first, delimiter == "." || delimiter == ")" else { return nil }
        return afterDigits.dropFirst().hasPrefix(" ") ? digits + 2 : nil
    }
}
