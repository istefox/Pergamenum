import SwiftUI

/// The Workspace's chrome: the bar above the board, the tool column beside it, the
/// zoom controls, the pen controls and the tray.
///
/// Lifted out of `WorkspaceView` so that file holds the board itself. Each view takes
/// exactly what it needs, which is also what makes it readable on its own.

/// Breadcrumb and save state (SPEC §6.1).
///
/// Undo, redo, Anteprima and the tray toggle used to live here too and are now in the
/// window toolbar: they are window-level commands, and the top bar is about where you
/// are on the board, not what you can do to it.
struct BoardTopBar: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController

    var body: some View {
        // Read once per redraw: `breadcrumb` is computed - it splits the folder path and
        // allocates a fresh array on every access - so reading it inside the `ForEach`
        // body cost one more array construction per segment on top of the enumeration.
        let crumbs = workspace.breadcrumb
        return HStack(spacing: theme.spacing(.xs)) {
            Circle()
                .fill(theme.color(workspace.hasUnsavedChanges ? .taskScheduled : .accentPrimary))
                .frame(width: 8, height: 8)

            ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Text("›").themedText(.body, color: .textTertiary)
                }
                if index == crumbs.count - 1 {
                    // The last segment is where you already are, so it is not a link
                    // (ADR-0024 §D8.2): as a `Button` it re-ran `open(folder:)` on the
                    // open folder, which resets the board's zoom and pan for a click
                    // that was meant to go nowhere. Emphasis carries "you are here" -
                    // the tree says it with the system's row fill and this pane's
                    // `.accentPrimary` no longer means "selected" anywhere (§D8.3).
                    Text(crumb.title).themedText(.body, color: .textPrimary)
                } else {
                    Button(crumb.title) { workspace.open(folder: crumb.folder) }
                        .buttonStyle(.plain)
                        .themedText(.body, color: .textSecondary)
                }
            }

            Spacer()

            Label(
                workspace.hasUnsavedChanges ? "Salvataggio…" : "Salvato",
                systemImage: workspace.hasUnsavedChanges ? "arrow.triangle.2.circlepath" : "checkmark.circle"
            )
            .themedText(.caption, color: .textSecondary)
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.vertical, theme.spacing(.s))
    }
}

/// The eleven tools of SPEC §6.4, in a column down the left.
struct BoardToolbar: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController

    var body: some View {
        VStack(spacing: theme.spacing(.xs)) {
            ForEach(WorkspaceController.Tool.allCases) { tool in
                Button {
                    workspace.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 30, height: 30)
                        .foregroundStyle(theme.color(
                            tool == workspace.tool ? .onAccent : (tool.isAvailable ? .textSecondary : .textTertiary)
                        ))
                        .background(tool == workspace.tool ? theme.color(.accentPrimary) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!tool.isAvailable)
                .opacity(tool.isAvailable ? 1 : 0.4)
                .overlay(alignment: .topTrailing) {
                    // A locked tool has to look locked, or the board keeps creating
                    // cards and the user cannot see why.
                    if tool == workspace.tool, workspace.isToolLocked {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(theme.color(.onAccent))
                            .padding(2)
                    }
                }
                // Double click keeps the tool active instead of returning to
                // Seleziona after one use (SPEC §6.4).
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    workspace.tool = tool
                    workspace.isToolLocked.toggle()
                })
                .help(tool.shortcut.map { "\(tool.title) (\($0.uppercased()))" } ?? tool.title)
                .keyboardShortcut(tool.shortcut.map { KeyEquivalent(Character($0)) } ?? "\0", modifiers: [])
            }
            Spacer()
        }
        .padding(theme.spacing(.xs))
        .frame(width: 44)
    }
}

/// Zoom out, the current percentage, zoom in, zoom to fit (SPEC §6.1).
struct BoardZoomControls: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController
    let viewportSize: CGSize

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Button { workspace.zoom(by: 1 / 1.25) } label: { Image(systemName: "minus") }
            Button { workspace.resetZoom() } label: {
                Text("\(Int(workspace.zoom * 100))%").themedText(.caption)
            }
            Button { workspace.zoom(by: 1.25) } label: { Image(systemName: "plus") }
            Divider().frame(height: 12)
            Button { workspace.zoomToFit(in: viewportSize) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.color(.textSecondary))
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .background(theme.color(.surfaceRaised))
        .clipShape(Capsule())
        .themedShadow(.card)
    }
}

/// Colour, width, eraser and "Fatto" for the Disegno tool (SPEC §6.4, tool 10).
struct BoardPenControls: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController
    @Binding var penColor: ColorToken
    @Binding var penWidth: CGFloat
    @Binding var isErasing: Bool

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            ForEach([ColorToken.textPrimary, .accentPrimary, .taskOverdue, .stickyYellow], id: \.self) { token in
                Circle()
                    .fill(theme.color(token))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle().strokeBorder(
                            token == penColor ? theme.color(.canvasSelection) : theme.color(.borderSubtle),
                            lineWidth: token == penColor ? 2 : 1
                        )
                    )
                    .onTapGesture { penColor = token; isErasing = false }
            }
            Divider().frame(height: 14)
            ForEach([CGFloat(2), 6, 14], id: \.self) { width in
                Circle()
                    .fill(theme.color(width == penWidth && !isErasing ? .accentPrimary : .textTertiary))
                    .frame(width: width + 4, height: width + 4)
                    .onTapGesture { penWidth = width; isErasing = false }
            }
            Divider().frame(height: 14)
            Image(systemName: "eraser")
                .foregroundStyle(theme.color(isErasing ? .accentPrimary : .textSecondary))
                .onTapGesture { isErasing.toggle() }
            Divider().frame(height: 14)
            Button("Fatto") {
                _ = workspace.commitDrawing()
                workspace.tool = .select
            }
            .buttonStyle(.plain)
            .themedText(.caption, color: .accentPrimary)
            .disabled(workspace.activeDrawing.strokes.isEmpty)
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .background(theme.color(.surfaceRaised))
        .clipShape(Capsule())
        .themedShadow(.card)
    }
}

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

    /// R-05: the tasks that named this board with `^[[…]]`, completable where they are
    /// shown. `vault.toggle` writes the task's own note, never a copy.
    ///
    /// Deliberately disjoint from "TASK COLLEGATI" above it (ADR-0021 §D1): the
    /// assignment marker is removed from `TaskItem.links`, so a task appears in exactly
    /// one of the two sections and the pair is not a duplicate list.
    private var assignedTasks: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(spacing: theme.spacing(.xs)) {
                Text("TASK ASSEGNATI").themedText(.caption, color: .textTertiary)
                if !assigned.tasks.isEmpty {
                    Text("\(assigned.open)/\(assigned.tasks.count)")
                        .themedText(.caption, color: .textTertiary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Task assegnati a questa board: \(assigned.tasks.count)")
            .accessibilityIdentifier("board-assigned-tasks-header")

            if assigned.tasks.isEmpty {
                Text("nessun task assegnato a questa board")
                    .themedText(.caption, color: .textTertiary)
            } else {
                ForEach(assigned.tasks) { task in
                    TaskPanelRow(task: task, identifierPrefix: "assigned-task")
                }
            }
        }
        .task(id: AssignedKey(generation: vault.taskGeneration, board: boardFileName)) {
            refreshAssignedTasks()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board-assigned-tasks")
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
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(spacing: theme.spacing(.xs)) {
                Text("NOTE REFERENZIATE").themedText(.caption, color: .textTertiary)
                if !references.isEmpty {
                    Text("\(references.count)").themedText(.caption, color: .textTertiary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Note referenziate da questa board: \(references.count)")
            .accessibilityIdentifier("board-referenced-notes-header")

            if references.isEmpty {
                Text("nessuna nota su questa board")
                    .themedText(.caption, color: .textTertiary)
            } else {
                ForEach(references, id: \.self) { reference in
                    noteRow(reference)
                }
            }
        }
        .task(id: workspace.document) {
            refreshReferencedNotes()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("board-referenced-notes")
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
