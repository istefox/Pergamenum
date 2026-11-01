import Foundation

/// A section a convention owns, found by its heading line rather than by its heading's text
/// (ADR-0065 §D9.3, R-18, PG-278; R-10).
///
/// One walk for every section the app reads or rewrites (`## Note correlate`, `## Timeline`,
/// `## Note`). A search for the heading's characters matched them anywhere - inside
/// `### Timeline`, `## Timeline riunione`, `## Note correlate` or a code fence - and the writer
/// then rewrote a section that was not its own.
enum MarkdownSection {
    /// The section, from the start of its heading line to the start of the next line beginning
    /// with `#`, or to the end of the body.
    ///
    /// The heading is a line that is exactly `heading` once one trailing `\r` and any trailing
    /// spaces or tabs are removed. Lines are walked on unicode scalars, because a CRLF pair is one
    /// `Character` and a `Character` search for `\n` finds no line end in a CRLF note at all
    /// (ADR-0065 §D3).
    ///
    /// A line inside a backtick or tilde fence is neither the heading nor the line that ends the
    /// section (PG-278): a note quoting the convention in a code block has no section there, and
    /// a `# comment` in a shell block under the section does not cut it short. The fences come
    /// from `WikilinkParser.codeRanges(in:)`, the rule that already keeps a `[[link]]` in a fence
    /// from being a link, CRLF included. Its inline code spans can contain a line start, when a
    /// span opens at column 0, but such a line begins with a backtick and is never the heading or
    /// a `#` line, so only the fences change the answer here.
    static func range(under heading: String, in body: String) -> Range<String.Index>? {
        let scalars = body.unicodeScalars
        let code = WikilinkParser.codeRanges(in: body)
        var start: String.Index?
        var lineStart = scalars.startIndex
        while lineStart < scalars.endIndex {
            let lineEnd = scalars[lineStart...].firstIndex(of: "\n") ?? scalars.endIndex
            let line = String(scalars[lineStart..<lineEnd])
            let isCode = code.contains { $0.contains(lineStart) }
            if let start {
                if !isCode, line.hasPrefix("#") { return start..<lineStart }
            } else if !isCode, isHeading(line, heading) {
                start = lineStart
            }
            guard lineEnd < scalars.endIndex else { break }
            lineStart = scalars.index(after: lineEnd)
        }
        return start.map { $0..<body.endIndex }
    }

    /// One line of a section below its heading: where it is in the body, without its `\n`, and
    /// whether it sits inside a code fence.
    struct Line {
        let range: Range<String.Index>
        let isCode: Bool

        /// The line's text, a CRLF line's `\r` included: read on unicode scalars, because the
        /// range ends between the `\r` and the `\n` of a pair that is one `Character`.
        func text(in body: String) -> String {
            String(body.unicodeScalars[range])
        }
    }

    /// The lines of `section` below its heading line, walked as `range(under:in:)` walks them and
    /// with the same fence rule, so a reader can skip a fenced example (`- 09:00-10:00 x` in a code
    /// block under `## Timeline` is not a block) and a writer can keep it.
    static func lines(below section: Range<String.Index>, in body: String) -> [Line] {
        let scalars = body.unicodeScalars
        guard let headingLineEnd = scalars[section].firstIndex(of: "\n") else { return [] }
        let code = WikilinkParser.codeRanges(in: body)
        var lines: [Line] = []
        var lineStart = scalars.index(after: headingLineEnd)
        while lineStart < section.upperBound {
            let lineEnd = scalars[lineStart..<section.upperBound].firstIndex(of: "\n") ?? section.upperBound
            lines.append(Line(range: lineStart..<lineEnd, isCode: code.contains { $0.contains(lineStart) }))
            guard lineEnd < section.upperBound else { break }
            lineStart = scalars.index(after: lineEnd)
        }
        return lines
    }

    /// Where the heading's own text ends inside `section`: the line is the heading plus at most
    /// trailing blanks and a `\r`, so its first `heading.count` characters are the heading.
    static func headingEnd(of heading: String, in body: String, section: Range<String.Index>) -> String.Index {
        body.index(section.lowerBound, offsetBy: heading.count, limitedBy: section.upperBound) ?? section.upperBound
    }

    /// The end of the section's last line, before the line break that separates it from the next
    /// heading; the end of the body when the section runs to it. This is where a writer that
    /// replaces or appends to the section stops, so the next heading keeps its own line.
    static func contentEnd(in body: String, section: Range<String.Index>) -> String.Index {
        guard section.upperBound < body.endIndex, section.upperBound > section.lowerBound else {
            return section.upperBound
        }
        // `upperBound` is the start of the next `#` line, so the `Character` before it is the line
        // break - a `"\r\n"` pair is one `Character`, so one step back covers CRLF too.
        return body.index(before: section.upperBound)
    }

    /// Whether `line` is `heading`'s line: equal once one trailing `\r` and any trailing spaces or
    /// tabs are removed. Shared with the Plaud note's own section split (`TranscriptNote`).
    static func isHeading(_ line: String, _ heading: String) -> Bool {
        var scalars = Substring(line).unicodeScalars
        if scalars.last == "\r" { scalars.removeLast() }
        while let last = scalars.last, last == " " || last == "\t" { scalars.removeLast() }
        return String(scalars) == heading
    }
}
