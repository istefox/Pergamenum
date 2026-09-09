import AppKit

/// Which of a card's paragraphs are drawn with their raw markdown showing (ADR-0028 §D1,
/// R-03, R-04).
///
/// A file of its own for the reason `NoteTextView+Reveal.swift` is one: reveal is a
/// self-contained concern, and `CardTextView.swift` reached SwiftLint's file length when it
/// arrived. The rule itself is not restated here - `MarkupReveal.paragraphs` is the note
/// editor's own pure function, called rather than reimplemented, so a card and a note cannot
/// disagree about which paragraphs a selection touches.
extension CardTextView.Coordinator {
    /// The caret's paragraph while the card is being written into (R-03), and nothing at all
    /// while it is at rest, where every marker stays concealed (R-04). Returns what it
    /// published, so a caller - and a test - can read the answer without reaching into the
    /// delegate's private table.
    ///
    /// `isEditable` decides, never where the selection happens to sit: a card at rest keeps
    /// whatever selection AppKit last left in it, and a board showing one line of raw `- ` per
    /// card because of that is the whole of R-04 lost.
    ///
    /// Only the paragraphs whose state changed are re-read, never the document - this runs on
    /// every arrow key, the same restraint `NoteTextView+Reveal.swift:66-88` keeps.
    @discardableResult
    func applyReveal(to textView: NSTextView) -> Set<Int> {
        // `hasMarkedText()` first, rather than trusting `markedRange()` to answer `NSNotFound`
        // when there is no composition: measured on a text view with no input context attached
        // - which is a card in a preview, a card in a test, and a card whose view is not in a
        // window yet - it answers `{length, 0}` instead, and `MarkupReveal` would read that as
        // the document's last paragraph and reveal it beside the caret's own.
        let selection = textView.selectedRange()
        let markedRange = textView.hasMarkedText()
            ? textView.markedRange()
            : NSRange(location: NSNotFound, length: 0)
        let revealed: Set<Int> = textView.isEditable
            ? MarkupReveal.paragraphs(
                in: textView.string,
                selection: selection,
                markedRange: markedRange,
                // Nil, and not a card-side equivalent: ADR-0018 §D2's fourth trigger is the
                // find bar's current match, and a card has no find bar to have one.
                currentMatch: nil
            )
            : []
        // ADR-0037 §D8: narrowed to span only while the card is being written into, exactly
        // the gate `revealed` above already applies - a card at rest reveals nothing regardless
        // of the setting (R-04 of ADR-0028 is not weakened by this addition).
        let revealedSpans: [Int: [NSRange]] = (textView.isEditable && parent.revealsInlineSpans)
            ? MarkupReveal.inlineSpans(
                in: textView.string, selection: selection, markedRange: markedRange, currentMatch: nil
              )
            : [:]
        // Both must be unchanged to skip work (ADR-0037 §D6) - a caret held still while only
        // the setting flips must still redraw, which a guard on `lastRevealed` alone would miss.
        guard revealed != lastRevealed || revealedSpans != lastRevealedSpans else { return revealed }
        lastRevealed = revealed
        lastRevealedSpans = revealedSpans

        let changedParagraphs = decorations.apply(revealedParagraphs: revealed)
        let changedSpans = decorations.apply(revealedSpans: revealedSpans)
        let changed = changedParagraphs.union(changedSpans)
        guard !changed.isEmpty, let storage = textView.textStorage else { return revealed }
        let text = storage.string as NSString
        storage.beginEditing()
        for offset in changed where offset < text.length {
            storage.edited(
                .editedAttributes,
                range: text.paragraphRange(for: NSRange(location: offset, length: 0)),
                changeInLength: 0
            )
        }
        storage.endEditing()
        return revealed
    }
}
