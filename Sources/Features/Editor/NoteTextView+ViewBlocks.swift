import AppKit

/// The Coordinator's own half of the view-block pass (ADR-0033 §D1/§D6/§D7/§D12/§D15; plan
/// `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 5): the styling pass that
/// recognises a closed `pergamenum-view` fence and registers its opening line's own marker,
/// the body/closing lines that leave the layout, and the host `ViewBlockHostStore` vends for
/// it, plus the caret rescue a fence hiding a line the caret was sitting in needs.
///
/// `NoteTextView+Tables.swift`'s `applyTables`/`refreshTableGrids`/`tableCaretRescue`/
/// `clearTables` shape, copied and diverging only where the sixth input
/// (`EditorDecorationDelegate.apply(viewBlockLines:)`/`apply(viewBlockHosts:)`, Task 2) and
/// the ordinal-keyed host store (`ViewBlockHostStore`, Task 4, ADR §D3) say to.
extension NoteTextView.Coordinator {
    /// Registers everything a view block needs drawn, from the `.viewBlockRun` spans
    /// `applyStyling` has just walked: the opening fence line's own `.viewBlock` marker, the
    /// body and closing-fence lines that leave the layout, and the host vended for each
    /// fence's ordinal.
    ///
    /// **Its own guard and its own change check**, `applyTables`'s own reasoning: with
    /// `hidesMarkup` off this registers nothing and clears what it registered before (ADR
    /// §D12) - the escape hatch has to reach the enumeration refusal too, or the body lines
    /// would stay out of the layout with the backticks visible above them. `markers` is
    /// `inout` for the same reason `applyTables`'s own is: the opening line's marker belongs
    /// in the same table `applyStyling` is about to hand over, and a second
    /// `apply(hiddenMarkers:)` call would be a second producer on one setter.
    ///
    /// **Stub.** The tester's own declaration (Task 5): the real body - walking `runs`,
    /// re-validating each one through
    /// `EditorDecorationDelegate.viewBlockRun(in:atParagraphStart:)`, vending a host per
    /// ordinal from `ViewBlockHostStore`, and the caret rescue (ADR §D15) that runs after
    /// `storage.endEditing()`, beside `refreshTableGrids` - is the coder's.
    func applyViewBlocks(to textView: NSTextView, runs: [NSRange], markers: inout [Int: [HiddenMarker]]) {
        // Task 5, coder.
    }

    /// Clears every view block this pass has registered - `NoteTextView+Tables.swift`'s
    /// `clearTables()` twin, called both by `applyViewBlocks`'s own `hidesMarkup`-off guard
    /// (ADR §D12) and whenever a note stops naming any `pergamenum-view` fence at all.
    ///
    /// **Stub.** The tester's own declaration (Task 5).
    func clearViewBlocks() {
        // Task 5, coder.
    }
}
