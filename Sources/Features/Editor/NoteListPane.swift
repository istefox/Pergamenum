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

    private var folderTree: some View {
        List(selection: selectedPath) {
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

/// The note context menu of SPEC §10: rename with link updating (W-08), move, delete.
///
/// One type used by both lists, so the tree and the flat list cannot drift apart.
private struct NoteRowMenu: View {
    @Environment(VaultController.self) var vault
    let note: NoteRecord
    @Binding var renaming: NoteRecord?
    @Binding var deleting: NoteRecord?

    var body: some View {
        Button("Apri") { vault.openNote(at: note.relativePath) }
        Button("Rinomina…") { renaming = note }
        Menu("Sposta in") {
            Button("(radice)") { vault.moveNote(at: note.relativePath, toFolder: "") }
            ForEach(vault.folders, id: \.self) { folder in
                Button(folder) { vault.moveNote(at: note.relativePath, toFolder: folder) }
                    .disabled(folder == note.folder)
            }
        }
        Divider()
        Button("Rivela nel Finder") {
            guard let root = vault.root else { return }
            NSWorkspace.shared.activateFileViewerSelecting([
                root.appending(path: note.relativePath, directoryHint: .notDirectory),
            ])
        }
        Divider()
        Button("Elimina…", role: .destructive) { deleting = note }
    }
}

/// Renaming a note, with the title being typed held here and nowhere else.
private struct RenameNoteSheet: View {
    @Environment(\.theme) var theme
    let note: NoteRecord
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var title: String

    init(note: NoteRecord, onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.note = note
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _title = State(initialValue: note.title)
    }

    private var violations: [NoteName.Violation] { NoteName.validate(title) }
    private var canRename: Bool { violations.isEmpty && title != note.title }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Rinomina nota").themedText(.title)
            Text("I wikilink che puntano a «\(note.title)» vengono riscritti (W-08).")
                .themedText(.caption, color: .textSecondary)

            TextField("Titolo", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canRename { onConfirm(title) } }

            ForEach(ConformanceText.lines(NoteViolations(
                name: violations, frontmatter: [], tags: [],
                relatedMissingInSection: [], relatedMissingInFrontmatter: []
            )), id: \.self) { line in
                Text(line).themedText(.caption, color: .taskOverdue)
            }

            HStack {
                Spacer()
                Button("Annulla", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Rinomina") { onConfirm(title) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRename)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 460)
        .background(theme.color(.surfaceCard))
    }
}
