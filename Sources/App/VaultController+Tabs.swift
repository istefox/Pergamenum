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

    /// Shows or hides the frontmatter block of the focused tab (`NoteTab.hidesFrontmatter`).
    func toggleFrontmatter() {
        updateFocusedTab { $0.hidesFrontmatter.toggle() }
    }

    /// Which index entry the caret is inside, in the focused tab.
    var currentOutlineEntry: Int? {
        get { focusedTab?.currentOutlineEntry }
        set { updateFocusedTab { $0.currentOutlineEntry = newValue } }
    }

    /// The same, for the front tab of one column, without moving the focus.
    ///
    /// The text view reports the entry on every selection change, including the one it makes
    /// itself while loading its note. Written through the focused facade, each column had to
    /// take the focus first, so coming back to Note with two columns handed the focus to
    /// whichever loaded last. A click or a key in the text focuses its column already, through
    /// `CompletingTextView.becomeFirstResponder`.
    func recordOutlineEntry(_ entry: Int?, inColumn columnIndex: Int) {
        guard columns.indices.contains(columnIndex),
              let id = columns[columnIndex].activeID,
              let index = columns[columnIndex].tabs.firstIndex(where: { $0.id == id })
        else { return }
        columns[columnIndex].tabs[index].currentOutlineEntry = entry
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

    /// Cmd+W (ADR-0073 §D11). A clean tab closes at once; a dirty one is not closed here but
    /// handed to its column through `closeRequest`, which raises ADR-0012 §D3's «Salva / Non
    /// salvare / Annulla» dialog - the same one the chip's close button raises.
    func requestCloseFocusedTab() {
        guard let tab = focusedTab else { return }
        if tab.note.hasUnsavedChanges {
            closeRequest = tab.id
        } else {
            closeTab(tab.id)
        }
    }

    /// The column that holds the requested tab takes the request, clearing it; any other
    /// column gets nil and leaves it for its owner.
    func takeCloseRequest(forColumn columnIndex: Int) -> NoteTab? {
        guard let id = closeRequest, columns.indices.contains(columnIndex),
              let tab = columns[columnIndex].tabs.first(where: { $0.id == id })
        else { return nil }
        closeRequest = nil
        return tab
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

    // `closeColumn(_:ask:saveAll:)` lives in `VaultController+ColumnClose.swift`: it asks about the
    // column's unsaved tabs before closing it (PG-335).

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

    /// A tab by id, in whichever column holds it.
    func tab(withID id: NoteTab.ID) -> NoteTab? {
        columns.lazy.flatMap(\.tabs).first { $0.id == id }
    }

    /// Brings a tab of **either** column to the front and gives its column the focus - the
    /// cancelled quit's reveal (ADR-0073 §D7). `focusTab` alone stays in the focused column.
    func revealTab(_ id: NoteTab.ID) {
        guard let columnIndex = columns.firstIndex(where: { $0.tabs.contains { $0.id == id } }) else { return }
        focusColumn(columnIndex)
        focusTab(id)
    }

    /// Closes one tab by id, focused or not, in whichever column holds it.
    ///
    /// Closing a column's active tab moves that column's front to the one before it, which is
    /// where the eye already is; `focusedColumnIndex` is never touched. Unsaved changes are
    /// not this method's business - ADR-0012 D3's dialog asks before it gets here.
    func closeTab(_ id: NoteTab.ID) {
        guard let columnIndex = columns.firstIndex(where: { $0.tabs.contains { $0.id == id } }),
              let index = columns[columnIndex].tabs.firstIndex(where: { $0.id == id })
        else { return }
        let wasActive = columns[columnIndex].activeID == id
        closedTabPaths.append(columns[columnIndex].tabs[index].note.relativePath)
        columns[columnIndex].tabs.remove(at: index)
        if wasActive {
            let neighbour = columns[columnIndex].tabs.indices.contains(index - 1) ? index - 1 : 0
            columns[columnIndex].activeID = columns[columnIndex].tabs.indices.contains(neighbour)
                ? columns[columnIndex].tabs[neighbour].id
                : nil
        }
        // Every close, not only the active tab's; after the neighbour, as the session stores it.
        rememberTabs()
    }

    /// Changes the focused tab in place, leaving its identity and view state alone.
    func updateFocusedTab(_ change: (inout NoteTab) -> Void) {
        guard let id = focusedTab?.id else { return }
        updateTab(id, change)
    }

    /// Changes any tab of the focused column by id, focused or not.
    ///
    /// A caller that already knows a tab's id and its column is the focused one - a rename
    /// or a trash reaching every column goes through `updateTabs(showing:_:)` instead
    /// (ADR-0056 §D1).
    func updateTab(_ id: NoteTab.ID, _ change: (inout NoteTab) -> Void) {
        guard columns.indices.contains(focusedColumnIndex),
              let index = columns[focusedColumnIndex].tabs.firstIndex(where: { $0.id == id })
        else { return }
        change(&columns[focusedColumnIndex].tabs[index])
    }

    /// Applies `change` to every tab showing `relativePath`, in every column - not only in
    /// the focused one. An external change, and an in-process write, rename or trash the
    /// session announces (`landed(_:)`, ADR-0067), do not know which tab, if any, has the focus: `canOperate(on:)`
    /// (`VaultController+Files.swift`) already asks the question of every column, and these
    /// four used to ask it of the first one only.
    func updateTabs(showing relativePath: String, _ change: (inout NoteTab) -> Void) {
        for columnIndex in columns.indices {
            for tabIndex in columns[columnIndex].tabs.indices
            where columns[columnIndex].tabs[tabIndex].note.relativePath == relativePath {
                change(&columns[columnIndex].tabs[tabIndex])
            }
        }
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

    /// Reads a note for the editor, or reports why not.
    ///
    /// Split out of `openNote(at:)` so opening in place and opening in a new tab cannot
    /// drift: they differ in where the note lands and in nothing else. Internal because the
    /// session restore in `VaultController.swift` reads through it too.
    ///
    /// **No longer refreshes the index row (ADR-0043 §D4).** It used to, with an unstamped
    /// call into the old single-record index-refresh door that ADR-0043 §D1 found reachable
    /// from five unguarded places - this being one of them. After §D1 every real change has
    /// a stamped writer of its own
    /// (the write path, a move, a trash, the watcher); a row that disagrees with the file
    /// got that way from one of those, and the index is disposable by construction
    /// (ADR-0001 §D2.1) - the cold scan or the watcher's reconciliation is what keeps it in
    /// step, not this read.
    func readForEditing(_ relativePath: String) -> OpenNote? {
        guard let session else { return nil }
        do {
            let (record, text) = try session.read(relativePath)
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
