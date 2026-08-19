import Foundation

/// The state that belongs to the note being looked at, reached where the menu bar can
/// reach it (ADR-0012 D2).
///
/// These three used to be stored on `Navigation`, which is the window. They are now stored
/// on the focused `NoteTab` and read through here, so a menu can still change what it names
/// (SPEC §10) while two tabs keep their own folds. Reading with no tab open answers the
/// nothing-is-open value and writing is a no-op: reading mode with no note is not a state,
/// it is a question about nothing.
extension VaultController {
    /// The index entries whose sections are folded in the focused tab.
    var foldedEntries: Set<Int> {
        get { focusedTab?.foldedEntries ?? [] }
        set { updateFocusedTab { $0.foldedEntries = newValue } }
    }

    /// Which index entry the caret is inside, in the focused tab.
    var currentOutlineEntry: Int? {
        get { focusedTab?.currentOutlineEntry }
        set { updateFocusedTab { $0.currentOutlineEntry = newValue } }
    }

    /// Whether the focused tab shows its note rendered rather than as source.
    var isReadingMode: Bool {
        get { focusedTab?.isReadingMode ?? false }
        set { updateFocusedTab { $0.isReadingMode = newValue } }
    }

    func toggleFold(_ entry: Int) {
        updateFocusedTab { tab in
            if tab.foldedEntries.contains(entry) {
                tab.foldedEntries.remove(entry)
            } else {
                tab.foldedEntries.insert(entry)
            }
        }
    }
}

/// The gestures the tab bar and the File menu send (ADR-0012 D5).
extension VaultController {
    /// Cmd+T. Opens the quick switcher with the promise that what it finds lands in a tab
    /// of its own.
    ///
    /// **There is no empty tab in this model, and that is why Cmd+T asks first.** A tab
    /// holds a note; a tab holding nothing would put a second no-note state on screen
    /// beside the one the pane already has, for the two seconds between pressing Cmd+T
    /// and choosing something. The roadmap says "Cmd+T" and this is Cmd+T - it just knows
    /// what it is opening before it opens it.
    func beginNewTab() {
        opensNextNoteInNewTab = true
        isShowingQuickSwitcher = true
    }

    /// Opens what the quick switcher found, where the gesture that opened it asked for.
    func openChosenNote(at relativePath: String) {
        if opensNextNoteInNewTab {
            openNoteInNewTab(at: relativePath)
        } else {
            openNote(at: relativePath)
        }
        opensNextNoteInNewTab = false
    }

    /// Cmd+Shift+T, most recently closed first. The note is read from disk again, which is
    /// the whole content of a closed tab: it was saved or its changes were discarded.
    func reopenClosedTab() {
        guard let path = closedTabPaths.popLast() else { return }
        openNoteInNewTab(at: path)
    }

    /// Cmd+1…Cmd+9. Nine means the last tab, whatever its position - Safari's rule, and
    /// the reason the ninth key is useful on a bar of twelve.
    func selectTab(_ number: Int) {
        guard columns.indices.contains(focusedColumnIndex) else { return }
        let tabs = columns[focusedColumnIndex].tabs
        guard !tabs.isEmpty else { return }
        let tab = number >= 9 ? tabs[tabs.count - 1] : tabs[safe: number - 1]
        guard let tab else { return }
        focusTab(tab.id)
    }

    /// Closes the focused tab. The dialog ADR-0012 D3 asks for belongs to the view that
    /// can show it; by the time this runs, the question has been answered.
    func closeFocusedTab() {
        guard let id = focusedTab?.id else { return }
        closeTab(id)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Reading a note into a tab.
///
/// Beside the tabs rather than in `VaultController.swift`, because that is what opening a note
/// now is: the two entry points differ in *where the note lands* and in nothing else, which is
/// why they share `readForEditing` instead of each doing the read themselves.
extension VaultController {
    func openNote(at relativePath: String) {
        // Already open somewhere in this column: go to that tab rather than loading a second
        // copy of the same note. Found on screen on 2026-08-19, with the note in two tabs at
        // once. Re-reading it would be worse than untidy - the tab that has it may hold
        // unsaved edits, and this would quietly drop them.
        if let existing = tabs.first(where: { $0.note.relativePath == relativePath }) {
            focusTab(existing.id)
            return
        }
        guard let note = readForEditing(relativePath) else { return }
        show(note)
        isComposingNote = false
    }

    /// Reads the focused tab's note from disk again, replacing the buffer.
    ///
    /// For the callers that mean "the file changed underneath, catch up" rather than "open
    /// this": `openNote(at:)` cannot serve them any more, because for them the note being
    /// already open is the normal case and it now short-circuits.
    func reloadFocusedNote() {
        guard let path = openNote?.relativePath, let note = readForEditing(path) else { return }
        replaceOpenNote(note)
    }

    /// Follows a renamed or moved note in every tab that was showing it.
    ///
    /// Not "the open note" any more: before tabs there was one buffer to put back in step,
    /// and a rename now has to reach a note sitting in a tab nobody is looking at, or that
    /// tab keeps a path with no file behind it.
    func movedNote(from oldPath: String, to newPath: String) {
        guard columns.indices.contains(focusedColumnIndex) else { return }
        guard tabs.contains(where: { $0.note.relativePath == oldPath }),
              let note = readForEditing(newPath)
        else { return }
        for tab in tabs where tab.note.relativePath == oldPath {
            updateTab(tab.id) { $0 = tab.showing(note) }
        }
    }

    /// Closes every tab showing a note that is no longer there.
    func trashedNote(at relativePath: String) {
        for tab in tabs where tab.note.relativePath == relativePath {
            closeTab(tab.id)
        }
        // A trashed note is not one to offer back with Cmd+Shift+T.
        closedTabPaths.removeAll { $0 == relativePath }
    }

    /// The tabs of the focused column, or none.
    var tabs: [NoteTab] {
        columns.indices.contains(focusedColumnIndex) ? columns[focusedColumnIndex].tabs : []
    }

    /// Opens a note beside the ones already open instead of over the focused one
    /// (ADR-0012 D2). Cmd+T and a Cmd+click in the list are the gestures that reach it.
    func openNoteInNewTab(at relativePath: String) {
        guard let note = readForEditing(relativePath) else { return }
        openTab(showing: note)
        isComposingNote = false
    }

    /// Reads a note for the editor and puts the index back in step, or reports why not.
    ///
    /// Split out of `openNote(at:)` so opening in place and opening in a new tab cannot
    /// drift: they differ in where the note lands and in nothing else.
    private func readForEditing(_ relativePath: String) -> OpenNote? {
        guard let session else { return nil }
        do {
            let (record, text) = try session.read(relativePath)
            session.updateIndex(record, at: relativePath)
            return OpenNote(
                relativePath: relativePath,
                title: record.title,
                text: text,
                savedText: text,
                externalChangePending: nil
            )
        } catch {
            recordProblem("\(relativePath): \(error)")
            return nil
        }
    }
}
