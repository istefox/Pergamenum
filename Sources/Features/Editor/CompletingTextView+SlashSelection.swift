import AppKit

// PG-387 (N4), ADR-0085 §D8, plan docs/plans/pg-387-n4-birth-of-note.md, Task 7 - R-13.
// A file of its own because `CompletingTextView+Pasteboard.swift` is protected (SPEC, Constraints).

extension CompletingTextView {
    /// Typing a `/` over a selection replaces it, as typing does; the replaced text and where it
    /// was are kept first, one-shot, so «Estrai in una nota» from the slash menu can put it back.
    /// Any other string, and a `/` over a bare caret, leaves the stash as typing found it.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string
        if typed == "/" {
            let replaced = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
            let text = self.string as NSString
            if replaced.length > 0, NSMaxRange(replaced) <= text.length {
                slashSelectionStash = (replaced.location, text.substring(with: replaced))
            } else {
                slashSelectionStash = nil
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    /// Puts the stashed selection back in place of `range` (the `/prefix` typed over it) and
    /// reselects it, then drops the stash. Answers whether there was one to restore.
    ///
    /// Through `replaceCharacters` between `shouldChangeText` and `didChangeText`, not
    /// `insertText`: the edit is undoable and reaches the binding like any other, and a stashed
    /// `/` cannot stash itself again on its way back.
    func restoreSlashSelection(replacing range: NSRange) -> Bool {
        guard let stash = slashSelectionStash else { return false }
        slashSelectionStash = nil
        guard NSMaxRange(range) <= (string as NSString).length,
              shouldChangeText(in: range, replacementString: stash.text)
        else { return false }
        replaceCharacters(in: range, with: stash.text)
        didChangeText()
        setSelectedRange(NSRange(location: range.location, length: (stash.text as NSString).length))
        return true
    }

    /// The slash menu's catalogue: the commands that take the selection, which the catalogue
    /// leaves out, are added only while a stash holds one to give them. Whether one can run is
    /// asked when it runs, after the selection is back (ADR-0085 §D8).
    var slashCandidates: [EditorCommand] {
        slashSelectionStash == nil ? editorCommands : editorCommands + EditorCommand.selectionEntries
    }
}
