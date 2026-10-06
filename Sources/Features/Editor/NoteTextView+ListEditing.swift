import AppKit

/// Return inside a list item, and the renumbering every other change to an ordered run needs
/// (ADR-0028 §D6, plan `2026-08-29-wysiwyg-markdown-in-workspace` Task 4, R-07/R-08/R-12).
///
/// Wired the way `NoteTextView+EmbedCaret.swift` already is, and beside it on purpose: both are
/// claimants of `CompletingTextView.claimsCommand`, chained in `NoteTextView.wire(_:to:)`, and
/// both write through that file's `replaceAtomically(_:with:in:)` rather than opening a second
/// edit path. `ListContinuation` is the pure core this file feeds - every rule about where a run
/// starts, what continues it and how it is numbered lives there and is tested there
/// (`Tests/ListContinuationTests.swift`); what is here is only the wiring, which is what
/// `Tests/NoteListEditingTests.swift` drives through a real text view.
///
/// In a file of its own for the reason `NoteTextView+Coordinator.swift`'s own header gives:
/// that file is already at the length SwiftLint warns at, and a coordinator concern that grows
/// goes beside it rather than into it - the same split `+Reveal`, `+Embeds`, `+EmbedCaret`,
/// `+EmbedResize`, `+Matches` and `+Transclusion` already are.
extension NoteTextView.Coordinator {
    /// Return inside a list item, claimed before the ordinary newline gets it: the item's own
    /// marker is carried onto the new line, an empty item leaves the list instead, and an
    /// ordered run is made contiguous again around the item that has just gone in.
    ///
    /// False for every other selector, and for a Return anywhere that is not a list item -
    /// `ListContinuation.newline` answering nil is exactly that case, and it is what leaves
    /// `CompletingTextView.doCommand(by:)` to `super` and the note to AppKit's own Return. The
    /// completion panel is asked first regardless, by construction: `doCommand(by:)` consults
    /// `claimsCommand` only while the panel is shut, so choosing a suggestion with Return still
    /// outranks continuing the list the suggestion is being typed into.
    ///
    /// Not gated on `decorations.hidesMarkup`, unlike `claimsEmbedCommand`: continuing a list is
    /// an editing rule rather than a rendering one, so it holds in source mode too.
    ///
    /// **One write, through the mechanism the embed's own two writes already use.** The
    /// insertion and the renumbering it forces come back from `ListContinuation` already applied
    /// to the same string, so they reach the storage as a single replacement and one Cmd+Z takes
    /// both back - rather than leaving a list numbered 1/2/3/4 with the new item gone (R-12).
    func claimsListCommand(_ selector: Selector, in textView: NSTextView) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)),
              let edit = ListContinuation.newline(in: textView.string, at: textView.selectedRange())
        else { return false }
        let whole = NSRange(location: 0, length: (textView.string as NSString).length)
        guard Self.replaceAtomically(whole, with: edit.text, in: textView) else { return false }
        textView.setSelectedRange(edit.selection)
        return true
    }

    /// Makes every ordered run contiguous again after a change that was not a Return - an item
    /// deleted, a list pasted in, a number written by hand (R-08).
    ///
    /// Called from `textDidChange`, so it runs on every keystroke, and `ListContinuation
    /// .renumbered` answering nil for text that needs nothing is what keeps an ordinary one from
    /// pushing an undo step nobody asked for. It re-enters `textDidChange` exactly once - the
    /// write below ends in `didChangeText()`, which is also what restyles the text it just
    /// wrote - and that second pass answers nil, because a run this one has made contiguous has
    /// nothing left to change.
    ///
    /// The caret is put back where it was, clamped, the same way `updateNSView` puts it back
    /// after replacing the whole text. That is exact for every renumbering whose markers keep
    /// their width, which is all of them until a run reaches its tenth item; past that the caret
    /// is a character behind the text until it is next moved.
    func renumberLists(in textView: NSTextView) {
        guard let renumbered = ListContinuation.renumbered(textView.string) else { return }
        let whole = NSRange(location: 0, length: (textView.string as NSString).length)
        let caret = textView.selectedRange().location
        guard Self.replaceAtomically(whole, with: renumbered, in: textView) else { return }
        textView.setSelectedRange(NSRange(
            location: min(caret, (renumbered as NSString).length), length: 0
        ))
    }

    /// Renumbers the ordered run an edit touched, and only that run (ADR-0082 §D6).
    ///
    /// `edited` is the range `textView(_:shouldChangeTextInRanges:replacementStrings:)` recorded
    /// for this change, in the text as it now is. With it, only the covering range of the digits
    /// that change is replaced, through the same `replaceAtomically` the whole-text form uses, so
    /// the keystroke and its renumbering stay one undo step, and the caret is carried through the
    /// rewrite by `Renumbering.mapping`: a run's tenth item shrinking to a ninth no longer leaves
    /// it a character ahead. A misnumbered list elsewhere in the note is left as it is until it is
    /// itself edited.
    ///
    /// Without a recorded range (an undo, a redo, a change nobody typed) this is the whole-text
    /// `renumberLists(in:)`, caret clamped as before. The write's own `didChangeText()` re-enters
    /// `textDidChange` with the range this replacement recorded, and that pass answers nil: the
    /// run it reaches is already contiguous.
    func renumberLists(in textView: NSTextView, touching edited: NSRange?) {
        guard let edited else {
            renumberLists(in: textView)
            return
        }
        guard let rewrite = ListContinuation.renumbered(textView.string, touching: edited) else { return }
        let caret = textView.selectedRange().location
        guard Self.replaceAtomically(rewrite.range, with: rewrite.replacement, in: textView) else { return }
        textView.setSelectedRange(NSRange(
            location: min(rewrite.mapping(caret), (textView.string as NSString).length), length: 0
        ))
    }

    /// Records where a change lands before AppKit makes it, for the scoped renumber
    /// (ADR-0082 §D6). Always allows the change: this delegate method only watches.
    ///
    /// The recorded range is the union of the replacement ranges as they will stand after the
    /// change - each range's location moved by the length changes before it, and its length the
    /// replacement's own - so `textDidChange` can hand `renumberLists(in:touching:)` a range of
    /// the text it sees. Nothing is recorded while the undo manager is undoing or redoing: an undo
    /// restores a whole earlier text, and the whole-text fallback is the honest answer for it.
    func textView(
        _ textView: NSTextView, shouldChangeTextInRanges affectedRanges: [NSValue], replacementStrings: [String]?
    ) -> Bool {
        if let undo = textView.undoManager, undo.isUndoing || undo.isRedoing {
            renumbering.editedRange = nil
            return true
        }
        var shift = 0
        var union: NSRange?
        for (index, value) in affectedRanges.enumerated() {
            let range = value.rangeValue
            let length = replacementStrings.flatMap { index < $0.count ? ($0[index] as NSString).length : nil }
                ?? range.length
            let landed = NSRange(location: range.location + shift, length: length)
            union = union.map { NSUnionRange($0, landed) } ?? landed
            shift += length - range.length
        }
        renumbering.editedRange = union
        return true
    }
}

/// The range the last change landed on, between `shouldChangeTextInRanges` recording it and
/// `textDidChange` taking it (ADR-0082 §D6). Its own type, held by the coordinator as one stored
/// property, the shape ADR-0074 §D2 gives every feature's state.
@MainActor
final class ListRenumberLedger {
    var editedRange: NSRange?

    /// The recorded range, cleared as it is read, so a change that skipped the recording (a
    /// programmatic replacement) never inherits the previous keystroke's range.
    func take() -> NSRange? {
        defer { editedRange = nil }
        return editedRange
    }
}
