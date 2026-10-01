import Foundation

/// Where a note's frontmatter block sits, in one place for everything that needs its extent:
/// the styler that paints it and the editor pass that can hide it.
enum NoteFrontmatter {
    /// The `---`-delimited block, only when it opens on the very first line.
    ///
    /// The closing `---` is the first line after the opening that starts with it, whichever
    /// ending the line before it has: a `"\n---"` search never matched in a CRLF note, where
    /// `"\r\n"` is one `Character`, so its frontmatter was styled as body (PG-274).
    static func range(in text: String) -> Range<String.Index>? {
        guard text.hasPrefix("---") else { return nil }
        var index = text.index(text.startIndex, offsetBy: 3)
        while let lineEnd = text[index...].firstIndex(where: LineBreak.isTerminator) {
            let lineStart = text.index(after: lineEnd)
            if text[lineStart...].hasPrefix("---") {
                return text.startIndex..<text.index(lineStart, offsetBy: 3)
            }
            index = lineStart
        }
        return nil
    }

    /// Whether the note has a closed frontmatter block.
    static func exists(in text: String) -> Bool {
        range(in: text) != nil
    }
}
