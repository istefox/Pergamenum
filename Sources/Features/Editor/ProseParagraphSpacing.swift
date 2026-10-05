import AppKit

/// Which source lines of a note get the gap after a prose paragraph, and how it is put on them
/// (n1-seams R-14).
///
/// Per source line, not per markdown paragraph: the editor draws one line of source as one
/// TextKit paragraph, so a prose or heading line takes `spacing.paragraph` below itself. A line
/// is left alone when it is blank, or when any span that gives a line a shape of its own touches
/// it - frontmatter, a code fence, a table, a view block, a list item, a task, a quote, a rule, a
/// Pratiche anchor, an embed or transclusion. Those keep the spacing their own pass gives them
/// (a transclusion's reserved height, above all), and a list keeps its items tight.
///
/// Editor only: the Workspace card and the transclusion picture
/// (`MarkdownAttributedText.attributed`) do not call this.
enum ProseParagraphSpacing {
    /// What makes a line not blank, built once rather than per line.
    private static let nonWhitespace = CharacterSet.whitespaces.inverted

    /// The whole-line ranges, newline included, of every prose and heading line in `text`.
    /// `spans` are `MarkdownStyler.spans(in: text)`, passed in because the styling pass already
    /// has them.
    static func paragraphRanges(in text: String, spans: [MarkdownStyler.StyledRange]) -> [NSRange] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        // Range-based, so asking a line about it costs a lookup and not a walk of every span.
        var excluded = IndexSet()
        for styled in spans where shapesItsLine(styled.span) {
            let range = NSRange(styled.range, in: text)
            guard range.location != NSNotFound, range.length > 0 else { continue }
            excluded.insert(integersIn: range.location..<NSMaxRange(range))
        }

        var ranges: [NSRange] = []
        var cursor = 0
        while cursor < nsText.length {
            let line = nsText.lineRange(for: NSRange(location: cursor, length: 0))
            cursor = NSMaxRange(line)
            let content = contentRange(of: line, in: nsText)
            // Blank is "nothing but `.whitespaces`", asked of the string in place: this runs on
            // every keystroke, so no line is copied out to be trimmed.
            guard content.length > 0,
                  nsText.rangeOfCharacter(from: Self.nonWhitespace, range: content).location != NSNotFound,
                  !excluded.intersects(integersIn: content.location..<NSMaxRange(content))
            else { continue }
            ranges.append(line)
        }
        return ranges
    }

    /// The styling pass's one call: `spacing` onto every prose and heading line of `text`. A
    /// zero gap is what every line already carries, so the per-line walk is skipped outright.
    static func apply(
        _ spacing: CGFloat, to storage: NSMutableAttributedString, text: String, spans: [MarkdownStyler.StyledRange]
    ) {
        guard spacing != 0 else { return }
        merge(spacing, into: storage, ranges: paragraphRanges(in: text, spans: spans))
    }

    /// Sets `spacing` as the `paragraphSpacing` of every paragraph style under `ranges`, each
    /// style otherwise kept as it is: merged, never replaced, so the page's line-height multiple
    /// and a heading's own style survive (ADR-0030 §D5).
    static func merge(_ spacing: CGFloat, into storage: NSMutableAttributedString, ranges: [NSRange]) {
        for range in ranges where NSMaxRange(range) <= storage.length {
            storage.enumerateAttribute(.paragraphStyle, in: range) { value, run, _ in
                let style = NSMutableParagraphStyle()
                if let existing = value as? NSParagraphStyle { style.setParagraphStyle(existing) }
                style.paragraphSpacing = spacing
                storage.addAttribute(.paragraphStyle, value: style, range: run)
            }
        }
    }

    /// The spans that make their line something other than prose. Exhaustive on purpose: a
    /// span added to `MarkdownStyler` later has to say which side it is on.
    private static func shapesItsLine(_ span: MarkdownStyler.Span) -> Bool {
        switch span {
        case .frontmatter, .codeBlock, .tableRun, .viewBlockRun, .listMarker, .taskMarker,
             .blockquoteMarker, .horizontalRule, .messageAnchor, .embedRun:
            true
        case .heading, .headingMarker, .bold, .italic, .emphasisMarker, .strikethrough,
             .strikethroughMarker, .code, .codeToken, .tag, .scheduled, .due, .annotation,
             .linkSyntax, .linkTarget, .embedTarget:
            false
        }
    }

    /// `line` without its line break.
    private static func contentRange(of line: NSRange, in text: NSString) -> NSRange {
        var content = line
        while content.length > 0 {
            let last = text.character(at: NSMaxRange(content) - 1)
            guard last == 10 || last == 13 else { break }
            content.length -= 1
        }
        return content
    }
}
