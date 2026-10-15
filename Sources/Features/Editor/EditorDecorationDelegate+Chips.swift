import AppKit

/// ADR-0087's half of `EditorDecorationDelegate`: the re-validation of the six marker kinds N5 adds,
/// the `.kern` room a concealed pill delimiter leaves, and which drawn fragment a paragraph gets.
/// Its own file because the main one sits against its length cap (plan N5, Realignment 8).
extension EditorDecorationDelegate {
    /// One marker of a displayed copy drawn at `collapsedFont`. A pill's concealed delimiter keeps
    /// the room the pill stands in as `.kern` on its last character (ADR-0087 §D5): the character
    /// count never changes, and the room sits inside the run the painter measures.
    func collapse(_ marker: HiddenMarker, in copy: NSMutableAttributedString) {
        copy.addAttribute(.font, value: Self.collapsedFont, range: marker.range)
        switch marker.kind {
        case .inlineCode, .highlight, .embedChip:
            guard marker.range.length > 0 else { return }
            let last = NSRange(location: NSMaxRange(marker.range) - 1, length: 1)
            // An embed chip's `![[` also leaves the room its file-type symbol is painted in (§D9).
            let chip = constructStyle.chip
            let opensEmbed = marker.kind == .embedChip && copy.attributedSubstring(from: marker.range).string == "![["
            copy.addAttribute(.kern, value: chip.padding + (opensEmbed ? chip.symbol : 0), range: last)
        case .fenceOpening, .fenceClosing:
            // A line of collapsed characters is a few hundredths of a point tall: the row the
            // header's badge or the closing rule is drawn in is bought here (§D6).
            guard copy.length > 0 else { return }
            let style = NSMutableParagraphStyle()
            if let current = copy.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
                style.setParagraphStyle(current)
            }
            let font = constructStyle.badgeFont
            style.minimumLineHeight = marker.kind == .fenceOpening
                ? ceil(font.ascender - font.descender) + 2 * constructStyle.chip.padding
                : 3 * constructStyle.chip.padding
            copy.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: copy.length))
        default:
            break
        }
    }

    /// Whether a marker of one of ADR-0087's kinds still spells what the styling pass recorded,
    /// read from the characters as they are now - the generic path's rule for every kind
    /// (`stillSpells`), so a stale entry never collapses prose.
    static func stillSpellsAConstructMarker(_ kind: HiddenMarker.Kind, _ text: NSString, at range: NSRange) -> Bool {
        guard range.location >= 0, range.length > 0, NSMaxRange(range) <= text.length else { return false }
        let run = text.substring(with: range)
        switch kind {
        // A backtick run of any length (CommonMark's code span), and a highlight's two `=`.
        case .inlineCode: return run.allSatisfy { $0 == "`" }
        case .highlight: return run == "=="
        // A whole fence line, opening or closing: `CodeFence.marks` is the one predicate.
        case .fenceOpening, .fenceClosing:
            return CodeFence.marks(run.trimmingCharacters(in: .whitespaces))
        // The `> [!type]` run with its sign and one space, exactly as long as the header reads it.
        case .calloutMarker: return Callout.header(inLine: run)?.markerLength == range.length
        // An inline embed's `![[` or its closing `|W]]`/`]]`.
        case .embedChip: return run == "![[" || (run.hasSuffix("]]") && !run.contains("[["))
        default: return false
        }
    }

    /// The fragment a paragraph is drawn by when it is none of the delegate's older constructs: a
    /// fence line's chrome, a quote's bars or a callout's card (each paints its pills), else a
    /// chip-aware line for a paragraph whose displayed text carries a pill, else nil for the
    /// standard fragment.
    func constructFragment(for textElement: NSTextElement, at start: Int) -> NSTextLayoutFragment? {
        if let fence = fenceFragment(for: textElement, at: start) { return fence }
        if let quote = quoteFragment(for: textElement, at: start) { return quote }
        guard hidesMarkup, let paragraph = textElement as? NSTextParagraph,
              InlineChipPainter.carriesChips(paragraph.attributedString)
        else { return nil }
        let fragment = ChipLineFragment(textElement: textElement, range: textElement.elementRange)
        fragment.metrics = constructStyle.chip
        return fragment
    }
}
