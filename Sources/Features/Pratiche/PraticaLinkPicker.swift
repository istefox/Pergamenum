import SwiftUI

// ADR-0049 (Pratiche links to notes, tasks and boards), plan
// docs/plans/pratiche-note-task-workspace-links.md, Task 4 - R-01, R-02, R-03, §D10.

/// What `PraticaLinkPicker` is choosing, and on whose behalf.
///
/// ADR-0039 §D3's `taskPickingBoard` pattern, reused for a fourth participant: held on
/// `Navigation` because the command is offered from the list column, the timeline and
/// the inspector alike, and a sheet hosted in one of them cannot be reached from the
/// others.
struct PraticaLinkRequest: Identifiable, Equatable {
    /// Which of the three relations is being picked.
    enum Kind: Equatable {
        case note
        case task
        case board
    }

    /// Which write the picker's choice becomes: a pratica's own general links (§D1),
    /// or one message's single `pergamenum-mail-note` (§D6) - `.note` only, since a
    /// message links to at most one note and never to a task or a board.
    enum Scope: Equatable {
        case pratica(path: String)
        case message(notePath: String)
    }

    let id = UUID()
    var kind: Kind
    var scope: Scope
    /// R-03: what a created target is pre-filled with - the email subject for a
    /// per-message link, the pratica's own title for a general one.
    var contextTitle: String
    /// R-03: the pratica's own `topic-pratica`/`client-<slug>` tags, carried onto a
    /// note created from context. Empty for a task/board request, neither of which
    /// has anything of this shape to receive.
    var contextTags: [Tag]
}

/// The link commands' own picker (§D10): `WorkspacePicker`'s shape - filter, list,
/// footer, 380×380 - parameterised by `PraticaLinkRequest.Kind` so one view serves the
/// pratica's three general relations and the per-message one, with a «Crea nuova…» row
/// that satisfies the SPEC's "existing or new" in one surface (R-03).
///
/// **Rejected: reusing `QuickSwitcher`.** Its own doc comment states the constraint -
/// *"One caller, one question"* - and its `field`'s `.task` consumes
/// `vault.consumePendingSearch()`, so a picker opened from a pratica would swallow a
/// queued `pergamenum://search` query. It also offers headings and the daily note,
/// neither of which is a link target.
struct PraticaLinkPicker: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    let request: PraticaLinkRequest
    let actions: PraticaCommandActions
    let onClose: () -> Void

    @State private var filter = ""
    @State private var notes: [NoteRecord] = []
    @State private var tasks: [TaskItem] = []
    @State private var boards: [String] = []
    @State private var isCreating = false
    @State private var creationText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 380, height: 380)
        .background(theme.color(.surfaceCard))
        .task { load() }
        .onExitCommand(perform: onClose)
        .sheet(isPresented: $isCreating) { creationSheet }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-link-picker")
    }

    private func load() {
        switch request.kind {
        case .note:
            notes = vault.index.allNotes
        case .task:
            tasks = vault.index.allTasks
        case .board:
            boards = vault.root.map { CanvasStore(root: $0).allBoards() } ?? []
        }
    }

    // MARK: Header

    private var title: String {
        switch request.kind {
        case .note: "Collega una nota"
        case .task: "Collega un'attività"
        case .board: "Collega una board"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text(title).themedText(.title)
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.color(.textTertiary))
                TextField("Filtra", text: $filter)
                    .textFieldStyle(.plain)
                    .themedText(.body)
                    .accessibilityIdentifier("pratiche-link-picker-filter")
            }
        }
        .padding(theme.spacing(.m))
    }

    // MARK: Rows

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                createRow
                switch request.kind {
                case .note: noteRows
                case .task: taskRows
                case .board: boardRows
                }
            }
            .padding(.vertical, theme.spacing(.xs))
        }
        .accessibilityIdentifier("pratiche-link-picker-list")
    }

    /// R-03: the picker's other half - an existing target above, a fresh one below,
    /// on the same surface.
    private var createRow: some View {
        Button {
            creationText = request.contextTitle
            isCreating = true
        } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(theme.color(.accentPrimary))
                Text("Crea nuova…")
                    .themedText(.body, color: .accentPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing(.m))
            .padding(.vertical, theme.spacing(.xs))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pratiche-link-picker-create")
    }

    private var filteredNotes: [NoteRecord] {
        guard !filter.isEmpty else { return notes }
        return notes.filter { $0.title.localizedCaseInsensitiveContains(filter) }
    }

    @ViewBuilder
    private var noteRows: some View {
        ForEach(filteredNotes) { note in
            row(
                title: note.title, subtitle: note.relativePath, symbol: "doc.text",
                reference: note.relativePath
            ) {
                commit { await actions.linkExistingNote(titled: note.title, for: request) }
            }
        }
        if filteredNotes.isEmpty {
            emptyRow(notes.isEmpty ? "Nessuna nota nel vault" : "Nessuna nota trovata")
        }
    }

    private var filteredTasks: [TaskItem] {
        guard !filter.isEmpty else { return tasks }
        return tasks.filter { $0.text.localizedCaseInsensitiveContains(filter) }
    }

    @ViewBuilder
    private var taskRows: some View {
        ForEach(filteredTasks) { task in
            row(
                title: task.text,
                subtitle: NoteName.title(fromFileName: (task.sourcePath as NSString).lastPathComponent),
                symbol: "checklist", reference: "\(task.sourcePath)#\(task.lineIndex)"
            ) {
                commit { await actions.linkExistingTask(task, for: request) }
            }
        }
        if filteredTasks.isEmpty {
            emptyRow(tasks.isEmpty ? "Nessuna attività nel vault" : "Nessuna attività trovata")
        }
    }

    private var filteredBoards: [String] {
        guard !filter.isEmpty else { return boards }
        return boards.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    @ViewBuilder
    private var boardRows: some View {
        ForEach(filteredBoards, id: \.self) { path in
            row(
                title: (WorkspaceBoardResolver.fileName(of: path) as NSString).deletingPathExtension,
                subtitle: (path as NSString).deletingLastPathComponent,
                symbol: "rectangle.3.group", reference: path
            ) {
                commit { await actions.linkExistingBoard(at: path, for: request) }
            }
        }
        if filteredBoards.isEmpty {
            emptyRow(boards.isEmpty ? "Nessuna board nel vault" : "Nessuna board trovata")
        }
    }

    private func row(
        title: String, subtitle: String, symbol: String, reference: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: symbol).foregroundStyle(theme.color(.textTertiary))
                Text(title).themedText(.body).lineLimit(1)
                Spacer(minLength: theme.spacing(.xs))
                Text(subtitle).themedText(.caption, color: .textTertiary).lineLimit(1)
            }
            .padding(.horizontal, theme.spacing(.m))
            .padding(.vertical, theme.spacing(.xs))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier("pratiche-link-picker-row-\(reference)")
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .themedText(.body, color: .textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, theme.spacing(.l))
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Chiudi", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(theme.spacing(.m))
    }

    // MARK: Writing

    /// One shape for every row's tap and every creation confirm: run the write, then
    /// close - the picker's job ends the moment a link exists.
    private func commit(_ write: @escaping () async -> Void) {
        Task { @MainActor in
            await write()
            onClose()
        }
    }

    // MARK: Creation (R-03)

    @ViewBuilder
    private var creationSheet: some View {
        switch request.kind {
        case .board:
            boardCreationSheet
        case .note, .task:
            PraticaLinkCreationSheet(
                title: request.kind == .note ? "Nuova nota" : "Nuova attività",
                placeholder: request.kind == .note ? "Titolo della nota" : "Che cosa c'è da fare",
                text: $creationText,
                onConfirm: {
                    isCreating = false
                    let text = creationText
                    let kind = request.kind
                    commit {
                        switch kind {
                        case .note: await actions.createAndLinkNote(titled: text, for: request)
                        case .task: await actions.createAndLinkTask(texted: text, for: request)
                        case .board: break
                        }
                    }
                },
                onCancel: { isCreating = false }
            )
        }
    }

    /// R-03: ADR-0022's existing creation flow, unchanged (§D10) - the same
    /// `NewWorkspaceSheet` the Workspace sidebar's own «Nuova board» opens, over the
    /// same `CanvasStore` primitives, so this picker invents no second dialect.
    @ViewBuilder
    private var boardCreationSheet: some View {
        if let root = vault.root {
            let store = CanvasStore(root: root)
            NewWorkspaceSheet(
                kind: .board,
                parents: WorkspaceFolderSheets.parentOptions(from: store.allFolders().map { FolderPath($0) }),
                initialParent: "",
                isNameAvailable: { name, parent in store.boardNameIsAvailable(name.value, in: parent.value) },
                onConfirm: { name, parent in
                    isCreating = false
                    commit { await actions.createAndLinkBoard(named: name.value, in: parent.value, for: request) }
                },
                onCancel: { isCreating = false }
            )
        }
    }
}

/// The minimal "type a title" half of «Crea nuova…» (R-03): a note or a task needs
/// nothing beyond that, unlike a board's name-and-folder pair, which is why this is
/// its own small sheet rather than `NewWorkspaceSheet` widened for a case it does not
/// need.
private struct PraticaLinkCreationSheet: View {
    @Environment(\.theme) private var theme

    let title: String
    let placeholder: String
    @Binding var text: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var canConfirm: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(title).themedText(.title)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canConfirm { onConfirm() } }
                .accessibilityIdentifier("pratiche-link-picker-creation-field")
            HStack {
                Spacer()
                Button("Annulla", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Crea", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 360)
        .background(theme.color(.surfaceCard))
        .accessibilityIdentifier("pratiche-link-picker-creation-sheet")
    }
}
