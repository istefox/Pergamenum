import AppKit

/// The renumbering every change to a card's ordered run that was *not* a Return needs
/// (ADR-0028 §D6, plan `2026-08-29-wysiwyg-markdown-in-workspace` Task 6, R-08/R-12).
///
/// The card's half of `NoteTextView+ListEditing.renumberLists(in:)`, calling the same pure
/// `ListContinuation.renumbered` rather than spelling the rule a second time - what a contiguous
/// run is, and which ordinal a run starts from, is one answer for both surfaces or it is two
/// answers that drift.
///
/// In a file of its own for the reason `CardTextView+Reveal.swift` is one: `CardTextView.swift`
/// is already at the length SwiftLint warns at, and a coordinator concern that grows goes beside
/// it rather than into it.
extension CardTextView.Coordinator {
    /// Makes every ordered run in the card contiguous again after a change that was not a Return -
    /// an item deleted, a list pasted in, a number written over by hand (R-08).
    ///
    /// Called from `textDidChange`, so it runs on every keystroke, and `ListContinuation
    /// .renumbered` answering nil for a text that needs nothing is what keeps an ordinary one from
    /// pushing an undo step nobody asked for. That same nil is the re-entrancy guard: the write
    /// below ends in `didChangeText()`, which re-enters `textDidChange` and reaches this method a
    /// second time, and a run this pass has just made contiguous has nothing left to change. No
    /// flag of its own, deliberately - the pure function's own contract already stops it.
    ///
    /// The caret is put back where it was, clamped, the same way `updateNSView` puts it back after
    /// replacing the whole text. That is exact for every renumbering whose markers keep their
    /// width, which is all of them until a run reaches its tenth item; past that the caret is a
    /// character behind the text until it is next moved.
    ///
    /// **No undo group opened by hand.** The edit that triggered this pass and the write it makes
    /// are two registrations on the card's own manager inside one event, which
    /// `UndoManager.groupsByEvent` already puts in a single top-level group (ADR-0027 §D2) - so
    /// one Cmd+Z gives back the deleted item *and* the numbering that closed over it, rather than
    /// a list still renumbered around a hole. That is a claim about AppKit rather than about
    /// either write, which is why it is asserted rather than assumed, by
    /// `Tests/CardFormattingTests.swift`'s
    /// `deletingAMiddleItemOfACardsOrderedRunRenumbersTheRestAndOneUndoTakesBothBack`.
    func renumberLists(in textView: FormattingTextView) {
        guard let renumbered = ListContinuation.renumbered(textView.string) else { return }
        let caret = textView.selectedRange().location
        textView.replaceWholeText(
            with: renumbered,
            selecting: NSRange(
                location: min(caret, (renumbered as NSString).length), length: 0
            )
        )
    }
}
