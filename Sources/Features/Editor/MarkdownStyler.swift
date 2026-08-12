import Foundation

/// Classifies spans of a note's source for the editor to style.
///
/// SPEC §5 asks for "source mode improved": the syntax stays visible and gets styled,
/// rather than being hidden the way a live preview would. So this never removes or
/// replaces characters - it only says what each range *is*, and the view decides how
/// that looks using theme tokens.
enum MarkdownStyler {
    enum Span: Equatable, Sendable {
        /// The whole `---` block at the top of the file.
        case frontmatter
        case heading(level: Int)
        case bold
        case italic
        case code
        /// The `[[` `]]` `#` `|` punctuation inside a wikilink.
        case linkSyntax
        /// The target part of a wikilink, which is what a click follows.
        case linkTarget(String)
        /// An inline `#tag` in the body.
        case tag(String)
        /// The `- [ ]` marker of a task line.
        case taskMarker(done: Bool)
        /// A `>2026-08-15` scheduling marker.
        case scheduled
        /// A `!2026-08-20` due date.
        case due
        /// `@done(...)`, `@remind(...)`, `@repeat(...)`.
        case annotation
    }

    struct StyledRange: Equatable, Sendable {
        var range: Range<String.Index>
        var span: Span
    }

    /// Returns the styled ranges of a whole note, in no particular order. Ranges may
    /// nest (a wikilink inside a heading); the view applies them in the order given,
    /// so later spans win where they overlap.
    static func spans(in text: String) -> [StyledRange] {
        var result: [StyledRange] = []

        let bodyStart = frontmatterRange(in: text).map { range -> String.Index in
            result.append(StyledRange(range: range, span: .frontmatter))
            return range.upperBound
        } ?? text.startIndex

        for lineRange in lineRanges(in: text, from: bodyStart) {
            let line = String(text[lineRange])
            result.append(contentsOf: spans(inLine: line, at: lineRange, in: text))
        }

        result.append(contentsOf: wikilinkSpans(in: text, from: bodyStart))
        return result
    }

    /// The `---`-delimited block, only when it opens on the very first line.
    private static func frontmatterRange(in text: String) -> Range<String.Index>? {
        guard text.hasPrefix("---") else { return nil }
        let afterOpening = text.index(text.startIndex, offsetBy: 3)
        guard let closing = text.range(of: "\n---", range: afterOpening..<text.endIndex) else { return nil }
        return text.startIndex..<closing.upperBound
    }

    private static func lineRanges(in text: String, from start: String.Index) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var lineStart = start
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            if lineStart < lineEnd { ranges.append(lineStart..<lineEnd) }
            guard lineEnd < text.endIndex else { break }
            lineStart = text.index(after: lineEnd)
        }
        return ranges
    }

    private static func spans(
        inLine line: String,
        at lineRange: Range<String.Index>,
        in text: String
    ) -> [StyledRange] {
        var result: [StyledRange] = []

        /// Maps an offset inside `line` back to an index into `text`.
        func absolute(_ offset: Int, _ length: Int) -> Range<String.Index> {
            let start = text.index(lineRange.lowerBound, offsetBy: offset)
            let end = text.index(start, offsetBy: length)
            return start..<end
        }

        let trimmed = line.drop(while: { $0 == " " })
        let indent = line.count - trimmed.count

        if trimmed.hasPrefix("#") {
            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            // A heading needs a space after the hashes; `#tag` at line start is a tag.
            if hashes <= 6, trimmed.dropFirst(hashes).hasPrefix(" ") {
                result.append(StyledRange(range: lineRange, span: .heading(level: hashes)))
            }
        }

        if let marker = taskMarker(in: trimmed) {
            result.append(StyledRange(
                range: absolute(indent, marker.length),
                span: .taskMarker(done: marker.done)
            ))
        }

        result.append(contentsOf: inlineSpans(in: line, absolute: absolute))
        return result
    }

    private static func taskMarker(in line: some StringProtocol) -> (length: Int, done: Bool)? {
        // `- [ ]`, `- [x]`, `- [>]`, `- [-]` (SPEC §7.1), and the `*` bullet variant.
        guard line.count >= 5, let first = line.first, first == "-" || first == "*" else { return nil }
        let after = line.dropFirst()
        guard after.hasPrefix(" ["), after.count >= 4 else { return nil }
        let state = Array(after)[2]
        guard Array(after)[3] == "]" else { return nil }
        return (5, state == "x" || state == "X")
    }

    private static func inlineSpans(
        in line: String,
        absolute: (Int, Int) -> Range<String.Index>
    ) -> [StyledRange] {
        var result: [StyledRange] = []
        let characters = Array(line)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            switch character {
            case "*", "_":
                if let (length, span) = emphasis(characters, at: index) {
                    result.append(StyledRange(range: absolute(index, length), span: span))
                    index += length
                    continue
                }
            case "`":
                if let end = characters[(index + 1)...].firstIndex(of: "`") {
                    let length = end - index + 1
                    result.append(StyledRange(range: absolute(index, length), span: .code))
                    index += length
                    continue
                }
            case "#":
                // An inline tag, not a heading: it must be preceded by whitespace or
                // start the line, or `C#` and a URL fragment would both become tags.
                let precededByBoundary = index == 0 || characters[index - 1] == " "
                if precededByBoundary, let length = tagLength(characters, from: index) {
                    let value = String(characters[index..<(index + length)])
                    result.append(StyledRange(range: absolute(index, length), span: .tag(value)))
                    index += length
                    continue
                }
            case ">", "!":
                if let length = dateMarkerLength(characters, from: index) {
                    result.append(StyledRange(
                        range: absolute(index, length),
                        span: character == ">" ? .scheduled : .due
                    ))
                    index += length
                    continue
                }
            case "@":
                if let length = annotationLength(characters, from: index) {
                    result.append(StyledRange(range: absolute(index, length), span: .annotation))
                    index += length
                    continue
                }
            default:
                break
            }
            index += 1
        }
        return result
    }

    private static func emphasis(_ characters: [Character], at index: Int) -> (Int, Span)? {
        let marker = characters[index]
        let isDouble = index + 1 < characters.count && characters[index + 1] == marker
        let markerLength = isDouble ? 2 : 1
        let searchStart = index + markerLength

        guard searchStart < characters.count else { return nil }
        var cursor = searchStart
        while cursor < characters.count {
            if characters[cursor] == marker {
                if isDouble {
                    guard cursor + 1 < characters.count, characters[cursor + 1] == marker else {
                        cursor += 1
                        continue
                    }
                    return (cursor + 2 - index, .bold)
                }
                return (cursor + 1 - index, .italic)
            }
            cursor += 1
        }
        return nil
    }

    /// Length of a `#namespace-value` run, or nil when what follows is not a tag.
    private static func tagLength(_ characters: [Character], from index: Int) -> Int? {
        var cursor = index + 1
        while cursor < characters.count {
            let character = characters[cursor]
            guard character.isLetter || character.isNumber || character == "-" else { break }
            cursor += 1
        }
        let length = cursor - index
        guard length > 1 else { return nil }
        return Tag(String(characters[index..<cursor])) == nil ? nil : length
    }

    /// Length of `>YYYY-MM-DD` or `!YYYY-MM-DD`.
    private static func dateMarkerLength(_ characters: [Character], from index: Int) -> Int? {
        let dateLength = 10
        guard index + dateLength < characters.count + 1,
              index + 1 + dateLength <= characters.count
        else { return nil }
        let candidate = String(characters[(index + 1)..<(index + 1 + dateLength)])
        return CalendarDate(iso: candidate) == nil ? nil : dateLength + 1
    }

    /// Length of `@name(...)`.
    private static func annotationLength(_ characters: [Character], from index: Int) -> Int? {
        var cursor = index + 1
        while cursor < characters.count, characters[cursor].isLetter { cursor += 1 }
        guard cursor > index + 1, cursor < characters.count, characters[cursor] == "(" else { return nil }
        guard let close = characters[cursor...].firstIndex(of: ")") else { return nil }
        return close + 1 - index
    }

    private static func wikilinkSpans(in text: String, from start: String.Index) -> [StyledRange] {
        var result: [StyledRange] = []
        for link in WikilinkParser.links(in: String(text[start...])) {
            // The parser worked on a slice; shift its indices back onto the full text.
            let offset = text.distance(from: text.startIndex, to: start)
            let sliceStart = text.index(text.startIndex, offsetBy: offset)
            let lower = text.index(sliceStart, offsetBy: String(text[start...]).distance(
                from: String(text[start...]).startIndex, to: link.range.lowerBound
            ))
            let upper = text.index(sliceStart, offsetBy: String(text[start...]).distance(
                from: String(text[start...]).startIndex, to: link.range.upperBound
            ))

            result.append(StyledRange(range: lower..<upper, span: .linkSyntax))

            // The target sits after the opening brackets; styling it separately is
            // what makes only the title look clickable.
            let openingLength = link.isEmbed ? 3 : 2
            let targetStart = text.index(lower, offsetBy: openingLength)
            if let targetEnd = text.index(targetStart, offsetBy: link.target.count, limitedBy: upper) {
                result.append(StyledRange(
                    range: targetStart..<targetEnd,
                    span: .linkTarget(link.target)
                ))
            }
        }
        return result
    }
}
