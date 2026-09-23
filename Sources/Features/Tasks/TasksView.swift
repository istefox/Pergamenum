import SwiftUI

/// The Attività sidebar and its five views (SPEC §7.4).
struct TasksView: View {
    @Environment(\.theme) var theme
    @Environment(VaultController.self) var vault
    @Environment(ShortcutStore.self) var shortcuts
    @Environment(ThemeEngine.self) private var themeEngine
    @Environment(Navigation.self) var navigation
    @Environment(CommandActions.self) var actions
    /// The pratiche list the rows' pratica badges are read against (`TasksView+Pratiche.swift`).
    @Environment(PraticheController.self) var pratiche
    /// One derived selection (ADR-0047 §D6): a view of SPEC §7.4, or a category row. Held
    /// on `Navigation` (PG-206), not here, since this view is recreated every time the
    /// pane is shown again and a `@State` here would forget it each time.
    var selection: TaskPaneSelection {
        get { navigation.taskSelection }
        nonmutating set { navigation.taskSelection = newValue }
    }
    /// Every board's vault-relative path, for the Workspace segment on each row and the
    /// `.workspace` grouping. Fetched once per scan rather than per row: `CanvasStore.allBoards()`
    /// is an uncached full filesystem walk (`WorkspacePicker` makes the same choice for itself).
    @State var boards: [String] = []
    @State var selectedTaskID: String?
    /// The task waiting for a due date (SPEC §7.1 `!YYYY-MM-DD`, context menu "Aggiungi scadenza").
    @State var addingDueFor: TaskItem?
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
            TaskViewSidebar(selection: Bindable(navigation).taskSelection)
            Divider()
            list
        }
        .background(theme.color(.backgroundPrimary))
        .toolbar { toolbar }
        .sheet(item: $addingDueFor) { task in
            dueDateSheet(for: task)
        }
        .task(id: vault.scanGeneration) {
            boards = vault.root.map { CanvasStore(root: $0).allBoards() } ?? []
            // The pratiche list is filled only by whoever calls `load(from:)`, and the
            // Pratiche pane does so only in its own `.task` - so without this a fresh launch
            // would draw no pratica badge until that pane had been opened once. The same
            // call `PraticheSettingsTab` makes; it reads the ledger, the index and the
            // `pratica.md` files, never the Mail store (ADR-0036 §D10 holds). With no vault
            // open, the no-vault reset stays with the Pratiche surfaces that own it.
            if vault.session != nil { pratiche.load(from: vault) }
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
        selection = .view(.landing(forCapturedDay: capture.day, today: today))
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
                if let task = selected { Task { await vault.toggle(task) } }
            } label: {
                Label("Completa o riapri", systemImage: "checkmark.circle")
            }
            .help("Completa o riapre il task selezionato")
            .disabled(selected == nil)

            Button {
                if let task = selected { Task { await vault.apply(.schedule(today), to: task) } }
            } label: {
                Label("Pianifica oggi", systemImage: "calendar.badge.clock")
            }
            .help("Pianifica il task selezionato per oggi")
            .disabled(selected == nil)

            Button {
                if let task = selected { actions.run(.linkBoard, on: task) }
            } label: {
                Label(TaskCommand.linkBoard.title, systemImage: TaskCommand.linkBoard.symbol)
            }
            .help("Collega il task a una board")
            .disabled(selected == nil)

            Button {
                if let task = selected { actions.run(.goToNote, on: task) }
            } label: {
                Label(TaskCommand.goToNote.title, systemImage: TaskCommand.goToNote.symbol)
            }
            .help("Apre la nota in cui il task è scritto")
            .disabled(selected == nil)

            if let task = selected, task.workspacePath != nil {
                Button {
                    actions.run(.goToBoard, on: task)
                } label: {
                    Label(TaskCommand.goToBoard.title, systemImage: TaskCommand.goToBoard.symbol)
                }
                .help("Apre la board a cui il task è assegnato")
            }

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
