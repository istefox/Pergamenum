import Foundation

/// The sidebar's selection-collapse rule (ADR-0026 §D4), out of `NoteListPane`.
///
/// Pure code motion (PG-147): the rule reads nothing of the view, only `NoteTree.Node`, so
/// it never needed to be a member of it. The line references in the comments below
/// (`:215-220`, `:224-230`) name `NoteListPane.swift`, where the callers still are.
enum NoteSelectionRule {
    /// What a change to the sidebar's `Set<String>` selection means for the note open in
    /// the editor: one of the two calls `selectedPath`'s single-value setter already makes
    /// above (`vault.openNote(at:)` / `vault.leaveComposer()`, `:224-230`), or nothing.
    /// Never a bare `String?` - the two calls differ in whether the note is re-read from
    /// disk, and collapsing them into "the path that should now read as open" would push
    /// that distinction back out to every caller instead of answering it once, here.
    enum Outcome: Equatable {
        /// Read `path` from disk and show it - a different note than whatever is open
        /// today, or no note at all.
        case open(String)
        /// The row clicked is the note already open, currently covered by the composer:
        /// step out of it (`VaultController.leaveComposer()`) rather than re-reading the
        /// file and discarding whatever is unsaved in it (the comment above, `:215-220`).
        case leaveComposer
    }

    /// ADR-0026 §D4's collapse rule, adapted from `WorkspaceBrowser.opening(from:to:
    /// currently:in:)` (`WorkspaceBrowser.swift:758-780`) to the Note pane's own model:
    /// there is no `WorkspaceSelection` here, because a `Set<String>`'s only member, once
    /// this rule clears the note/folder guard below, already *is* the note's own
    /// vault-relative path - nothing left to resolve it against. The tree is read only for
    /// that guard (PG-082), never to turn the id into something else.
    ///
    /// `currentlyOpen` is `vault.openNote?.relativePath`, read raw and never masked -
    /// masking that value is `:216-220`'s job for what `List` reads as selected, not this
    /// rule's. `isComposingNote` is the second fact `:216-220` needs and
    /// `WorkspaceBrowser.opening` has no equivalent of: the same "one id, already open"
    /// case means two different things depending on it - step out of the composer, or
    /// nothing at all (an already-selected row producing no change for `List` to report in
    /// the first place, answered anyway for a function that has to answer every input it
    /// is given).
    ///
    /// `nil` is "do nothing": for two-or-more ids (R-10, the open note stays open exactly
    /// as `WorkspaceBrowser.opening`'s row 3 leaves the open board), for an empty set
    /// (today's setter already does nothing on deselect, `:225`), and for a single id
    /// already open with nothing covering it.
    ///
    /// `old` stays in the signature and stays unread, for the reason
    /// `WorkspaceBrowser.opening` gives verbatim: what a new set means is a question about
    /// what is open, not about what was lit a moment ago.
    ///
    /// `nonisolated`, matching `WorkspaceBrowser.opening`: a pure function of its
    /// arguments, callable from a test's synchronous, non-actor context.
    nonisolated static func opening(
        from old: Set<String>, to new: Set<String>,
        tree: [NoteTree.Node],
        currentlyOpen: String?, isComposingNote: Bool
    ) -> Outcome? {
        // Two or more: nothing opens and nothing closes (§D4 row 3, R-10). The set answers
        // "what does a drag carry" and only that - the note on screen, composer or no
        // composer, is not what a second lit row is about.
        guard new.count <= 1 else { return nil }
        // Empty: nothing, which is what the single-value setter this was extracted out of
        // already did on deselect (`guard let path else { return }`). A "close the note"
        // action never existed here and is not introduced by turning the binding into a set
        // (§D4 row 4).
        guard let id = new.first else { return nil }
        // A folder row now carries a `.tag` too (2026-08-28 toolbar parity chain), so this
        // still has to tell a folder id apart from a note id to open - but `NoteName
        // .validate` never forbade a `.` in a folder name, so a folder literally named
        // `Reunion.md` would pass a `.hasSuffix(".md")` guess. The real tree already knows
        // which one it is (PG-082): resolve the id against it instead of guessing from the
        // string's shape.
        guard NoteTree.node(withID: id, in: tree)?.kind == .note else { return nil }
        // Exactly one id, different from what is open: that note opens (§D4 row 1). The id
        // *is* the note's vault-relative path - a `Set<String>` member here is a row's own
        // `.tag`, so past the guard above there is nothing left to resolve it against
        // (`WorkspaceBrowser.opening`'s tree lookup goes further, turning a folder id into
        // the board it should open).
        guard id == currentlyOpen else { return .open(id) }
        // The same note again (§D4 row 2), and the two halves of it: step out of the
        // composer while it covers that note, and do nothing at all while it does not.
        // Never `.open(id)` - re-reading the file is exactly what would discard whatever is
        // unsaved in it (`:215-220`).
        return isComposingNote ? .leaveComposer : nil
    }
}
