import Foundation

/// A note's index: its headings and the notes and files embedded in it, in the order
/// they appear.
///
/// A long note in this app has no way of being navigated. There is search, which needs
/// you to already know what you are looking for, and there is scrolling. An outline is
/// the only thing that says what is *in* the note.
///
/// In `Core` and without SwiftUI, so both the editor and the reading view read the same
/// list, and so it can be checked without a view to look at.
enum NoteOutline {
    struct Entry: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case heading(level: Int)
            case embed
        }

        var kind: Kind
        /// The heading's text with its markdown removed: `## Vedi [[Altra nota]]` reads
        /// as "Vedi Altra nota", because an index full of brackets is harder to scan than
        /// the note itself.
        var title: String
        /// The whole line, which is what the editor scrolls to and puts the caret on.
        var range: Range<String.Index>
        /// How far to indent this row. A heading's own level; for an embed, one step
        /// inside the heading it sits under, because that is where it belongs in the
        /// document even though markdown gives it no level of its own.
        var level: Int
    }

    /// Every entry in `text`, in document order.
    ///
    /// Skips the frontmatter, and skips fenced code blocks through `CodeFence.regions` -
    /// a `#` inside a shell block is a comment, and this would be the second place in the
    /// project to get that wrong if it read the rule for itself.
    static func entries(in text: String) -> [Entry] {
        var result: [Entry] = []
        let start = bodyStart(of: text)
        let fences = CodeFence.regions(in: text)
        var enclosingLevel = 1

        for line in lineRanges(in: text, from: start) {
            guard !fences.contains(where: { $0.range.overlaps(line) }) else { continue }
            let trimmed = text[line].trimmingCharacters(in: .whitespaces)

            if let level = headingLevel(of: trimmed) {
                enclosingLevel = level
                result.append(Entry(
                    kind: .heading(level: level),
                    title: plainText(of: String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)),
                    range: line,
                    level: level
                ))
                continue
            }
            // Only an embed on a line of its own. One inside a paragraph is an
            // illustration in a sentence, not a section of the note.
            if let embed = Attachment.embed(inLine: trimmed), !Attachment.isRemote(embed.target) {
                result.append(Entry(
                    kind: .embed,
                    title: embed.alt ?? embed.target,
                    range: line,
                    level: min(enclosingLevel + 1, 6)
                ))
            }
        }
        return result
    }

    /// The level of an ATX heading, or nil when the line is not one.
    ///
    /// The same rule `MarkdownStyler` applies: at most six hashes and a space after them,
    /// so `#tag` at the start of a line stays a tag. Not `private`: `OutlineMove` reuses it
    /// rather than reading the ATX rule a second time.
    static func headingLevel(of trimmedLine: String) -> Int? {
        guard trimmedLine.hasPrefix("#") else { return nil }
        let hashes = trimmedLine.prefix(while: { $0 == "#" }).count
        guard hashes <= 6, trimmedLine.dropFirst(hashes).hasPrefix(" ") else { return nil }
        return hashes
    }

    /// Where the body starts, derived from the one frontmatter parser rather than from a
    /// second reading of the `---` rule: `NoteDocument.body` is literally the tail of the
    /// text, so its length gives the offset.
    private static func bodyStart(of text: String) -> String.Index {
        let document = NoteDocument.parse(text)
        guard document.hasFrontmatterBlock else { return text.startIndex }
        return text.index(text.endIndex, offsetBy: -document.body.count)
    }

    private static func plainText(of text: String) -> String {
        MarkdownInlineParser.spans(in: text).map(\.text).joined()
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
}
