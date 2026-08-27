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

    @State private var filter = ""
    /// The folders currently open, by path. View state rather than a preference: a
    /// tree that reopens exactly as it was is nice, and a tree that reopens with the
    /// note you are reading hidden is not, which is what `reveal` below prevents.
    @State private var expanded: Set<String> = []
    @State private var tree: [NoteTree.Node] = []
    /// The note the rename sheet is editing. The title being typed lives inside the
    /// sheet: held here alongside it, the two were set in the same action and the
    /// sheet validated the old value while showing the new one.
    @State private var renaming: NoteRecord?
    /// The note the delete confirmation is about (SPEC §10: never without asking).
    @State private var deleting: NoteRecord?
    /// Folders or flat list. A preference rather than view state: whichever one
    /// someone works in, they work in it every day.
    @AppStorage("noteListShowsFolders") private var showsFolders = true
    /// Whether the starred section is open. A preference and not view state, for the same
    /// reason `showsFolders` is one: it is answered once and lived with.
    @AppStorage("noteListShowsStarred") private var showsStarred = true

    var body: some View {
        VStack(spacing: 0) {
            header
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
        .onChange(of: vault.openNote?.relativePath) { _, path in reveal(path) }
        .sheet(item: $renaming) { note in
            RenameNoteSheet(note: note) { newTitle in
                vault.renameNote(at: note.relativePath, to: newTitle)
                renaming = nil
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
                if let note = deleting { vault.trashNote(at: note.relativePath) }
                deleting = nil
            }
            Button("Annulla", role: .cancel) { deleting = nil }
        } message: {
            Text("Va nel Cestino del Finder, non è una cancellazione definitiva. I link che puntavano qui resteranno non risolti.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: theme.spacing(.xs)) {
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
            NoteRowMenu(note: note, renaming: $renaming, deleting: $deleting)
        }
        .accessibilityIdentifier("starred-note")
    }

    private var folderTree: some View {
        List(selection: selectedPath) {
            starredSection
            ForEach(tree) { node in
                NoteTreeRow(
                    node: node,
                    depth: 0,
                    expanded: $expanded,
                    renaming: $renaming,
                    deleting: $deleting
                )
            }
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("note-tree")
        .contextMenu {
            Button("Espandi tutto") { expanded = Self.allFolders(in: tree) }
            Button("Comprimi tutto") { expanded = [] }
        }
    }

    /// Every note in one list, which is what the sidebar showed before the tree and
    /// what a filter falls back to: a match three folders down is easier to see in a
    /// flat list than as a tree opened around it.
    private var flatList: some View {
        List(selection: selectedPath) {
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
                .tag(note.relativePath)
                // Dragged onto a task line in the editor, this becomes a wikilink
                // (SPEC §7.2).
                .draggable(note.title)
                .contextMenu {
                    NoteRowMenu(note: note, renaming: $renaming, deleting: $deleting)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("note-flat-list")
    }

    private var filteredNotes: [NoteRecord] {
        filter.isEmpty ? vault.index.allNotes : vault.index.search(filter, limit: 200)
    }

    /// Reads the open note's path and opens whatever the list selects. Selection is
    /// derived from the controller rather than duplicated in view state, so opening a
    /// note from a backlink or the quick switcher also moves the highlight.
    ///
    /// **Nothing is selected while the composer is up**, and that is not cosmetic: the
    /// setter of a selection binding runs on a *change*, so with the covered note still
    /// reading as selected, clicking it was no change at all and the composer stayed put -
    /// on the one note the click most obviously means "show me that again". Reading nil
    /// makes the click a change, and leaves the list agreeing with the index and the
    /// inspector, which say nothing while the composer covers a note.
    private var selectedPath: Binding<String?> {
        Binding(
            get: { vault.isOpenNoteVisible ? vault.openNote?.relativePath : nil },
            set: { path in
                guard let path else { return }
                // Already open underneath: step out of the composer rather than read the
                // note again, which would throw away whatever is unsaved in it.
                guard path != vault.openNote?.relativePath else { return vault.leaveComposer() }
                vault.openNote(at: path)
            }
        )
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
    /// there is no `WorkspaceSelection` and no tree lookup here, because a `Set<String>`'s
    /// only member, once this rule reaches the "one id" case, already *is* the note's own
    /// vault-relative path - nothing to resolve it against.
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
        currentlyOpen: String?, isComposingNote: Bool
    ) -> SelectionOutcome? {
        // Placeholder (RED body): "do nothing", always. Correct by construction for the
        // two-or-more-ids row, the empty-set row, and a re-clicked already-visible row;
        // wrong, and left red on its `#expect` rather than on a build error, for every row
        // that should open a note or step out of the composer.
        nil
    }

    // MARK: Tree state

    /// Rebuilt when the index changes rather than in `body`: sorting every note on
    /// every keystroke in the editor is work nobody asked for.
    private func rebuild() {
        tree = NoteTree.build(from: vault.index.allNotes)
        reveal(vault.openNote?.relativePath)
    }

    /// Opens the folders above a note, so a note opened from a backlink, a wikilink or
    /// the quick switcher is visible in the tree rather than merely selected inside a
    /// closed folder.
    private func reveal(_ path: String?) {
        guard let path else { return }
        expanded.formUnion(NoteTree.ancestors(of: path))
    }

    private static func allFolders(in nodes: [NoteTree.Node]) -> Set<String> {
        var result: Set<String> = []
        for node in nodes where node.kind == .folder {
            result.insert(node.id)
            result.formUnion(allFolders(in: node.children ?? []))
        }
        return result
    }

}

/// One row of the folder tree, and its subtree.
///
/// Recursive rather than an `OutlineGroup`: the group owns its expansion state
/// privately, and this tree has to be opened from outside - by "Espandi tutto", and by
/// a note being opened from somewhere that is not the sidebar.
private struct NoteTreeRow: View {
    @Environment(\.theme) var theme
    @Environment(VaultController.self) var vault

    let node: NoteTree.Node
    let depth: Int
    @Binding var expanded: Set<String>
    @Binding var renaming: NoteRecord?
    @Binding var deleting: NoteRecord?

    /// One indent step. The rows are drawn flat inside a `List`, so the depth has to
    /// be paid for in padding rather than by nesting the views.
    private static let indent: CGFloat = 14

    var body: some View {
        switch node.kind {
        case .folder: folderRow
        case .note: noteRow
        }
    }

    private var isOpen: Bool { expanded.contains(node.id) }

    @ViewBuilder
    private var folderRow: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .font(.caption2)
                .foregroundStyle(theme.color(.textTertiary))
            Image(systemName: isOpen ? "folder" : "folder.fill")
                .foregroundStyle(theme.color(.accentPrimary))
            Text(node.name).themedText(.body).lineLimit(1)
            Spacer(minLength: theme.spacing(.xs))
            Text("\(node.noteCount)").themedText(.caption, color: .textTertiary)
        }
        .padding(.leading, CGFloat(depth) * Self.indent)
        // The whole row, not only the label: a disclosure triangle you have to hit
        // exactly is the thing people complain about in file trees.
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .accessibilityIdentifier("folder-\(node.id)")
        .contextMenu { folderMenu }

        if isOpen {
            ForEach(node.children ?? []) { child in
                NoteTreeRow(
                    node: child,
                    depth: depth + 1,
                    expanded: $expanded,
                    renaming: $renaming,
                    deleting: $deleting
                )
            }
        }
    }

    @ViewBuilder
    private var folderMenu: some View {
        Button("Nuova nota qui") { vault.beginNewNote(in: node.id) }
        Button(isOpen ? "Comprimi" : "Espandi") { toggle() }
        Divider()
        Button("Rivela nel Finder") {
            guard let root = vault.root else { return }
            NSWorkspace.shared.activateFileViewerSelecting([
                root.appending(path: node.id, directoryHint: .isDirectory),
            ])
        }
    }

    private var noteRow: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "doc.text")
                .foregroundStyle(theme.color(.textTertiary))
            Text(node.name).themedText(.body).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, CGFloat(depth) * Self.indent)
        .tag(node.id)
        .draggable(node.name)
        .contextMenu {
            if let record = vault.index.allNotes.first(where: { $0.relativePath == node.id }) {
                NoteRowMenu(note: record, renaming: $renaming, deleting: $deleting)
            }
        }
    }

    private func toggle() {
        if isOpen {
            expanded.remove(node.id)
        } else {
            expanded.insert(node.id)
        }
    }
}
