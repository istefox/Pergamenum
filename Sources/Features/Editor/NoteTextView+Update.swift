import AppKit
import SwiftUI

// `updateNSView`'s four steps, in the order it calls them (PG-144 Task 5). Each reads this
// view's inputs at the moment the undivided method did, and none reorders a side effect: the
// text sync precedes every pass, the passes precede the insertion, and the insertion precedes
// the one-shots.

extension NoteTextView {
    /// Step 1: hands the coordinator this value, pushes the plain properties to the text view,
    /// and syncs its text with the model, placing the caret for a note switch.
    func pushInputs(to textView: CompletingTextView, coordinator: Coordinator) {
        coordinator.parent = self
        coordinator.undoManager = textView.window?.undoManager
        textView.noteTitles = noteTitles
        textView.boardTitles = boardTitles
        textView.tagSuggestions = tagSuggestions
        textView.editorCommands = editorCommands
        // Re-applied on every update rather than only at build time: turning the checker on
        // in Impostazioni has to reach the note already open, not the next one.
        apply(spellCheck, to: textView)
        // The same reason, for the readable-width column: the frame observation answers a
        // resize, and this answers the setting being turned on or off (ADR-0030 §D6, R-10).
        // Before the styling below, since the inset decides where the text wraps and every
        // height measured after it depends on that.
        coordinator.applyReadableWidth(to: textView)

        // Compared and recorded on every update, read only inside the branch below. Claimed
        // ahead of the text sync rather than after it: nothing the sync triggers reads it.
        let isNoteSwitch = coordinator.requests.claimNotePath(vault.notePath)
        // Only touch the text when the model diverges from what is on screen:
        // reassigning it unconditionally would reset the cursor on every keystroke.
        if textView.string != text {
            // This view is one persistent instance per editor column (never rebuilt per
            // note), so a genuine note switch and the same note's content changing
            // externally (undo, sync) both land here. Carrying the old raw offset forward
            // is right for the second case but wrong for the first: with no per-note caret
            // bookmark anywhere in this app, a switched-to note's caret at whatever numeric
            // offset the previous note happened to leave behind can - and did (issue #188)
            // - land inside a paragraph whose markup reveal-on-caret (ADR-0018 §D2) then
            // never gets a reason to re-hide. `vault.notePath` is the one signal available to
            // tell the two cases apart.
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(
                location: isNoteSwitch ? 0 : min(selection.location, (text as NSString).length),
                length: 0
            ))
        }
    }

    /// Step 2: the passes, in the order each depends on the one before.
    func runPasses(on textView: CompletingTextView, coordinator: Coordinator) {
        coordinator.applyStyling(to: textView, theme: theme)
        coordinator.applyEmbeds(to: textView)
        coordinator.applyTransclusions(to: textView, theme: theme)
        coordinator.applyFolding(to: textView, folded: outline.foldedEntries, theme: theme)
        // After the styling, always: `applyStyling` rewrites every attribute in the storage
        // and invalidates the layout with them, so a highlight painted before it would be
        // gone by the time anything was drawn.
        coordinator.applyMatches(
            to: textView, matches: find.matches, current: find.currentMatch, theme: theme
        )
        // After the matches, so the find bar's current match is a reveal trigger too
        // (ADR-0018 §D2), and before growing the view so a reveal's height change is
        // already accounted for.
        coordinator.applyReveal(to: textView)
        coordinator.growToFitTheText(textView)
    }

    /// Step 3: applies the Inserisci menu's text at the cursor, and opens the query builder
    /// on the fence it wrote when the insertion asks for it.
    func consumeInsertion(in textView: CompletingTextView, coordinator: Coordinator) {
        guard let insertion else { return }
        // After the text sync above, so the insertion is not overwritten by the
        // model value that predates it.
        let insertionRange = textView.selectedRange()
        textView.insertText(insertion.text, replacementRange: insertionRange)
        let cursor = textView.selectedRange().location - insertion.cursorBack
        textView.setSelectedRange(NSRange(location: max(0, cursor), length: 0))
        onInsertionApplied()

        // R-04: "Inserisci ▸ Vista…" opens the query builder on the fence it just wrote,
        // in the same gesture (ADR-0034 §D10). The opening offset is the stub's own
        // convention (`ViewQueryText.stub`'s `head`/`openingOffset`): a leading `\n` -
        // needed only when the caret was mid-line - moves the fence one character in,
        // nothing else does. Read from the live characters rather than from
        // `viewBlocks.drawn`, which is gated on `hidesMarkup` (ADR-0033 §D12) and would
        // stay empty for an editor with markup-hiding off.
        guard insertion.opensQueryBuilder, let onEditQuery = vault.onEditQuery else { return }
        let openingOffset = insertionRange.location + (insertion.text.hasPrefix("\n") ? 1 : 0)
        let nsText = textView.string as NSString
        guard let recognised = EditorDecorationDelegate.viewBlockRun(
            in: nsText, atParagraphStart: openingOffset
        ) else { return }
        // The body alone, opening and closing fence lines split off - the same helper
        // "Modifica query" on a drawn fence reads it through.
        let source = Coordinator.viewBlockBody(in: nsText, range: recognised.range)
        let request = ViewQueryEditRequest(id: UUID(), source: source) { [weak textView] body in
            guard let textView else { return false }
            return coordinator.commitViewBlock(body, at: openingOffset, in: textView)
        }
        onEditQuery(request)
    }

    /// Step 4: the one-shots, each consumed once against the coordinator's bookkeeping.
    func consumeOneShots(in textView: CompletingTextView, coordinator: Coordinator) {
        if coordinator.requests.claimFocus(focusRequest) {
            coordinator.takeFocus()
        }

        if find.findRequest != nil {
            // The selection as it is *now*, before anything else in this pass moves it. This
            // is the whole of the scope: `FindSession.open` decides whether it is wide enough
            // to be one.
            find.onFindApplied(textView.selectedRange())
        }

        if let replacements = find.replacements, !coordinator.alreadyApplied(replacements) {
            coordinator.apply(replacements, to: textView)
            find.onReplacementsApplied()
        }

        // Consumed by location, so stepping onto a different match scrolls and every other
        // view update does not - the same guard the focus and scroll claims are. Cleared when
        // the bar closes, so reopening on the same match scrolls again.
        if coordinator.requests.claimMatchJump(to: find.matchJump?.location) {
            if let matchJump = find.matchJump { coordinator.scroll(textView, to: matchJump, takingFocus: false) }
        }

        if let scrollRequest = outline.scrollRequest, coordinator.requests.claimScroll(scrollRequest.id) {
            coordinator.scroll(textView, to: scrollRequest.range)
            outline.onScrollApplied()
        }
    }
}
