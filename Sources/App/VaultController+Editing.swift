import Foundation

/// What one save of one tab did (ADR-0073 §D4).
enum TabSave: Equatable, Sendable {
    /// The buffer's text reached disk.
    case saved
    /// Nothing to save: the tab was clean, or no longer exists.
    case clean
    /// The write threw; the message is the problem recorded for it.
    case failed(String)
}

/// What the editor does to the note it is showing: saving it, restoring a past version over
/// it, and settling an external change that arrived underneath it.
///
/// Split out of `VaultController.swift` when tabs pushed that file past SwiftLint's 400 lines.
/// Every one of these reaches a buffer through a door that stayed behind with the stored
/// `columns` - the catch-up after a write is `landed(_:)`'s, which the session calls itself
/// (ADR-0067, `VaultController+TabFollowUps.swift`), and `replaceOpenNote` or
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
    /// handed to the write as its `origin` (ADR-0067 §D2): the session echoes it back through
    /// `landed(_:)`, which gives that tab its saved text and every other copy the prompt rule.
    /// Nothing is called after the write - the door already delivered it.
    ///
    /// Since ADR-0073 §D4 the write itself is `saveTab(_:)`'s, the one save door Cmd+S, the
    /// «Salva» chip, the tab-close dialog and the quit share. The behaviour is unchanged: no
    /// precondition, and a pending banner does not stop it.
    func saveOpenNote() async {
        guard let id = focusedTab?.id else { return }
        _ = await saveTab(id)
    }

    /// Writes one tab's buffer, found by id in **any** column, and says what happened
    /// (ADR-0073 §D4).
    ///
    /// `.clean` when the tab is not dirty or no longer exists; otherwise the text goes through
    /// `session.write(_:to:origin:)` with the tab's id as `origin`, so `landed(_:)` gives this
    /// tab its saved text and every other copy of the path the prompt rule (ADR-0067 §D2). The
    /// text is read before the `await`; anything typed during it stays unsaved. No focusing:
    /// a background tab, or one of the other column, is saved where it is.
    func saveTab(_ id: NoteTab.ID) async -> TabSave {
        guard let writer = tab(withID: id), writer.note.hasUnsavedChanges else { return .clean }
        let note = writer.note
        // A tab that outlived a vault switch names a path of the vault it came from; writing it
        // here would overwrite, or create, a different file (ADR-0073 §D5, departure 13). The
        // refusal lives in the one save door so Cmd+S, «Salva» and the close dialog inherit it.
        guard !writer.isFromPreviousVault else {
            let message = "\(note.relativePath): la nota è di una cartella note aperta prima, non salvata"
            recordProblem(message)
            return .failed(message)
        }
        guard let session else {
            let message = "\(note.relativePath): nessuna cartella note aperta"
            recordProblem(message)
            return .failed(message)
        }
        do {
            try await session.write(note.text, to: note.relativePath, origin: id)
            return .saved
        } catch {
            let message = "\(note.relativePath): \(error)"
            recordProblem(message)
            return .failed(message)
        }
    }

    /// The tab-close dialog's «Salva» (ADR-0012 §D3): saves, then closes **only** when the
    /// save landed or there was nothing to save (ADR-0073 §D4, F6). A failed save leaves the
    /// tab open and dirty with its problem recorded, and so does text typed while the write
    /// was suspended: a save that did not take the whole buffer never drops it.
    @discardableResult
    func saveAndCloseTab(_ id: NoteTab.ID) async -> TabSave {
        let outcome = await saveTab(id)
        switch outcome {
        case .saved, .clean:
            if tab(withID: id)?.note.hasUnsavedChanges != true { closeTab(id) }
        case .failed:
            break
        }
        return outcome
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
    /// version over another (ADR-0058 §D4). The restore passes no `origin` (ADR-0067 §D2), so
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
