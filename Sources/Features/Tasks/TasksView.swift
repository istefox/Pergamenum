import SwiftUI

/// The Attività sidebar and its five views (SPEC §7.4).
struct TasksView: View {
    @Environment(\.theme) var theme
    @Environment(VaultController.self) var vault
    @Environment(ShortcutStore.self) var shortcuts
    @Environment(ThemeEngine.self) private var themeEngine
    @State var view: IndexSnapshot.TaskView = .today
    /// Every board's vault-relative path, for the Workspace segment on each row and the
    /// `.workspace` grouping. Fetched once per scan rather than per row: `CanvasStore.allBoards()`
    /// is an uncached full filesystem walk (`WorkspacePicker` makes the same choice for itself).
    @State var boards: [String] = []
    @State var selectedTaskID: String?
    /// The task waiting for a note to link to (SPEC §7.2, "collegamento assistito").
    @State var linking: TaskItem?
    /// The task waiting for a due date (SPEC §7.1 `!YYYY-MM-DD`, context menu "Aggiungi scadenza").
    @State var addingDueFor: TaskItem?
    /// The task waiting for a Workspace (ADR-0021 D9, R-03). Separate from `linking`: a
    /// task carries any number of wikilinks and exactly one `^[[…]].canvas` marker, so the
    /// two are two gestures rather than one picker with a mode.
    @State var assigningWorkspaceFor: TaskItem?
    /// The "Progetti" groups the user folded shut (ADR-0021 D6), by `TaskGroup.id`.
    ///
    /// Collapsed rather than expanded ids, so a project opens showing its sub-tasks: the
    /// grouping is chosen to see the hierarchy, and a list of closed rows would hide the
    /// thing it was switched on for. Window state, not a preference - it is deliberately
    /// not in `taskListOptions`, which describes how a view reads on every launch.
    @State var collapsedProjects: Set<String> = []
    /// Every view's controls in one JSON map (ADR-0013 §D6).
    ///
    /// One key rather than five: `@AppStorage` takes a literal key, so a property per view
    /// would need a sixth the day a sixth view exists - and §7.4's five are closed precisely
    /// so that nothing else has to know how many there are.
    @AppStorage("taskListOptions") var storedOptions = ""

    var today: CalendarDate { .today }

    var body: some View {
        HStack(spacing: 0) {
            TaskViewSidebar(selection: $view)
            Divider()
            list
        }
        .background(theme.color(.backgroundPrimary))
        .toolbar { toolbar }
        .sheet(item: $linking) { task in
            QuickSwitcher(mode: .pick) { choice in
                // Only `.note` reaches here: `.pick` offers nothing else, because a heading
                // or a note that has still to be written is not something a task can link to.
                guard case .note(let path) = choice else { return }
                // The wikilink is the link (SPEC §7.2): no extra syntax, and it is
                // written into the task's own line in its own note.
                let title = NoteName.title(fromFileName: (path as NSString).lastPathComponent)
                vault.apply(.link(title), to: task)
                linking = nil
            }
        }
        .sheet(item: $addingDueFor) { task in
            dueDateSheet(for: task)
        }
        .sheet(item: $assigningWorkspaceFor) { task in
            WorkspacePicker(task: task) { assigningWorkspaceFor = nil }
        }
        .task(id: vault.scanGeneration) {
            boards = vault.root.map { CanvasStore(root: $0).allBoards() } ?? []
        }
        .onChange(of: vault.isLinkingSelectedTask) { _, requested in
            guard requested, let task = vault.selectedTask else { return }
            linking = task
            vault.isLinkingSelectedTask = false
        }
        // A captured task belongs to a view that may not be the one showing, and a
        // capture that appears nowhere reads as a capture that failed. So the pane
        // follows the task - on arrival too, since the composer works from every
        // section and the capture usually happens while this view does not exist.
        .task { followLastCapture() }
        .onChange(of: vault.taskGeneration) { _, _ in followLastCapture() }
    }

    private func followLastCapture() {
        guard let capture = vault.consumeLastCapture() else { return }
        view = switch capture.day {
        case .none: .inbox
        case .some(let day) where day <= today: .today
        default: .upcoming
        }
    }

    /// Capture, and the Task menu's actions on whatever is selected.
    ///
    /// The five views stay in the sidebar, where SPEC §7.4 puts them: they are where
    /// you are, not something you do. Every button here is also a menu item with a
    /// shortcut the user can change.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { vault.beginTaskCapture() } label: {
                Label("Cattura rapida", systemImage: "plus.circle")
            }
            .help("Cattura rapida di un task")
            .disabled(vault.root == nil)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                if let task = selected { vault.toggle(task) }
            } label: {
                Label("Completa o riapri", systemImage: "checkmark.circle")
            }
            .help("Completa o riapre il task selezionato")
            .disabled(selected == nil)

            Button {
                if let task = selected { vault.apply(.schedule(today), to: task) }
            } label: {
                Label("Pianifica oggi", systemImage: "calendar.badge.clock")
            }
            .help("Pianifica il task selezionato per oggi")
            .disabled(selected == nil)

            Button { linking = selected } label: {
                Label("Collega nota o board", systemImage: "link")
            }
            .help("Collega il task a una nota o a una board")
            .disabled(selected == nil)

            Button { assigningWorkspaceFor = selected } label: {
                Label("Assegna a un Workspace", systemImage: "rectangle.3.group")
            }
            .help("Assegna il task a un Workspace")
            .disabled(selected == nil)

            Button {
                if let task = selected { vault.openNote(at: task.sourcePath) }
            } label: {
                Label("Vai alla nota di origine", systemImage: "doc.text.magnifyingglass")
            }
            .help("Apre la nota in cui il task è scritto")
            .disabled(selected == nil)

            themeToggleToolbarItem(themeEngine)
        }
    }

    /// The selected task as the index has it now.
    ///
    /// Read back through the controller rather than kept here: the row selection is
    /// an id, and a task rewritten by one of these actions is a different value with
    /// the same id.
    private var selected: TaskItem? {
        guard let selectedTaskID else { return nil }
        return vault.index.allTasks.first { $0.id == selectedTaskID }
    }

}
