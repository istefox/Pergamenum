import AppKit
import SwiftUI

/// The left column of the Note pane: the vault's folders, the notes inside them, and
/// what the sidebar can do to either.
///
/// Split out of `VaultBrowser` rather than added to it: that file already carries the
/// editor and the inspector and is over the size SwiftLint warns at, and the folder
/// tree is a self-contained piece of it.
struct NoteListPane: View {
    @Environment(\.theme) var theme
    @Environment(VaultController.self) var vault
    /// Reached for the index below the list: a click there is a request the editor
    /// consumes, and this is where such requests live (M8).
    @Environment(Navigation.self) var navigation
    /// The **window's** undo manager, read from the environment and handed to
    /// `VaultController.moveItems` as an argument (ADR-0026 §D8) - the same stack
    /// `NSTextView` registers text edits on (`NoteTextView.swift`, `allowsUndo = true`),
    /// so Cmd+Z means "undo the last thing I did in this window" whatever had focus. The
    /// facade never reaches for `NSApp.keyWindow?.undoManager` itself.
    @Environment(\.undoManager) private var undoManager

    @State private var filter = ""
    /// Not `private`, on this property and every other `@State` down to `deletingFolder`
    /// below: `NoteListPane+FolderVerbs.swift` is an extension of this same struct in a
    /// separate file, and reads and writes all of them from `toolbar`, `currentSelection`,
    /// `targetFolder`, `renameSelection()`, `deleteSelection()`, `createFolder(named:in:)`
    /// and the sheets, extracted out of this file for its own length (see the header
    /// comment above `struct NoteListPane`).
    ///
    /// The folders currently open, by path. View state rather than a preference: a
    /// tree that reopens exactly as it was is nice, and a tree that reopens with the
    /// note you are reading hidden is not, which is what `reveal` below prevents.
    @State var expanded: Set<String> = []
    @State var tree: [NoteTree.Node] = []
    /// Every lit row, which is `List(selection:)`'s own set and the whole of ADR-0026 §D4:
    /// Cmd-click and Shift-click come from AppKit for free, so nothing here reads
    /// `NSEvent.modifierFlags` and no recognizer is added to a row body.
    ///
    /// It answers **one** question, "what does a drag carry" (R-11). What is *open* stays
    /// `vault.openNote`, derived from this set by `opening(from:to:currentlyOpen:
    /// isComposingNote:)` - a row can be lit without being open, and two lit rows open
    /// nothing (R-10).
    ///
    /// Folder rows carry a `.tag` too now (2026-08-28, toolbar parity chain): a folder id
    /// never collides with a note id (a note path always ends in `.md`, a folder path
    /// never does), so the two share this one set safely. `opening(...)` below is what
    /// keeps a folder id from being treated as a note to open.
    ///
    /// Kept in step with the editor by `syncSelectedRows()` - a note opened from a
    /// backlink, a wikilink or the quick switcher lights exactly its own row - and pruned
    /// of ids no row carries by `rebuild()`.
    @State var selectedRows: Set<String> = []
    /// What the drag that is in flight carries, stored by the source row at drag start.
    ///
    /// `.dropDestination` has no payload-aware validation - its `isTargeted` closure is
    /// handed a `Bool` and never the payload (ADR-0026 §D5) - so the only way a folder row
    /// can decline to light up for a cycle is for the source side to have remembered what
    /// it started dragging. Empty between drags.
    @State private var dragging: [VaultItemRef] = []
    /// The note the rename sheet is editing. The title being typed lives inside the
    /// sheet: held here alongside it, the two were set in the same action and the
    /// sheet validated the old value while showing the new one.
    @State var renaming: NoteRecord?
    /// The note the delete confirmation is about (SPEC §10: never without asking).
    @State var deleting: NoteRecord?
    /// The vault's real, on-disk folder list (`CanvasStore.allFolders()`), rebuilt
    /// alongside `tree` in `rebuild()` - `WorkspaceBrowser`'s own `folders`
    /// (`WorkspaceBrowser.swift:599`), needed here for the same two reasons: an empty
    /// folder needs a row `NoteTree.build(from:folders:)` can only give it if this list
    /// names it, and the "Nuova cartella" sheet's parent picker needs every folder, not
    /// only the ones a note happens to sit in.
    @State var diskFolders: [String] = []
    /// Whether the "Nuova cartella" sheet is up.
    @State var creatingFolder = false
    /// The folder the rename sheet is editing (toolbar "Rinomina" on a folder row).
    @State var renamingFolder: String?
    /// The folder the delete confirmation is about (toolbar "Elimina" on a folder row).
    @State var deletingFolder: String?
    /// Set when a folder rename was refused - the folder-verb twin of `renameRefused` above,
    /// declared here since `NoteListPane+FolderVerbs.swift` (an extension) cannot add stored
    /// properties.
    @State var renameFolderRefused: String?
    /// The folder-delete twin of `renameFolderRefused` above.
    @State var trashFolderRefused: String?
    /// Set when a move was refused for a reason the drag itself cannot show - today only
    /// `VaultController.canOperate`'s unsaved-note guard (ADR-0026 §D10), which used to
    /// fail `performMove` silently: the drag lifted, the folder row lit, and nothing moved,
    /// with no way to tell a refusal from a slow drop. `vault.problems.last` is read right
    /// after the refusing call, mirroring `WorkspaceBrowser`'s own `moveConflict` alert.
    @State var moveRefused: String?
    /// Set when a rename was refused (`canOperate`'s unsaved-note guard, most commonly) — the
    /// rename sheet dismisses regardless (ADR-0026 §D10's "close + alert" shape, same as
    /// `moveRefused` above), so this is the only trace of the refusal on screen.
    @State private var renameRefused: String?
    /// The trash confirmation's twin of `renameRefused` above.
    @State private var trashRefused: String?
    /// Folders or flat list. A preference rather than view state: whichever one
    /// someone works in, they work in it every day.
    @AppStorage("noteListShowsFolders") private var showsFolders = true
    /// Whether the starred section is open. A preference and not view state, for the same
    /// reason `showsFolders` is one: it is answered once and lived with.
    @AppStorage("noteListShowsStarred") private var showsStarred = true

    /// The pane, then the sheets its folder verbs open (`NoteListPane+FolderVerbs.swift`),
    /// then the move-refused alert - the same order the chain spelled out inline before the
    /// verbs moved to a file of their own, so no presentation changed position.
    var body: some View {
        folderVerbSheets(pane)
            // Same treatment `WorkspaceBrowser` gives a collision (ADR-0026 §D9's "a command
            // rendered twice"): a drop is a gesture with an expectation, and a refusal with
            // nothing on screen reads as a drag that missed.
            .alert(
                "Spostamento rifiutato",
                isPresented: Binding(
                    get: { moveRefused != nil },
                    set: { if !$0 { moveRefused = nil } }
                ),
                presenting: moveRefused
            ) { _ in
                Button("OK", role: .cancel) { moveRefused = nil }
                    .accessibilityIdentifier("sidebar-move-conflict-ok")
            } message: { reason in
                Text(reason)
                    .accessibilityIdentifier("sidebar-move-conflict")
            }
            .alert(
                "Rinomina rifiutata",
                isPresented: Binding(
                    get: { renameRefused != nil },
                    set: { if !$0 { renameRefused = nil } }
                ),
                presenting: renameRefused
            ) { _ in
                Button("OK", role: .cancel) { renameRefused = nil }
                    .accessibilityIdentifier("sidebar-rename-refused-ok")
            } message: { reason in
                Text(reason)
                    .accessibilityIdentifier("sidebar-rename-refused")
            }
            .alert(
                "Eliminazione rifiutata",
                isPresented: Binding(
                    get: { trashRefused != nil },
                    set: { if !$0 { trashRefused = nil } }
                ),
                presenting: trashRefused
            ) { _ in
                Button("OK", role: .cancel) { trashRefused = nil }
                    .accessibilityIdentifier("sidebar-trash-refused-ok")
            } message: { reason in
                Text(reason)
                    .accessibilityIdentifier("sidebar-trash-refused")
            }
    }

    private var pane: some View {
        VStack(spacing: 0) {
            header
            // A second row *beside* the header, never inside it - the same reason
            // `WorkspaceBrowser` gives (`WorkspaceBrowser.swift:123-126`): the header
            // groups its children under its own identifier and a button placed inside it
            // risks answering to that identifier instead of its own.
            toolbar
            Divider()
            if showsFolders, filter.isEmpty {
                folderTree
            } else {
                flatList
            }
            footer
        }
        .background(theme.color(.backgroundSecondary))
        .task(id: vault.scanGeneration) { rebuild() }
        .onChange(of: vault.openNote?.relativePath) { _, path in
            reveal(path)
            syncSelectedRows()
        }
        // The second half of what the old `selectedPath` getter did in one expression
        // (ADR-0026 §D4): the composer opening or closing changes nothing about *which*
        // note is open, so the change above never fires for it - and «nothing is selected
        // while the composer is up» is the behaviour that would otherwise be lost, taking
        // the `leaveComposer()` click with it.
        .onChange(of: vault.isOpenNoteVisible) { _, _ in syncSelectedRows() }
        // `VaultTopBar`'s breadcrumb (2026-08-28): a folder crumb opens the tree down to
        // it and lights its row, without touching the note open in the editor - a folder
        // id never ends `.md`, so `opening(...)` above reads this as "nothing to open or
        // close" (its own guard), exactly like a direct click on the row.
        .onChange(of: navigation.folderReveal) { _, reveal in
            guard let reveal else { return }
            guard !reveal.folder.isEmpty else {
                selectedRows = []
                return
            }
            showsFolders = true
            expanded.formUnion(NoteTree.ancestors(of: reveal.folder) + [reveal.folder])
            selectedRows = [reveal.folder]
        }
        .sheet(item: $renaming) { note in
            RenameNoteSheet(note: note) { newTitle in
                Task { @MainActor in
                    if !(await vault.renameNote(at: note.relativePath, to: newTitle)) {
                        renameRefused = vault.problems.last
                    }
                    renaming = nil
                }
            } onCancel: {
                renaming = nil
            }
        }
        .confirmationDialog(
            "Eliminare «\(deleting?.title ?? "")»?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Sposta nel Cestino", role: .destructive) {
                Task { @MainActor in
                    if let note = deleting, !(await vault.trashNote(at: note.relativePath)) {
                        trashRefused = vault.problems.last
                    }
                    deleting = nil
                }
            }
            Button("Annulla", role: .cancel) { deleting = nil }
        } message: {
            Text("Va nel Cestino del Finder, non è una cancellazione definitiva. I link che puntavano qui resteranno non risolti.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: theme.spacing(.xs)) {
            // `WorkspaceBrowser.header`'s own label half (`WorkspaceBrowser.swift:376-392`),
            // "NOTE" in place of "WORKSPACE" - the toolbar parity chain (2026-08-28).
            Image(systemName: "doc.text").foregroundStyle(theme.color(.textTertiary))
            Text("NOTE").themedText(.caption, color: .textTertiary)
            Spacer()
            Image(systemName: "magnifyingglass").foregroundStyle(theme.color(.textTertiary))
            TextField("Filtra", text: $filter)
                .textFieldStyle(.plain)
                .themedText(.body)
                .accessibilityIdentifier("note-filter")
            Button {
                showsFolders.toggle()
            } label: {
                Image(systemName: showsFolders ? "list.bullet.indent" : "list.bullet")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("note-list-style")
            .help(showsFolders ? "Mostra tutte le note in un elenco" : "Mostra le cartelle")
        }
        .padding(theme.spacing(.s))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Note del vault")
        .accessibilityIdentifier("note-browser-header")
    }

    // MARK: Folders

    // MARK: Le preferite (ADR-0012 D6)

    /// The starred notes, above the rest, and **nothing at all when there are none**: a heading
    /// over an empty space is a heading in the way, and for weeks after this ships that is the
    /// normal state of the section.
    ///
    /// **A `Section` inside each list rather than a stack above them**, which is the second
    /// attempt: rows of my own started fourteen points to the left of the notes underneath,
    /// because a `List` insets its rows and nothing outside one can ask by how much. Inside, the
    /// alignment is not a number to guess.
    ///
    /// The rows carry no `.tag`, so the list's selection - which is bound to the open note -
    /// cannot land on them: a note starred *and* visible in the tree would otherwise be two rows
    /// claiming to be the same selected thing. They are buttons, and being the open note is
    /// drawn rather than selected.
    @ViewBuilder
    private var starredSection: some View {
        let notes = vault.starredNotes
        if !notes.isEmpty {
            Section {
                if showsStarred {
                    ForEach(notes, id: \.relativePath) { note in
                        starredRow(note)
                    }
                }
            } header: {
                Button { showsStarred.toggle() } label: {
                    HStack(spacing: theme.spacing(.xs)) {
                        Image(systemName: showsStarred ? "chevron.down" : "chevron.right")
                            .themedText(.caption, color: .textTertiary)
                        Text("PREFERITE").themedText(.caption, color: .textTertiary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func starredRow(_ note: NoteRecord) -> some View {
        let isOpen = note.relativePath == vault.openNote?.relativePath && vault.isOpenNoteVisible
        return Button { vault.openNote(at: note.relativePath) } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "star.fill").themedText(.caption, color: .accentPrimary)
                Text(note.title)
                    .themedText(.body, color: isOpen ? .accentPrimary : .textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            NoteRowMenu(note: note, renaming: $renaming, deleting: $deleting, moveRefused: $moveRefused)
        }
        .accessibilityIdentifier("starred-note")
    }

    private var folderTree: some View {
        List(selection: treeSelection) {
            starredSection
            ForEach(tree) { node in
                NoteTreeRow(
                    node: node,
                    depth: 0,
                    expanded: $expanded,
                    renaming: $renaming,
                    deleting: $deleting,
                    moveRefused: $moveRefused,
                    move: moveContext
                )
            }
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("note-tree")
        .dropDestination(for: VaultItemDrag.self) { (drops: [VaultItemDrag], _: CGPoint) -> Bool in
            dropOnRoot(drops)
        }
        .contextMenu {
            Button("Espandi tutto") { expanded = Self.allFolders(in: tree) }
            Button("Comprimi tutto") { expanded = [] }
        }
    }

    /// Every note in one list, which is what the sidebar showed before the tree and
    /// what a filter falls back to: a match three folders down is easier to see in a
    /// flat list than as a tree opened around it.
    private var flatList: some View {
        List(selection: treeSelection) {
            starredSection
            ForEach(filteredNotes, id: \.relativePath) { note in
                VStack(alignment: .leading, spacing: 1) {
                    Text(note.title)
                        .themedText(.body)
                        .lineLimit(1)
                    if !note.folder.isEmpty {
                        Text(note.folder)
                            .themedText(.caption, color: .textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Dragged onto a folder row this moves the file (R-03); dragged onto a
                // task line in the editor it still becomes a wikilink (SPEC §7.2), because
                // `VaultItemDrag` puts the title on the pasteboard as a plain `String`
                // beside the structured payload (ADR-0026 §D3, R-09) - byte-identical to
                // the `.draggable(note.title)` that used to be written here.
                .draggable(beginDrag(of: note.relativePath, kind: .note, named: note.title))
                .accessibilityIdentifier("note-row-\(note.relativePath)")
                .contextMenu {
                    NoteRowMenu(note: note, renaming: $renaming, deleting: $deleting, moveRefused: $moveRefused)
                }
                // `.tag` **last in the chain**, normalised to the Workspace pane's order
                // (ADR-0026 §D11): a modifier applied after it drops it, and the failure is
                // silent - the list lights nothing and swallows every click
                // (`RootView.swift:205-208`).
                .tag(note.relativePath)
            }
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("note-flat-list")
        .dropDestination(for: VaultItemDrag.self) { (drops: [VaultItemDrag], _: CGPoint) -> Bool in
            dropOnRoot(drops)
        }
    }

    private var filteredNotes: [NoteRecord] {
        filter.isEmpty ? vault.index.allNotes : vault.index.search(filter, limit: 200)
    }

    /// The `List`'s selection: the whole lit **set** since ADR-0026 §D4, not the one open
    /// row it used to be. The tag is still the row's own id - a note's vault-relative path
    /// - so the strings travelling through this binding are row ids and nothing has to be
    /// derived from anything.
    ///
    /// A set rather than a `String?` is the whole of Cmd-click and Shift-click: AppKit's
    /// list already does both, so this repository reads no modifier flag and adds no
    /// gesture to a row (ADR-0026 A4). What is *open* is not this set - it is derived from
    /// it by `opening(from:to:currentlyOpen:isComposingNote:)`, whose three answers are the
    /// two calls the single-value setter used to make and the third the ADR added: nothing.
    ///
    /// The `get` no longer masks anything. **Nothing is selected while the composer is
    /// up** - which is not cosmetic, for the reason the old getter's comment gave: the
    /// setter of a selection binding runs on a *change*, so with the covered note still
    /// reading as selected, clicking it was no change at all and the composer stayed put,
    /// on the one note the click most obviously means "show me that again". That masking
    /// moved to `syncSelectedRows()`, which empties the set on the same condition and is
    /// driven by `.onChange(of: vault.isOpenNoteVisible)` - a stored set cannot mask itself
    /// in a getter without also un-lighting whatever else the user Cmd-clicked.
    private var treeSelection: Binding<Set<String>> {
        Binding(
            get: { selectedRows },
            set: { ids in
                let previous = selectedRows
                selectedRows = ids
                switch Self.opening(
                    from: previous, to: ids, tree: tree,
                    currentlyOpen: vault.openNote?.relativePath,
                    isComposingNote: vault.isComposingNote
                ) {
                case .open(let path): vault.openNote(at: path)
                case .leaveComposer: vault.leaveComposer()
                // "Leave what is open alone" - a two-row selection must not close the note
                // on screen (R-10), and an empty set deselects without closing anything.
                case nil: break
                }
            }
        )
    }

    /// The lit set follows what is open, never the other way round (ADR-0026 §D4): a note
    /// opened from a backlink, a wikilink, a tab or the quick switcher lights exactly its
    /// own row and drops whatever multi-row set was standing, because the one thing that is
    /// open is also one row.
    ///
    /// Empty while the composer covers the note, which is where the old getter's masking
    /// went (see `treeSelection`). Assigned to the `@State` directly and never through the
    /// binding, so this never re-enters the setter above.
    private func syncSelectedRows() {
        guard vault.isOpenNoteVisible, let path = vault.openNote?.relativePath else {
            selectedRows = []
            return
        }
        selectedRows = [path]
    }

    // MARK: Selection collapse rule (ADR-0026 §D4, adapted from `WorkspaceBrowser.opening`)

    /// What a change to the sidebar's `Set<String>` selection means for the note open in
    /// the editor: one of the two calls `selectedPath`'s single-value setter already makes
    /// above (`vault.openNote(at:)` / `vault.leaveComposer()`, `:224-230`), or nothing.
    /// Never a bare `String?` - the two calls differ in whether the note is re-read from
    /// disk, and collapsing them into "the path that should now read as open" would push
    /// that distinction back out to every caller instead of answering it once, here.
    enum SelectionOutcome: Equatable {
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
    ) -> SelectionOutcome? {
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

    // MARK: Move (ADR-0026)

    /// Everything a row's drag, its drop and a folder row's «Sposta in» menu need, rebuilt
    /// with the body so the lit set and the drag in flight it carries are the current ones
    /// (ADR-0026 §D4, §D5, §D9) - `WorkspaceMoveContext`'s shape, minus its `folders`,
    /// which the Note tree reads straight off `vault.folders` (§D9: correct *here*, because
    /// this tree is built from note paths and shows no folder that list omits).
    private var moveContext: NoteMoveContext {
        NoteMoveContext(
            dragging: dragging,
            beginDrag: { beginDrag(of: $0, kind: $1, named: $2) },
            perform: { performMove($0, into: $1) }
        )
    }

    /// What a drag started on `path` carries (ADR-0026 §D4, R-11): the whole lit set when
    /// that row is part of it, that row alone when it is not - the SPEC's own rule, and
    /// AppKit's. The set is also remembered here, because a folder row's drop affordance is
    /// asked of it and `isTargeted` never sees the payload (§D5).
    ///
    /// `name` is the row's own - a note's **title**, which is what `ProxyRepresentation(
    /// exporting: \.dragName)` puts on the pasteboard as a plain `String` and therefore what
    /// `CompletingTextView.performDragOperation` keeps reading, unedited (§D3, R-09).
    private func beginDrag(
        of path: String, kind: VaultItemKind, named name: String
    ) -> VaultItemDrag {
        let items = kind == .note && selectedRows.contains(path)
            ? references(for: selectedRows)
            : [VaultItemRef(path: path, kind: kind)]
        dragging = items
        return VaultItemDrag(items: items, dragName: name)
    }

    /// The notes behind a set of ids, in the index's own order - a `Set` has none, and a
    /// batch whose order changed between two identical drags would make `VaultMoveBatch`'s
    /// answers unrepeatable.
    ///
    /// Every id is a note path: a folder row of this pane carries no `.tag`, so nothing
    /// else can be in the set. An id no note answers to is dropped rather than guessed at.
    private func references(for ids: Set<String>) -> [VaultItemRef] {
        vault.index.allNotes.compactMap { note in
            ids.contains(note.relativePath)
                ? VaultItemRef(path: note.relativePath, kind: .note)
                : nil
        }
    }

    /// R-05's destination, on both lists: the tree's own empty area means the vault root,
    /// spelled `""` everywhere this feature computes a path.
    ///
    /// The rows sit *inside* this destination and SwiftUI hit-tests the innermost one
    /// first, so a drop on a folder row reaches that row's and only a drop on the
    /// background reaches this (ADR-0026 §D11) - which is also why «Sposta in ▸ (radice)»
    /// exists as a second, certain surface for the same move.
    private func dropOnRoot(_ drops: [VaultItemDrag]) -> Bool {
        guard let items = drops.first?.items else { return false }
        return performMove(items, into: "")
    }

    /// The move both surfaces call - a folder row's `.dropDestination`, the list's own
    /// root-area destination, and «Sposta in» in a folder row's context menu (ADR-0026 §D9:
    /// a command is named once and rendered twice).
    ///
    /// `false` for a refused drop, which is what `.dropDestination`'s `action` owes the
    /// drag. The cycle is refused here as well as by the affordance, because the menu has
    /// no hover to decline; every other refusal comes back on `vault.moveItems`'s own
    /// outcome (PG-083) and is joined into the one alert this pane shows.
    ///
    /// `undoManager` is the **window's**, handed down as an argument rather than reached
    /// for (§D8). Nil is not silently tolerated: `moveItems` records that the move cannot
    /// be taken back.
    ///
    /// The `Bool` now answers the *drag*, not the move: `.dropDestination`'s action is
    /// synchronous and the move goes through the one asynchronous write door (ADR-0043
    /// §D2), so a drop that got past the two pure guards is accepted straight away and
    /// whatever disk decides arrives a moment later on the alert this pane already shows.
    /// The guards stay on this side of the hop because they are pure string arithmetic
    /// over the payload, not state that the suspension could invalidate (§D7).
    private func performMove(_ items: [VaultItemRef], into destination: String) -> Bool {
        dragging = []
        guard !items.isEmpty,
              WorkspaceBrowser.canDrop(items, onFolder: destination) else { return false }
        Task { @MainActor in
            let outcome = await vault.moveItems(items, into: destination, undo: undoManager)
            guard outcome.didMove else {
                let reasons = outcome.refusals + outcome.failures
                moveRefused = reasons.isEmpty ? nil : reasons.joined(separator: "\n")
                return
            }
        }
        return true
    }

    // MARK: Tree state

    /// Rebuilt when the index changes rather than in `body`: sorting every note on
    /// every keystroke in the editor is work nobody asked for.
    private func rebuild() {
        let folders = vault.root.map { CanvasStore(root: $0).allFolders() } ?? []
        diskFolders = folders
        tree = NoteTree.build(from: vault.index.allNotes, folders: folders)
        // A move, a rename or a delete has just taken rows away, and an id kept in the lit
        // set after its row has gone is an id a drag would still carry (ADR-0026 §D4).
        // Asked of the very list the tree is built from, so the two cannot disagree about
        // which ids exist.
        let existing = Set(vault.index.allNotes.map(\.relativePath))
        selectedRows = selectedRows.filter(existing.contains)
        // With nothing lit, the open note's row is: this is the first scan of a pane drawn
        // with a note already open - a vault reopened on one, or a tab restored - where no
        // `.onChange` has fired because neither value changed.
        if selectedRows.isEmpty { syncSelectedRows() }
        reveal(vault.openNote?.relativePath)
    }

    /// Opens the folders above a note, so a note opened from a backlink, a wikilink or
    /// the quick switcher is visible in the tree rather than merely selected inside a
    /// closed folder.
    private func reveal(_ path: String?) {
        guard let path else { return }
        expanded.formUnion(NoteTree.ancestors(of: path))
    }
}
