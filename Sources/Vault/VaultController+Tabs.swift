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
    /// The folded sections' own heading offsets, in the focused tab (`NoteTab.foldedEntries`).
    var foldedEntries: Set<Int> {
        get { focusedTab?.foldedEntries ?? [] }
        set { updateFocusedTab { $0.foldedEntries = newValue } }
    }

    /// Which index entry the caret is inside, in the focused tab.
    var currentOutlineEntry: Int? {
        get { focusedTab?.currentOutlineEntry }
        set { updateFocusedTab { $0.currentOutlineEntry = newValue } }
    }

    /// Folds or unfolds the section whose heading starts at `offset` (a UTF-16 character
    /// offset, `NoteTab.foldedEntries`'s own key - never an ordinal, which is the identity
    /// that goes stale across an edit).
    func toggleFold(_ offset: Int) {
        updateFocusedTab { tab in
            if tab.foldedEntries.contains(offset) {
                tab.foldedEntries.remove(offset)
            } else {
                tab.foldedEntries.insert(offset)
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

/// The doors onto the tabs and the columns.
///
/// `columns` is stored on the class and written **only from here**. They moved out of
/// `VaultController.swift` when the split view took that file past SwiftLint's 400 lines, and
/// having every one of them in one file is what keeps the rule legible now that the compiler
/// no longer states it.
extension VaultController {
    // MARK: The doors onto the tabs
    //
    // `columns` is `private(set)`, so these four are the only way anything changes. They
    // are internal rather than private because the extensions that need them are in other
    // files - the same trade `replaceOpenNote` has always made, documented rather than
    // enforced by the compiler.

    /// Shows a note in the column's preview tab, opening one if there is none.
    ///
    /// **This is the single click, and it deliberately does not touch a stable tab.** Before
    /// tabs it replaced the one open note, which was the only thing it could do; doing that
    /// now would mean browsing the list destroys whatever the person had in front of them. So
    /// one tab per column is the preview, every single click lands there, and a double click
    /// makes it stable (`makeStable`).
    ///
    /// A reused tab keeps its identity and loses everything that described the note it was
    /// showing - folds, index entry, reading mode. That reset used to be an `onChange` in
    /// `VaultBrowser` watching the open note's path, which is the same rule written where it
    /// could not survive a second tab.
    func show(_ note: OpenNote) {
        guard columns.indices.contains(focusedColumnIndex) else { return }
        if let index = columns[focusedColumnIndex].tabs.firstIndex(where: \.isPreview) {
            let tab = columns[focusedColumnIndex].tabs[index]
            columns[focusedColumnIndex].tabs[index] = tab.showing(note)
            columns[focusedColumnIndex].activeID = tab.id
            rememberTabs()
        } else {
            var tab = NoteTab(note: note)
            tab.isPreview = true
            let after = columns[focusedColumnIndex].tabs.firstIndex { $0.id == focusedTab?.id }
            let at = after.map { $0 + 1 } ?? columns[focusedColumnIndex].tabs.count
            columns[focusedColumnIndex].tabs.insert(tab, at: at)
            columns[focusedColumnIndex].activeID = tab.id
        }
        rememberTabs()
    }

    /// Turns a preview tab into one that stays: the double click on a row or on the tab.
    func makeStable(_ id: NoteTab.ID) {
        guard columns.indices.contains(focusedColumnIndex),
              let index = columns[focusedColumnIndex].tabs.firstIndex(where: { $0.id == id })
        else { return }
        columns[focusedColumnIndex].tabs[index].isPreview = false
        rememberTabs()
    }

    // MARK: The columns (ADR-0012 D4)

    /// Gives a column the focus. An index that does not exist is ignored rather than trusted:
    /// a stale click on a column that has just been closed should do nothing, not trap.
    ///
    /// Everything downstream reads the focused column - the facade, the index in the sidebar,
    /// the inspector, every menu command - so this one line is what makes two columns behave
    /// like one editor that happens to be in two places.
    func focusColumn(_ index: Int) {
        guard columns.indices.contains(index), index != focusedColumnIndex else { return }
        focusedColumnIndex = index
        isComposingNote = false
        rememberTabs()
    }

    /// Splits the editor in two, with the focused note in a tab of its own on the right.
    ///
    /// Two columns and never three (D4). Splitting while a note is open puts that note on the
    /// right rather than an empty column: you split *because* you are reading something, and a
    /// blank half asks you to go and find it again.
    func splitEditor() {
        guard columns.count == 1 else { return }
        let note = focusedTab?.note
        addColumn()
        focusedColumnIndex = columns.count - 1
        if let note { openTab(showing: note) }
        rememberTabs()
    }

    /// Adds an empty column without moving the focus. The session restore needs this on its
    /// own; everything else goes through `splitEditor`.
    func addColumn() {
        guard columns.count == 1 else { return }
        columns.append(EditorColumn())
    }

    /// Closes a column and hands the focus to the one left.
    ///
    /// Never the last one: an editor with no columns is a window with nothing in it, and the
    /// no-tabs state already says "nessuna nota aperta" without needing a second way to reach
    /// it. The tabs it held are not offered back by Cmd+Shift+T - closing a column is closing
    /// a place, not a note.
    func closeColumn(_ index: Int) {
        guard columns.count > 1, columns.indices.contains(index) else { return }
        columns.remove(at: index)
        focusedColumnIndex = 0
        rememberTabs()
    }

    /// Opens a note in a tab of its own, after the focused one, and focuses it.
    func openTab(showing note: OpenNote) {
        guard columns.indices.contains(focusedColumnIndex) else { return }
        let tab = NoteTab(note: note)
        let after = columns[focusedColumnIndex].tabs.firstIndex { $0.id == focusedTab?.id }
        columns[focusedColumnIndex].tabs.insert(tab, at: after.map { $0 + 1 } ?? columns[focusedColumnIndex].tabs.count)
        columns[focusedColumnIndex].activeID = tab.id
        rememberTabs()
    }

    /// Brings a tab to the front of its column. Unknown ids are ignored rather than
    /// clearing the selection, which would blank the editor on a stale click.
    func focusTab(_ id: NoteTab.ID) {
        guard columns.indices.contains(focusedColumnIndex),
              columns[focusedColumnIndex].tabs.contains(where: { $0.id == id })
        else { return }
        columns[focusedColumnIndex].activeID = id
        isComposingNote = false
        rememberTabs()
    }

    /// Closes one tab by id, whether or not it is the focused one.
    ///
    /// Closing the focused tab moves focus to the one before it, which is where the eye
    /// already is; closing any other leaves focus alone. Unsaved changes are not this
    /// method's business - ADR-0012 D3's dialog asks before it gets here.
    func closeTab(_ id: NoteTab.ID) {
        guard columns.indices.contains(focusedColumnIndex),
              let index = columns[focusedColumnIndex].tabs.firstIndex(where: { $0.id == id })
        else { return }
        let wasFocused = columns[focusedColumnIndex].activeID == id
        closedTabPaths.append(columns[focusedColumnIndex].tabs[index].note.relativePath)
        columns[focusedColumnIndex].tabs.remove(at: index)
        guard wasFocused else { return }
        let neighbour = columns[focusedColumnIndex].tabs.indices.contains(index - 1) ? index - 1 : 0
        columns[focusedColumnIndex].activeID = columns[focusedColumnIndex].tabs.indices.contains(neighbour)
            ? columns[focusedColumnIndex].tabs[neighbour].id
            : nil
        rememberTabs()
    }

    /// Changes the focused tab in place, leaving its identity and view state alone.
    func updateFocusedTab(_ change: (inout NoteTab) -> Void) {
        guard let id = focusedTab?.id else { return }
        updateTab(id, change)
    }

    /// Changes any tab of the focused column by id, focused or not.
    ///
    /// A rename reaches a tab nobody is looking at, which is exactly the case the
    /// one-open-note version of this app could not have.
    func updateTab(_ id: NoteTab.ID, _ change: (inout NoteTab) -> Void) {
        guard columns.indices.contains(focusedColumnIndex),
              let index = columns[focusedColumnIndex].tabs.firstIndex(where: { $0.id == id })
        else { return }
        change(&columns[focusedColumnIndex].tabs[index])
    }

    /// Closes the note in the editor, for when the file it shows is no longer there.
    func closeOpenNote() {
        guard columns.indices.contains(focusedColumnIndex), let tab = focusedTab else { return }
        columns[focusedColumnIndex].tabs.removeAll { $0.id == tab.id }
        columns[focusedColumnIndex].activeID = columns[focusedColumnIndex].tabs.last?.id
    }

    /// Replaces the open note wholesale, keeping the tab and everything it knows.
    ///
    /// The one door for code outside this file: `openNote` reads the focused tab and cannot
    /// be assigned, so a view cannot quietly swap the buffer under the editor.
    func replaceOpenNote(_ note: OpenNote) {
        updateFocusedTab { $0.note = note }
    }
}

/// Reading a note into a tab.
///
/// Beside the tabs rather than in `VaultController.swift`, because that is what opening a note
/// now is: the two entry points differ in *where the note lands* and in nothing else, which is
/// why they share `readForEditing` instead of each doing the read themselves.
extension VaultController {
    func openNote(at relativePath: String) {
        rememberRecent(relativePath)
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
        // The recent list is paths, so a rename has to be followed here too - the same
        // follow-up `VaultSession.moveStar` performs for the star.
        if let index = recentNotePaths.firstIndex(of: oldPath) { recentNotePaths[index] = newPath }
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
        // A trashed note is not one to offer back with Cmd+Shift+T, nor one to list among
        // the recent ones: both would be a row that opens nothing.
        closedTabPaths.removeAll { $0 == relativePath }
        recentNotePaths.removeAll { $0 == relativePath }
    }

    /// Puts a note at the top of RECENTI, at most ten deep.
    ///
    /// Called where a note is *asked for* rather than in `readForEditing`, which the tab
    /// restore and every re-read after an external change also go through: those are the
    /// app catching up, not somebody going somewhere.
    func rememberRecent(_ relativePath: String) {
        recentNotePaths.removeAll { $0 == relativePath }
        recentNotePaths.insert(relativePath, at: 0)
        recentNotePaths = Array(recentNotePaths.prefix(Self.recentNoteLimit))
    }

    static let recentNoteLimit = 10

    /// The tabs of the focused column, or none.
    var tabs: [NoteTab] {
        columns.indices.contains(focusedColumnIndex) ? columns[focusedColumnIndex].tabs : []
    }

    /// Opens a note beside the ones already open instead of over the focused one
    /// (ADR-0012 D2). Cmd+T and a Cmd+click in the list are the gestures that reach it.
    func openNoteInNewTab(at relativePath: String) {
        rememberRecent(relativePath)
        guard let note = readForEditing(relativePath) else { return }
        openTab(showing: note)
        isComposingNote = false
    }

    /// Reads a note for the editor and puts the index back in step, or reports why not.
    ///
    /// Split out of `openNote(at:)` so opening in place and opening in a new tab cannot
    /// drift: they differ in where the note lands and in nothing else. Internal because the
    /// session restore in `VaultController.swift` reads through it too.
    func readForEditing(_ relativePath: String) -> OpenNote? {
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
