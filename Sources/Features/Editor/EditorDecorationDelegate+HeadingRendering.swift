import AppKit

/// The heading half of `EditorDecorationDelegate`'s substitution mechanism (ADR-0081 §D4), split
/// out the way `+ListRendering.swift` and `+QuoteRendering.swift` are: one concern, one
/// `extension` file, and the main file stays clear of SwiftLint's length limit.
extension EditorDecorationDelegate {
    /// The heading branch of `textContentStorage(_:textParagraphWith:)`: a revealed heading's
    /// `#` run and its space drawn in `markerFont` and hung in the gutter, its first line starting
    /// `w` before the gutter (`w` the run measured in that face, clamped at zero), so the title
    /// stays where its concealed twin puts it. An attribute change and nothing else: the
    /// paragraph keeps its stored length (`NSTextContentManager.h:120`).
    ///
    /// Nil - leaving the heading to the generic path, which conceals it or shows it raw exactly
    /// as before - when the setting is off, there is no gutter to hang in (a card, ADR-0081 §D6),
    /// no marker face was pushed, the paragraph is not revealed, or no heading marker still spells
    /// itself at this offset. A heading with no title hangs too: `MarkdownStyler` registers no
    /// marker for it, so the coordinator registers its run (`titlelessHeadingRun`, PG-425).
    func headingParagraph(at range: NSRange, storage: NSTextStorage) -> NSTextParagraph? {
        // Its own guard rather than the caller's, as `quoteParagraph` has: this branch can be
        // reached directly, and ADR-0018 §D10's switch has to mean off wherever it is asked.
        guard hidesMarkup, gutter > 0, let face = markerFont, revealedParagraphs.contains(range.location),
              let marker = marker(of: .heading, at: range)
        else { return nil }

        let text = storage.string as NSString
        guard !Self.survivors(among: [marker], of: range, in: text).isEmpty else { return nil }

        // The generic path's copy, so an inline span inside a revealed heading follows
        // ADR-0037's reveal exactly as it did when this paragraph fell through to it.
        let copy = collapsedCopy(at: range, storage: storage)
            ?? NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        copy.addAttribute(.font, value: face, range: marker.range)

        let style = NSMutableParagraphStyle()
        // Composed on the heading's own style, which already carries the gutter as its indents,
        // the heading's line height and the paragraph gap: only the first line's indent moves.
        if let base = Self.bodyParagraphStyle(of: copy) { style.setParagraphStyle(base) }
        let run = text.substring(
            with: NSRange(location: range.location + marker.range.location, length: marker.range.length)
        )
        style.firstLineHeadIndent = max(0, gutter - markerWidths.width(of: run, in: face))
        copy.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: copy.length))
        return NSTextParagraph(attributedString: copy)
    }

    /// The `#` run and the one space after it of a heading with no title yet (`# `, `###   `), in
    /// `note`'s coordinates, or nil for a heading with a title. `span` is the styler's `.heading`
    /// span or a paragraph; only its first line is read, split and classified as the styler splits
    /// and classifies it (`lineTokens`, `LineBreak.isTerminator`), and "no title" is the test the
    /// styler asks, `MarkdownBlockParser.headingHasNoTitle` (PG-425).
    ///
    /// The styler registers no `.headingMarker` there, so that concealing the run cannot shrink
    /// the row to nothing; without a marker a revealed one had no run to hang in the gutter. The
    /// coordinator registers this run as a `.heading` marker instead, which `headingParagraph`
    /// hangs and the generic path never collapses (`isTitlelessHeading`).
    static func titlelessHeadingRun(in span: NSRange, of note: NSString) -> NSRange? {
        guard NSMaxRange(span) <= note.length else { return nil }
        let source = note.substring(with: span)
        guard let token = MarkdownBlockParser.lineTokens(in: source, endsLine: LineBreak.isTerminator).first,
              case .heading(_, let marker) = token.kind,
              MarkdownBlockParser.headingHasNoTitle(source[token.range], marker: marker)
        else { return nil }
        let run = NSRange(marker, in: source)
        return NSRange(location: span.location + run.location, length: run.length)
    }

    /// Whether `marker` is the run `titlelessHeadingRun` answers for `paragraph`: a heading run
    /// with nothing after it on its line but spaces. Concealed, it stays on screen as it always
    /// has, raw, rather than collapsing a row that holds nothing else (`MarkdownStyler`).
    static func isTitlelessHeading(_ marker: HiddenMarker, of paragraph: NSRange, in text: NSString) -> Bool {
        guard marker.kind == .heading, NSMaxRange(marker.range) <= paragraph.length else { return false }
        let absolute = NSRange(location: paragraph.location + marker.range.location, length: marker.range.length)
        return titlelessHeadingRun(in: paragraph, of: text) == absolute
    }
}
