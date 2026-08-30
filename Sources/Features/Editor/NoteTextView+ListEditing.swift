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
        guard replaceAtomically(whole, with: edit.text, in: textView) else { return false }
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
        guard replaceAtomically(whole, with: renumbered, in: textView) else { return }
        textView.setSelectedRange(NSRange(
            location: min(caret, (renumbered as NSString).length), length: 0
        ))
    }
}
