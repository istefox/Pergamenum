import AppKit

/// The edit path `textDidChange` runs, and the two hooks that replay it for the operations that
/// change the text without posting `NSText.didChangeNotification` (ADR-0093 §D7).
///
/// Measured on the real path (ADR-0093, "The real edit path"): an undo and a redo by the window's
/// undo manager, and a `setMarkedText` that starts or replaces a composition, each change the storage
/// and post no change notification, so the incremental restyle was left owing the lines they rewrote.
/// The undo manager's did-undo and did-redo notifications and `CompletingTextView`'s marked-text
/// override call `replayEditIfUnstyled(in:)`, which runs the same passes, and only while an edit is
/// still unstyled: a path that did post the notification has been styled already and replays nothing.
///
/// In a file of its own for the reason `NoteTextView+ListEditing.swift`'s header gives: the
/// coordinator's own file is at the size SwiftLint allows.
extension NoteTextView.Coordinator {
    /// `textDidChange`'s body after its guard: the binding, the styling, the passes after it, the
    /// grow-to-fit and the completion panel. `renumbering` is false for a replay: the undo manager has
    /// finished by the time its notification arrives, so a renumber written there would be a new edit
    /// and empty the redo stack, and the text an undo restores was renumbered when it was first written.
    /// `completing` is false for a composition step: the marked text is not a word the person has
    /// written yet, so the step never opens a panel (the commit posts `textDidChange`, which does),
    /// but a panel already open is still refreshed, because that refresh is the only thing that
    /// closes it when the marked text ends its context.
    func runEditPasses(in textView: NSTextView, renumbering renumbers: Bool, completing: Bool = true) {
        let written = textView.string
        parent.text = written
        modelSync.wrote(written)
        applyStylingIfNeeded(to: textView, theme: parent.theme)
        // The binding was written first, so the stamp is the revision this keystroke made; and an edit
        // that made or unmade an entry above the caret is reported now, not at the next caret move
        // (ADR-0096 §D6, §D7). The ledger drops a repeat.
        stampOutline(in: textView)
        reportOutlineEntry(in: textView)
        linksDidChange(in: textView)
        applyEmbeds(to: textView)
        applyTransclusions(to: textView, theme: parent.theme)
        // After the styling and before the reveal, in that order and for both reasons:
        // this is a text change of its own, so the attributes it needs are the ones the
        // pass it triggers writes, and the offsets the reveal works in are the ones it
        // leaves behind (ADR-0028 §D6, R-08). Scoped to the run the change landed on when
        // `shouldChangeTextInRanges` recorded it (ADR-0082 §D6). A replay takes the recorded range
        // and drops it, so the next change cannot inherit it.
        let edited = renumbering.take()
        if renumbers { renumberLists(in: textView, touching: edited) }
        // After the passes above: a keystroke shifts every offset below it, and
        // the revealed set has to be recomputed against the new text (ADR-0018 §D2).
        applyReveal(to: textView)

        // Typing has to keep the caret on screen, and under TextKit 2 it does not do so
        // by itself once the note has just grown taller: the two `apply` passes above
        // change the height on this very keystroke, and the scroll view is still showing
        // what fitted before. Only on a real edit - never when a note is merely being
        // opened or restyled - so the index's jumps and the user's own scrolling are
        // left alone.
        growToFitTheText(textView, revealingCaret: true)

        guard let completingView = textView as? CompletingTextView else { return }
        guard completing || completingView.completionPanel.isVisible else { return }
        // Unconditionally, and once for all four triggers: the panel has to close when
        // the context stops being one, not only open when it starts.
        //
        // It cannot recur, and that is worth saying because the call it replaced could.
        // AppKit's `complete(nil)` put the first candidate into the text as it opened
        // the list, that edit called `textDidChange` straight back, the context was
        // still a completion one - `#area-training` is a tag prefix like `#a` was - and
        // the app died on a stack overflow from typing `#` at the start of a line. The
        // panel writes nothing until a row is chosen, so there is no edit to come back.
        completingView.refreshCompletion(theme: parent.theme)
    }

    /// The edit path, for an operation that changed the text without `textDidChange`: an undo, a
    /// redo, a composition step (`composing`, which never opens the completion panel). Nothing while
    /// every edit the storage reported is styled, so the sidebar's move-undo on the same window manager
    /// (ADR-0026 §D8) replays nothing.
    func replayEditIfUnstyled(in textView: NSTextView, composing: Bool = false) {
        guard hasUnstyledEdits else { return }
        runEditPasses(in: textView, renumbering: false, completing: !composing)
    }

    /// Moves the did-undo and did-redo observations onto `manager`, the one `undoManager` now names.
    /// The block runs on the main queue, so the main actor is checked rather than asserted blind, as
    /// `observeWidthChanges(of:)` does.
    func observeUndoNotifications(of manager: UndoManager?) {
        stopObservingUndoNotifications()
        guard let manager else { return }
        undoObservers = [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: manager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let textView = self.textView else { return }
                    self.replayEditIfUnstyled(in: textView)
                }
            }
        }
    }

    /// Removes the undo observations, from `dismantleNSView` and before moving them.
    func stopObservingUndoNotifications() {
        for observer in undoObservers { NotificationCenter.default.removeObserver(observer) }
        undoObservers = []
    }
}
