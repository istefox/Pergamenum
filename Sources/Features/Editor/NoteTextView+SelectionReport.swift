import AppKit

// PG-387 (N4), ADR-0085 §D8 and ADR-0086 §D4, plan docs/plans/pg-387-n4-birth-of-note.md, Tasks 6
// and 7 - R-08, R-13. Its own file because `NoteTextView.Coordinator`'s body is at the length the
// linter allows: `textViewDidChangeSelection` calls `reportSelection` in one line, and
// `consumeOneShots` calls `applyCaretRequest` in one line.

extension NoteTextView.Coordinator {
    /// Reports the non-empty selection through `selection.onSelectionChanged`, once per change, and
    /// nil once when it collapses. A bare caret moving, or typing with one, reports nothing: the
    /// tab's `selection` is written only when it changes (ADR-0085 §D8).
    func reportSelection(in textView: NSTextView) {
        guard let report = parent.selection.onSelectionChanged else { return }
        let range = textView.selectedRange()
        let selection: NSRange? = range.length > 0 ? range : nil
        guard requests.claimSelection(selection) else { return }
        report(selection)
    }

    /// Reports the index entry the caret is in, when it changed since the last report.
    func reportOutlineEntry(in textView: NSTextView) {
        let caret = textView.selectedRange().location
        let entry = parent.outline.outlineRanges.lastIndex { $0.location <= caret }
        guard requests.claimOutlineEntry(entry) else { return }
        parent.outline.onOutlineEntryChanged?(entry)
    }

    /// The same report for a tab or note switch, which moves the caret without a selection
    /// notification when the text is unchanged (two tabs of one note): the ledger was reset with
    /// the switch, so `lastOutlineEntry` is unreported only then. Every other pass, a keystroke
    /// included, is that one comparison and no walk of the index or write (PG-401).
    func reportOutlineEntryAfterSwitch(in textView: NSTextView) {
        guard requests.lastOutlineEntry == nil else { return }
        reportOutlineEntry(in: textView)
    }

    /// Places the caret at the request's offset once, clamped to the text, and takes the keyboard
    /// (ADR-0086 §D4): the daily note's `{{cursor}}`, a composed note's body caret.
    ///
    /// The keyboard goes through `takeFocus()`, not `scroll`'s own `makeFirstResponder`: the request
    /// is usually already there on the text view's first update, when the view is not in a window
    /// yet, and `makeFirstResponder` on no window is a silent no-op that the claim above would never
    /// give a second chance - the first key typed after Cmd+Shift+D landed nowhere (R-08).
    /// `takeFocus()` retries once on the next pass.
    func applyCaretRequest(in textView: NSTextView) {
        let request = parent.selection.caretRequest
        guard let request, requests.claimCaret(request) else { return }
        let length = (textView.string as NSString).length
        scroll(textView, to: NSRange(location: min(max(0, request.offset), length), length: 0), takingFocus: false)
        takeFocus()
        parent.selection.onCaretApplied()
    }
}
