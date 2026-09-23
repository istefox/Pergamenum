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

    /// Every list line's CommonMark nesting level, in one forward pass over `text`
    /// (PG-139/#239) - equivalent to, but not a replacement for, calling `level(in:lineStart:
    /// indent:)` at every list line: that walks backward to the top of the document and
    /// rebuilds the ancestor stack from scratch each time, which is the O(n²) this exists to
    /// avoid on a long list restyled on every keystroke.
    ///
    /// Keyed by each list line's own start index. The indices belong to *this* `String`; the
    /// map is meaningless against any other value, which is why the one caller that holds
    /// `text` throughout is the only one given it.
    ///
    /// Scans from `text.startIndex` - frontmatter included, no fence filter - exactly what
    /// `level(in:lineStart:indent:)`'s own backward walk already sees, and folds the same
    /// stack `ancestorContentColumns(in:before:)` rebuilds per line incrementally instead: a
    /// list line pops every entry whose content column is greater than its own indent,
    /// reports `min(1 + stack.count, 6)`, then pushes its own content column; a blank line
    /// changes nothing; an indented non-list line changes nothing (still inside the nearest
    /// open item); a non-list, non-blank line at column 0 clears the stack (nothing stays
    /// open across a top-level paragraph). `markerWidth` is the same shared grammar, so a
    /// checkbox line is still counted as an ancestor here, exactly as it is today.
    static func levels(in text: String) -> [String.Index: Int] {
        var levels: [String.Index: Int] = [:]
        var stack: [Int] = []

        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]

            if !line.isEmpty {
                let indentPrefix = line.prefix(while: { $0 == " " || $0 == "\t" })
                let indentColumns = indentPrefix.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
                let content = line.dropFirst(indentPrefix.count)

                if let marker = markerWidth(in: content) {
                    while let top = stack.last, top > indentColumns {
                        stack.removeLast()
                    }
                    levels[lineStart] = min(1 + stack.count, 6)
                    stack.append(indentColumns + marker)
                } else if indentColumns == 0 {
                    stack.removeAll()
                }
            }

            guard lineEnd < text.endIndex else { break }
            lineStart = text.index(after: lineEnd)
        }

        return levels
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
