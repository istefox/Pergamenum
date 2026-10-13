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
        textView.noteAliases = noteAliases
        textView.boardTitles = boardTitles
        textView.tagSuggestions = tagSuggestions
        textView.editorCommands = editorCommands
        // The `[[` popup's «Crea «X»» row exists only where something can act on it (ADR-0083 §D6).
        textView.offerCreation = links.offerCreation
        // Attached once, and only where there is something to preview (ADR-0083 §D7).
        if links.preview != nil { coordinator.linkPreview.attach(to: textView) }
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
        let isNoteSwitch = coordinator.requests.claimNotePath(vault.notePath, tab: vault.tabID)
        // A preview of a link in the note that was there is a preview of nothing now (ADR-0083 §D7).
        if isNoteSwitch, links.preview != nil { coordinator.linkPreview.noteChanged() }
        // Only touch the text when the model diverges from what is on screen:
        // reassigning it unconditionally would reset the cursor on every keystroke.
        // Not read at all when the view wrote this very text and nothing has edited it since: the
        // compare is linear in the note, and SwiftUI updates the view after every keystroke
        // (ADR-0094 §D9).
        let viewHoldsTheModel = textView.textStorage?.delegate === coordinator && coordinator.modelSync.viewHolds(text)
        if !viewHoldsTheModel { coordinator.modelSync.countCompare() }
        if !viewHoldsTheModel, textView.string != text {
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
            // The view now holds the model's own value, so the next update finds it without a second
            // whole-note compare (ADR-0095 §D8): one compare per replaced model. The storage heard the
            // assignment synchronously, so a later character edit still sends the next update here.
            coordinator.modelSync.wrote(text)
            textView.setSelectedRange(NSRange(
                location: isNoteSwitch ? 0 : min(selection.location, (text as NSString).length),
                length: 0
            ))
        }
    }

    /// Step 2: the passes, in the order each depends on the one before.
    func runPasses(on textView: CompletingTextView, coordinator: Coordinator) {
        // The dirty range, nothing, or the whole note (ADR-0091 §D8): the second pass of a
        // keystroke `textDidChange` already styled finds nothing to do.
        coordinator.applyStylingIfNeeded(to: textView, theme: theme)
        coordinator.stampOutline(in: textView)
        coordinator.applyEmbeds(to: textView)
        coordinator.applyTransclusions(to: textView, theme: theme)
        // The model's fold offsets as ordinals of the outline the styling just brought up to date
        // (ADR-0095 §D7): nothing folded reads nothing.
        coordinator.applyFolding(
            to: textView, folded: coordinator.foldedOrdinals(of: outline.foldedOffsets, in: textView),
            hidesFrontmatter: outline.hidesFrontmatter, theme: theme
        )
        // After the styling, always: a styling rewrites the attributes it covers and
        // invalidates the layout with them, so a highlight painted before it would be
        // gone by the time anything was drawn.
        coordinator.applyMatches(
            to: textView, matches: find.matches, current: find.currentMatch, theme: theme
        )
        // After the matches, so the find bar's current match is a reveal trigger too
        // (ADR-0018 §D2), and before growing the view so a reveal's height change is
        // already accounted for.
        coordinator.applyReveal(to: textView)
        coordinator.growToFitTheText(textView)
        // After the restyle: a note switch puts the caret at 0 on text that is not styled yet, so
        // the selection notification reported no link, and the styled one has the caret's link
        // only now (ADR-0083 §D3). The ledger drops it when nothing changed.
        coordinator.reportLinkAtCaret(in: textView)
        // And the selection the switch left behind: the ledger was reset with the note, so this
        // reports the new note's selection (none, after the caret went to 0) to the tab that is
        // active now, clearing a range its tab kept from when it was last in front. A no-op
        // everywhere else: one comparison, no write on a bare caret (PG-401).
        coordinator.reportSelection(in: textView)
        // And the index entry, for the same switch: a same-note tab switch fires no selection
        // notification, so the incoming tab's `currentOutlineEntry` would stay what it last held.
        coordinator.reportOutlineEntryAfterSwitch(in: textView)
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

        coordinator.applyCaretRequest(in: textView)
    }
}
