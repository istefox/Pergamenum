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
    /// itself at this offset. A heading with no title registers no marker (`MarkdownStyler`), so
    /// it is nil too.
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
}
