import Foundation

/// What the editor does to the note it is showing: saving it, restoring a past version over
/// it, and settling an external change that arrived underneath it.
///
/// Split out of `VaultController.swift` when tabs pushed that file past SwiftLint's 400 lines.
/// Every one of these reaches a buffer through a door that stayed behind with the stored
/// `columns` - the catch-up after a write is `landed(_:)`'s, which the session calls itself
/// (ADR-0066, `VaultController+TabFollowUps.swift`), and `replaceOpenNote` or
/// `updateFocusedTab` for settling the banner the person clicked (`closeTabs(_:ofVanishedNote:)` when it was a deletion, ADR-0064
/// §D5) - so the rule that a view cannot swap the buffer under the editor survives the move.
extension VaultController {
    /// Writes the open note.
    ///
    /// **`async`, on the one write door left (ADR-0043 §D2).** ADR-0041 Task 8 tried this
    /// conversion and reverted it, because `Tests/VaultTests.swift`,
    /// `Tests/NoteHistoryTests.swift` and `Tests/NoteTabTests.swift` called it
    /// synchronously and read the file straight back off disk, and test files were outside
    /// that task's edit scope. What that comment recorded was not a property of the save but
    /// the shape of the work: the conversion fails unless the tests move with it. They moved
    /// with it here, so the caller awaits the write instead of the write pretending to be
    /// instantaneous - and an `await` is exactly the guarantee those tests were relying on,
    /// now stated rather than inferred from the thread.
    ///
    /// The *target* is the focused buffer, as every caller means it; the *effects* reach every
    /// tab showing the path (ADR-0058 §D3). The writer tab's id is taken before the `await`,
    /// because the focused tab when the write resumes may no longer be the one that saved, and
    /// handed to the write as its `origin` (ADR-0066 §D2): the session echoes it back through
    /// `landed(_:)`, which gives that tab its saved text and every other copy the prompt rule.
    /// Nothing is called after the write - the door already delivered it.
    func saveOpenNote() async {
        guard let session, let writer = focusedTab, writer.note.hasUnsavedChanges else { return }
        let note = writer.note
        do {
            try await session.write(note.text, to: note.relativePath, origin: writer.id)
        } catch {
            recordProblem("\(note.relativePath): \(error)")
        }
    }

    /// Writes a past version back over the open note (ADR-0011, M9).
    ///
    /// **Saves the buffer first, and that is the point rather than tidiness.**
    /// `NoteHistory` records the text being *written*, so the note's current text is in
    /// the list only because an earlier write put it there; unsaved edits are in no
    /// snapshot at all. Restoring straight over them would discard work with nothing to
    /// go back to, which is precisely what ADR-0001 §D3.4 refuses to do. Saving first
    /// puts the buffer in the history, and the restore's own write adds itself on the
    /// way past - so the sheet's promise that restoring keeps the current version is
    /// literally true, in the one case where it would otherwise be a lie.
    ///
    /// `async` for the same reason `saveOpenNote()` above is, and the ordering matters here
    /// more than anywhere: the buffer's save must have *finished* before the restore writes
    /// over it, or the snapshot the sheet promised to keep is the one the restore overwrote.
    ///
    /// The path is read **before** the save, not after it: a re-read of `openNote` once the
    /// save resumes finds whichever tab has the focus then, and would write one note's past
    /// version over another (ADR-0058 §D4). The restore passes no `origin` (ADR-0066 §D2), so
    /// the catch-up `landed(_:)` performs reaches every tab showing the path, the writer's own
    /// included; a buffer still dirty after the save - a failed save, or text typed during
    /// either `await` - gets the prompt rather than being overwritten.
    func restoreVersion(_ text: String) async {
        guard let session, let path = openNote?.relativePath else { return }
        await saveOpenNote()
        do {
            try await session.write(text, to: path)
        } catch {
            recordProblem("\(path): \(error)")
        }
    }

    /// Resolves the focused tab's pending external change the way the disk has it - the
    /// banner's first button, «Ricarica da disco» or «Scarta ed elimina» (ADR-0064 §D5).
    ///
    /// - `.text`: the buffer takes the incoming text, which also becomes its saved text.
    /// - `.deleted`: the unsaved text is discarded and the focused tab closes through
    ///   `closeTabs(_:ofVanishedNote:)`, the one door for a tab whose file is gone (§D4).
    ///   Nothing is written: the file stays deleted.
    func acceptExternalChange() {
        guard let tab = focusedTab, let pending = tab.note.externalChangePending else { return }
        switch pending {
        case .text(let incoming):
            var note = tab.note
            note.text = incoming
            note.savedText = incoming
            note.externalChangePending = nil
            replaceOpenNote(note)
        case .deleted:
            closeTabs([tab.id], ofVanishedNote: tab.note.relativePath)
        }
    }

    /// Keeps the in-app version and clears the prompt - the banner's second button, «Tieni la
    /// mia versione» (ADR-0064 §D5).
    ///
    /// - `.text`: the buffer is untouched; the next save overwrites the disk.
    /// - `.deleted`: `savedText` also becomes `""`, the honest answer to «what the disk last
    ///   held» once it holds nothing. That keeps a non-empty buffer dirty even when it was
    ///   undone back to its old saved text, so the next save recreates the file and closing
    ///   the tab asks first, instead of leaving a clean tab on a missing file nothing can save.
    func keepLocalVersion() {
        updateFocusedTab { tab in
            if tab.note.externalChangePending == .deleted { tab.note.savedText = "" }
            tab.note.externalChangePending = nil
        }
    }
}
