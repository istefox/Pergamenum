import AppKit

/// Commits one `TableGridView` cell's edit back to the note's own source text (ADR-0029
/// §D7/§D8; plan `2026-09-02-editor-wysiwyg-unification`, Task 5) - the Coordinator's own
/// half of the grid, on the exact model `NoteTextView+EmbedCaret.swift`'s
/// `replaceAtomically(_:with:in:)` already set: one atomic
/// `shouldChangeText`/`beginEditing`/`replaceCharacters`/`endEditing` write, never a second
/// path, so a structural table edit is one `Cmd+Z` regardless of which cell moved.
extension NoteTextView.Coordinator {
    /// Applies `edit` to the table whose header paragraph starts at `offset`, and writes
    /// the result back over the table's own source range - `false`, the buffer left
    /// untouched, when the table is not there to write over any more.
    ///
    /// **D8's reload guard, not yet in the stub below:** before writing anything, the real
    /// implementation must re-run `GFMTable.parse` at the range last recorded for this
    /// table (never trust a stale `GFMTable` carried across keystrokes - the note may have
    /// changed underneath it, by this edit's own sibling cells committing in a different
    /// order, or by a paste, or by Cmd+Z). A shape that no longer matches - a different
    /// column count, a table that moved or is simply gone - refuses the commit and returns
    /// `false` rather than writing over the wrong lines. Only once the reload confirms the
    /// table is still there does `edit.applied(to:)` run, `GFMTable.serialised()` turn the
    /// result back into text, and `replaceAtomically(_:with:in:)` (the only mechanism this
    /// write may use, ADR-0019 §D7's precedent) replace `table.range` with it, one call, one
    /// undo step.
    ///
    /// Stub for Task 5 (tester): always refuses, so the "one atomic write, one undo step"
    /// test below is red until the coder wires the reload-guard-then-write path described
    /// above. The two reload-guard tests (table replaced wholesale under the grid, table
    /// moved by an edit above it) already pass with this stub - refusing is the correct
    /// answer for both, they just are not exercising the coder's own guard logic yet.
    @discardableResult
    func commitTable(_ edit: TableEdit, at offset: Int, in textView: NSTextView) -> Bool {
        false
    }
}
