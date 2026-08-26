import SwiftUI

/// The board's right-hand column, lifted out of `BoardChrome.swift`: that file holds the
/// furniture around the board (top bar, tool column, zoom and pen controls), while the tray
/// is a panel of its own, with its own held state and its own refresh plumbing.

/// The right-hand column: items in the folder not yet on the board, the tasks that
/// link to this board, and the board's dashboard - the tasks assigned to it and the
/// notes it carries (SPEC §6.1, §7.2; ADR-0021 §D7, §D8).
///
/// The dashboard goes here rather than into a second trailing column, which is the
/// whole of D7: this column is the structural slot the UX blueprint points at, and a
/// board with two inspectors would be the second mechanism it asks us not to build.
struct BoardTray: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    let workspace: WorkspaceController

    /// The tasks assigned to this board, and how many of them are still open.
    ///
    /// Held rather than queried per draw: `index.tasks(assignedToWorkspace:)` sorts every
    /// note in the vault and flat-maps every task out of it, and this tray redraws on every
    /// observable change it reads - a card dragged across the board included. Refreshed on
    /// `taskGeneration`, the same counter `TasksView` and `TodayView` watch, which every
    /// completed scan and every task line the app writes bumps.
    @State private var assigned = AssignedTasks()

    /// The notes this board carries, held rather than derived per draw.
    ///
    /// `WorkspaceReferences.notes(in:)` walks every node and runs `WikilinkParser.links`
    /// over the text of every text card, so computing it inside `body` re-parsed the whole
    /// board on every observable change this tray reads - a card dragged across it
    /// included. Refreshed on the document itself, which is `Equatable`: a board's
    /// references cannot change without it changing, and a drag stays transient until it
    /// commits, so this recomputes once per real mutation rather than once per redraw.
    @State private var references: [String] = []

    /// What `assigned` was computed from. A type rather than an interpolated string so the
    /// two parts of the key cannot run into each other.
    private struct AssignedKey: Equatable {
        let generation: Int
        let board: String
    }

    /// The count comes out of the same pass that collects the tasks: a second `filter` over
    /// the result was another array allocated per draw for a number.
    private struct AssignedTasks {
        var tasks: [TaskItem] = []
        var open = 0
    }

    var body: some View {
        // Four sections do not fit a 200-point column, and the one that overflows is
        // whichever happens to be last rather than the least important.
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                if !workspace.contents.unplaced.isEmpty {
                    newItems
                }
                // SPEC §7.2: the board shows the tasks that link to it, exactly as a note
                // does. The link target is the `.canvas` file name, which is how a
                // wikilink names a board.
                LinkedTasksPanel(
                    title: boardFileName,
                    emptyText: "nessun task linka questa board"
                )
                assignedTasks
                referencedNotes
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(theme.spacing(.s))
        }
        .frame(width: 200)
        .background(theme.color(.backgroundSecondary))
        .accessibilityIdentifier("board-tray")
    }

    // MARK: Dashboard

    /// The shape both dashboard sections have: a caption header with an optional count
    /// badge, then either one line of empty text or the rows. Written once because the
    /// two were identical down to the spacing and the colour token on every piece of
    /// text, and a header that drifts from the one under it is the kind of difference
    /// nobody decided on.
    ///
    /// The refresh trigger stays at the call site: the two watch different things (a task
    /// generation, the document itself), and that is the one part of a section that is
    /// genuinely its own.
    private func traySection<Rows: View>(
        title: String,
        badge: String?,
        accessibilityLabel: String,
        identifier: String,
        isEmpty: Bool,
        emptyText: String,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(spacing: theme.spacing(.xs)) {
                Text(title).themedText(.caption, color: .textTertiary)
                if let badge {
                    Text(badge).themedText(.caption, color: .textTertiary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier("\(identifier)-header")

            if isEmpty {
                Text(emptyText).themedText(.caption, color: .textTertiary)
            } else {
                rows()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    /// R-05: the tasks that named this board with `^[[…]]`, completable where they are
    /// shown. `vault.toggle` writes the task's own note, never a copy.
    ///
    /// Deliberately disjoint from "TASK COLLEGATI" above it (ADR-0021 §D1): the
    /// assignment marker is removed from `TaskItem.links`, so a task appears in exactly
    /// one of the two sections and the pair is not a duplicate list.
    private var assignedTasks: some View {
        traySection(
            title: "TASK ASSEGNATI",
            badge: assigned.tasks.isEmpty ? nil : "\(assigned.open)/\(assigned.tasks.count)",
            accessibilityLabel: "Task assegnati a questa board: \(assigned.tasks.count)",
            identifier: "board-assigned-tasks",
            isEmpty: assigned.tasks.isEmpty,
            emptyText: "nessun task assegnato a questa board"
        ) {
            ForEach(assigned.tasks) { task in
                TaskPanelRow(task: task, identifierPrefix: "assigned-task")
            }
        }
        .task(id: AssignedKey(generation: vault.taskGeneration, board: boardFileName)) {
            refreshAssignedTasks()
        }
    }

    private func refreshAssignedTasks() {
        let tasks = vault.index.tasks(assignedToWorkspace: boardFileName)
        assigned = AssignedTasks(
            tasks: tasks,
            open: tasks.reduce(into: 0) { count, task in
                if task.state != .done { count += 1 }
            }
        )
    }

    /// R-06: the notes this board carries, read from the open document and never from
    /// the index (ADR-0021 §D8) - the index would answer "which notes mention this
    /// board", which is a different question and wrong for a card placed and never
    /// linked.
    private var referencedNotes: some View {
        traySection(
            title: "NOTE REFERENZIATE",
            badge: references.isEmpty ? nil : "\(references.count)",
            accessibilityLabel: "Note referenziate da questa board: \(references.count)",
            identifier: "board-referenced-notes",
            isEmpty: references.isEmpty,
            emptyText: "nessuna nota su questa board"
        ) {
            ForEach(references, id: \.self) { reference in
                noteRow(reference)
            }
        }
        .task(id: workspace.document) {
            refreshReferencedNotes()
        }
    }

    private func refreshReferencedNotes() {
        references = WorkspaceReferences.notes(in: workspace.document)
    }

    private func noteRow(_ reference: String) -> some View {
        // A `.file` card carries a vault path; a wikilink inside a text card carries a
        // title, resolved through the index for display and left exactly as written
        // when it resolves to nothing (D8) - an unresolved link is still a fact about
        // the board.
        //
        // The name is bound once because the row writes it twice, as the label and as
        // the accessibility label: computed at each of them, every redraw of the tray
        // paid a second NSString bridge and a second `NoteName.title(fromFileName:)`
        // for every row - and this tray redraws on every observable change it reads, a
        // card dragged across the board included.
        let path = resolvedPath(for: reference)
        let name = displayName(for: reference, path: path)
        return Button {
            if let path { vault.openNote(at: path) }
        } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: path == nil ? "questionmark.square.dashed" : "doc.text")
                    .foregroundStyle(theme.color(path == nil ? .textTertiary : .textSecondary))
                Text(name)
                    .themedText(.caption, color: path == nil ? .textTertiary : .textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(path == nil)
        .help(path ?? "nota non trovata nel vault")
        .accessibilityLabel("Nota \(name)")
        .accessibilityIdentifier("board-referenced-note-\(reference)")
    }

    private func resolvedPath(for reference: String) -> String? {
        if vault.index.notes[reference] != nil { return reference }
        let title = ((reference as NSString).lastPathComponent as NSString)
            .deletingPathExtension
        return vault.index.resolve(title: title).first
    }

    private func displayName(for reference: String, path: String?) -> String {
        guard let path else { return reference }
        return NoteName.title(fromFileName: (path as NSString).lastPathComponent)
    }

    /// The board's own file name, as a wikilink would write it.
    ///
    /// Read from the store the controller already holds rather than from a fresh one:
    /// `CanvasStore.init` calls `resolvingSymlinksInPath().standardizedFileURL`, so
    /// building a store here charged the tray a filesystem syscall per access - twice
    /// per draw, on a view that redraws for every observable change it reads, a card
    /// dragged across the board included. The value is the same: the store is attached
    /// from the same `vault.root` (`WorkspaceView.attachWorkspace`), and a board is only
    /// ever on screen when `load(folder:)` found one, which needs the store anyway.
    private var boardFileName: String {
        guard let store = workspace.store else { return "" }
        return (store.boardPath(forFolder: workspace.folder) as NSString).lastPathComponent
    }

    private var newItems: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("NUOVI ELEMENTI").themedText(.caption, color: .textTertiary)
            Text("Trascina o clicca per posare sulla board.")
                .themedText(.caption, color: .textTertiary)

            // No `ScrollView` of its own any more: the tray scrolls as one column, and
            // a vertical scroll view nested in another has no height to work with.
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                ForEach(workspace.contents.unplaced, id: \.self) { path in
                    Button {
                        _ = workspace.placeFile(path, at: CGPoint(x: 60, y: 60))
                    } label: {
                        HStack(spacing: theme.spacing(.xs)) {
                            Image(systemName: workspace.subfolderSet.contains(path)
                                  ? "folder" : "doc")
                            Text((path as NSString).lastPathComponent)
                                .themedText(.caption)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
