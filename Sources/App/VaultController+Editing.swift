import Foundation

/// What the editor does to the note it is showing: saving it, restoring a past version over
/// it, and settling an external change that arrived underneath it.
///
/// Split out of `VaultController.swift` when tabs pushed that file past SwiftLint's 400 lines.
/// Every one of these reaches the buffer through `replaceOpenNote` or `updateFocusedTab`, the
/// doors that stayed behind with the stored `columns` - so the rule that a view cannot swap
/// the buffer under the editor survives the move.
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
    func saveOpenNote() async {
        guard let session, var note = openNote, note.hasUnsavedChanges else { return }
        do {
            try await session.write(note.text, to: note.relativePath)
            note.savedText = note.text
            note.externalChangePending = nil
            replaceOpenNote(note)
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
    func restoreVersion(_ text: String) async {
        guard let session, openNote != nil else { return }
        await saveOpenNote()
        // Re-read: the save above replaced `openNote` wholesale.
        guard var note = openNote else { return }
        do {
            let result = try await session.write(text, to: note.relativePath)
            note.text = result.text
            note.savedText = result.text
            note.externalChangePending = nil
            replaceOpenNote(note)
        } catch {
            recordProblem("\(note.relativePath): \(error)")
        }
    }

    /// Puts the editor back in step after a write the session made underneath it.
    ///
    /// This is the fourth of the four things every write in this app used to do by
    /// hand, and the only one that is the facade's business: the session writes the
    /// file, records the hash and updates the index, and then this decides whether the
    /// editor should notice.
    ///
    /// **A buffer with unsaved changes raises the conflict prompt (ADR-0043 §D7).** The
    /// dirty buffer is the user's work, and ADR-0001 §D3.4 says never to merge and never
    /// to discard it - ask. This used to leave the buffer alone on the theory that "the
    /// watcher will raise the question when the write comes back round", which is false:
    /// `reconcile` drops this session's own writes by matching their hash
    /// (`VaultSession+Watching.swift`), which is §D3.3 working correctly, so a write
    /// this session made itself never reaches the watcher as an external change and the
    /// question would never have been asked at all.
    func syncOpenNote(with result: VaultSession.WriteResult) {
        guard var note = openNote, note.relativePath == result.path else { return }
        if note.hasUnsavedChanges {
            // Never merge, never discard: ask (ADR-0001 §D3.4), with this write's own
            // text as the incoming side of the prompt.
            note.externalChangePending = result.text
        } else {
            note.text = result.text
            note.savedText = result.text
        }
        replaceOpenNote(note)
    }

    /// Resolves an external change the user chose to accept, replacing the buffer.
    func acceptExternalChange() {
        guard var note = openNote, let incoming = note.externalChangePending else { return }
        note.text = incoming
        note.savedText = incoming
        note.externalChangePending = nil
        replaceOpenNote(note)
    }

    /// Keeps the in-app version and clears the prompt. The next save overwrites disk.
    func keepLocalVersion() {
        updateFocusedTab { $0.note.externalChangePending = nil }
    }
}
