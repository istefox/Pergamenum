import Foundation

/// What opens and closes a fenced code block, in one place.
///
/// Two things in this app need to know: `MarkdownBlockParser`, which reads a note into
/// blocks for the reading view, and `MarkdownStyler`, which colours the source in the
/// editor. They traverse differently - the parser consumes an array of lines, the styler
/// needs indices into the text - so they cannot share a loop. They can share the rule,
/// and they must: two spellings of "this line is a fence" is exactly the kind of pair
/// that drifts silently until a note renders one way and edits another.
enum CodeFence {
    /// A fence line, opening or closing.
    ///
    /// One predicate for both, because that is what the reading view has always done: any
    /// line starting with three backticks ends an open fence, info string or not. CommonMark
    /// is stricter - a closing fence carries no info string - and adopting that here would
    /// change how existing notes render, which is a decision, not a detail.
    static func marks(_ trimmedLine: some StringProtocol) -> Bool {
        trimmedLine.hasPrefix("```")
    }

    /// The language written after the backticks, or nil when the fence declares none.
    static func language(declaredBy trimmedLine: some StringProtocol) -> String? {
        guard marks(trimmedLine) else { return nil }
        let declared = trimmedLine.dropFirst(3).trimmingCharacters(in: .whitespaces)
        return declared.isEmpty ? nil : declared
    }

    /// One fenced block, located in the text it came from.
    struct Region: Equatable, Sendable {
        /// The whole block, opening and closing lines included: what gets a background.
        var range: Range<String.Index>
        /// The code between the fences, which is what a grammar is run over. Empty for a
        /// fence with nothing in it.
        var body: Range<String.Index>
        var language: String?
    }

    /// Every fenced block in `text`, in order.
    ///
    /// An unclosed fence runs to the end of the text rather than off it - the same choice
    /// `MarkdownBlockParser` makes, and for the same reason: while someone is typing the
    /// opening backticks, every note is briefly a note with an unclosed fence.
    static func regions(in text: String) -> [Region] {
        var regions: [Region] = []
        var open: Opening?

        for line in lineRanges(in: text) {
            let trimmed = text[line].trimmingCharacters(in: .whitespaces)
            guard marks(trimmed) else { continue }

            if let current = open {
                regions.append(Region(
                    range: current.start..<line.upperBound,
                    // A fence closed on the line right after it opens has no body at all,
                    // and `bodyStart` is then already past `line.lowerBound`.
                    body: current.bodyStart..<max(current.bodyStart, line.lowerBound),
                    language: current.language
                ))
                open = nil
            } else {
                // The body starts on the next line; when the opening fence is the last
                // line of the note there is no next line, and the body is empty.
                let afterLine = line.upperBound < text.endIndex
                    ? text.index(after: line.upperBound)
                    : text.endIndex
                open = Opening(start: line.lowerBound, bodyStart: afterLine, language: language(declaredBy: trimmed))
            }
        }

        if let current = open {
            regions.append(Region(
                range: current.start..<text.endIndex,
                body: current.bodyStart..<text.endIndex,
                language: current.language
            ))
        }
        return regions
    }

    /// A fence that has been opened and not yet closed, which is the state a note is in
    /// for as long as it takes to type the second row of backticks.
    private struct Opening {
        let start: String.Index
        let bodyStart: String.Index
        let language: String?
    }

    /// Line ranges excluding the newline, empty lines included - unlike the styler's own
    /// helper, which skips them because it has nothing to style on an empty line.
    private static func lineRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        while start <= text.endIndex {
            let end = text[start...].firstIndex(of: "\n") ?? text.endIndex
            ranges.append(start..<end)
            guard end < text.endIndex else { break }
            start = text.index(after: end)
        }
        return ranges
    }
}
