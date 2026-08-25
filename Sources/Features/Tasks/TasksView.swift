import SwiftUI

/// The Attività sidebar and its five views (SPEC §7.4).
struct TasksView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(ShortcutStore.self) private var shortcuts
    @State private var view: IndexSnapshot.TaskView = .today
    /// Every board's vault-relative path, for the Workspace segment on each row and the
    /// `.workspace` grouping. Fetched once per scan rather than per row: `CanvasStore.allBoards()`
    /// is an uncached full filesystem walk (`WorkspacePicker` makes the same choice for itself).
    @State private var boards: [String] = []
    @State private var selectedTaskID: String?
    /// The task waiting for a note to link to (SPEC §7.2, "collegamento assistito").
    @State private var linking: TaskItem?
    /// The task waiting for a due date (SPEC §7.1 `!YYYY-MM-DD`, context menu "Aggiungi scadenza").
    @State private var addingDueFor: TaskItem?
    /// The task waiting for a Workspace (ADR-0021 D9, R-03). Separate from `linking`: a
    /// task carries any number of wikilinks and exactly one `^[[…]].canvas` marker, so the
    /// two are two gestures rather than one picker with a mode.
    @State private var assigningWorkspaceFor: TaskItem?
    /// The "Progetti" groups the user folded shut (ADR-0021 D6), by `TaskGroup.id`.
    ///
    /// Collapsed rather than expanded ids, so a project opens showing its sub-tasks: the
    /// grouping is chosen to see the hierarchy, and a list of closed rows would hide the
    /// thing it was switched on for. Window state, not a preference - it is deliberately
    /// not in `taskListOptions`, which describes how a view reads on every launch.
    @State private var collapsedProjects: Set<String> = []
    /// Every view's controls in one JSON map (ADR-0013 §D6).
    ///
    /// One key rather than five: `@AppStorage` takes a literal key, so a property per view
    /// would need a sixth the day a sixth view exists - and §7.4's five are closed precisely
    /// so that nothing else has to know how many there are.
    @AppStorage("taskListOptions") private var storedOptions = ""

    private var today: CalendarDate { .today }

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

    // MARK: List

    private var list: some View {
        // Both halves computed once here rather than read twice from the body: the rows need
        // to know which of them are rolled over, and asking a second time would be a second
        // pass over every task in the vault on every redraw.
        let rolled = rolledOverGroup
        let arranged = arrangedGroups + rolled
        let rolledIDs = Set(rolled.first?.tasks.map(\.id) ?? [])
        return VStack(alignment: .leading, spacing: 0) {
            TaskListControls(title: view.title, options: optionsBinding)
                .padding(.horizontal, theme.spacing(.l))
                .padding(.top, theme.spacing(.s))

            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                    ForEach(arranged) { group in
                        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                            if let parent = group.parent {
                                project(group, parent: parent, rolledIDs: rolledIDs)
                            } else {
                                // An ungrouped list has one group with no title, and no
                                // heading is drawn for it: a single "Oggi" above the day's
                                // own view says nothing the sidebar has not already said.
                                if !group.title.isEmpty {
                                    Text(group.title).themedText(.heading)
                                }
                                ForEach(group.tasks) { task in
                                    row(task, isRolledOver: rolledIDs.contains(task.id))
                                }
                            }
                        }
                    }
                    if arranged.isEmpty {
                        Text("Nessun task in questa vista")
                            .themedText(.body, color: .textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, theme.spacing(.xl))
                    }
                }
                .padding(theme.spacing(.l))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The controls of the view showing, read back from the one stored map and written
    /// straight into it. A binding rather than `@State` mirrored onto storage: two copies of
    /// a preference is how one of them ends up stale after a view switch.
    private var optionsBinding: Binding<TaskListOptions> {
        Binding(
            get: { options },
            set: { newValue in
                var map = TaskListOptions.map(fromJSON: storedOptions)
                map[view.rawValue] = newValue
                storedOptions = TaskListOptions.json(of: map)
            }
        )
    }

    private var options: TaskListOptions {
        TaskListOptions.map(fromJSON: storedOptions)[view.rawValue] ?? view.defaultListOptions
    }

    /// The current view's tasks, arranged the way its controls ask (ADR-0013 §D6).
    ///
    /// The arrangement itself is in `TaskArrangement`, outside SwiftUI, because a sort that is
    /// not stable and a group that swallows the tasks with nothing to group by are defects a
    /// test can hold and a screenshot cannot.
    private var arrangedGroups: [TaskGroup] {
        TaskArrangement.groups(
            vault.index.tasks(for: view, on: today),
            options: options,
            // Only *Tutti* floats its starred notes, which is where the roadmap asks for them:
            // in a view already grouped by day or by project, a star would fight the grouping
            // the user chose rather than help it.
            priorityPaths: view == .all ? Set(vault.starredNotes.map(\.relativePath)) : [],
            boards: boards
        )
    }

    /// The unfinished tasks of the days before today, under their own heading and only in
    /// *Oggi* (ADR-0013 §D1).
    ///
    /// A group appended after the arrangement rather than a sixth grouping: what belongs to an
    /// earlier day is not another way of cutting today's list, it is a second list. The
    /// controls of §D6 act on the day's own tasks and leave this one alone, which is why it is
    /// added here and not passed through `TaskArrangement`.
    private var rolledOverGroup: [TaskGroup] {
        guard view == .today, vault.settings.rollover else { return [] }
        let tasks = vault.index.rolledOverTasks(
            on: today, daysBack: vault.settings.rolloverDays
        )
        return tasks.isEmpty ? [] : [TaskGroup(title: TasksView.rolledOverTitle, tasks: tasks)]
    }

    /// The key that does the same thing from the Task menu, read from the store rather than
    /// written here: it is user-editable, and it already moved once - `Cmd+0` became
    /// `Opt+Cmd+0` when `Cmd+1…9` went to the tabs (ADR-0012 §D5). A hardcoded glyph in this
    /// row would have been wrong from the day it was typed, and the approved mockup still
    /// carries the old one.
    private var moveKey: String { shortcuts.binding(for: .taskToday).displayString }

    private static let rolledOverTitle = "Rimandati"

    /// A "Progetti" group: the parent task on the disclosure header, its `^parent` children
    /// indented beneath it, and how many of them are done beside the header (ADR-0021 D6).
    ///
    /// The header is the **same** `row` every other task is drawn with, so a project is
    /// completable, selectable and right-clickable exactly like the tasks under it - it is
    /// a task, and a heading that only looked like one would be a second row view to keep
    /// in step with this one.
    private func project(
        _ group: TaskGroup, parent: TaskItem, rolledIDs: Set<String>
    ) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { !collapsedProjects.contains(group.id) },
                set: { expanded in
                    if expanded {
                        collapsedProjects.remove(group.id)
                    } else {
                        collapsedProjects.insert(group.id)
                    }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                ForEach(group.tasks) { task in
                    row(task, isRolledOver: rolledIDs.contains(task.id))
                }
            }
            .padding(.leading, theme.spacing(.m))
            .padding(.top, theme.spacing(.xs))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.s)) {
                row(parent)
                if let progress = group.progress {
                    Text("\(progress.done)/\(progress.total)")
                        .themedText(.mono, color: .textTertiary)
                        // Read out in words: "1/3" is a date to VoiceOver as often as a date.
                        .accessibilityLabel(
                            "\(progress.done) di \(progress.total) completati"
                        )
                        // On macOS, `.accessibilityIdentifier` applied to an ANCESTOR
                        // propagates onto every descendant AX element in the same view
                        // subtree that has no identifier of its own on THAT element,
                        // *and even overrides one a descendant already set* - confirmed
                        // twice by reading an exported UI-hierarchy attachment: first
                        // with the identifier on the whole DisclosureGroup (it leaked
                        // onto the disclosed child rows below, replacing their own
                        // "task-row"), then with it on this HStack (it still overrode
                        // row(parent)'s own "task-row", one level up). Putting it on
                        // this Text - a leaf with no identifier of its own, and a
                        // sibling of row(parent) rather than a container of it - is
                        // what keeps it from touching anything else. Safe because
                        // TaskListOptions.bySubtasks(_:) always sets `progress`
                        // together with `parent` - see its own comment - so this
                        // branch runs whenever `project(_:parent:rolledIDs:)` does.
                        .accessibilityIdentifier("task-project-group")
                }
            }
        }
    }

    private func row(_ task: TaskItem, isRolledOver: Bool = false) -> some View {
        let isSelected = selectedTaskID == task.id
        return ThemedCard(padding: .s) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.s)) {
                Image(systemName: task.state == .done ? "checkmark.square" : "square")
                    .foregroundStyle(theme.color(task.isOverdue(on: today) ? .taskOverdue : .taskOpen))
                    .onTapGesture { vault.toggle(task) }

                // A minimal marker in both densities (R-05): the assignment itself is worth
                // knowing about even in the one-line row that has no room for which board.
                if task.workspacePath != nil {
                    Image(systemName: "rectangle.3.group")
                        .foregroundStyle(theme.color(.textTertiary))
                        .help("Assegnato a un Workspace")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.text)
                        .themedText(.body, color: task.state == .done ? .taskDone : .textPrimary)
                    // The second line is what the compact density drops (ADR-0013 §D6): the
                    // task itself and its marker are what a list is read for, and the note it
                    // came from is what it is worked from.
                    if options.density == .expanded { details(task) }
                }

                Spacer()

                // A rolled-over row says which day it belongs to, and says it instead of the
                // ISO marker every other row carries: without that the row would look like an
                // ordinary one, which is the silent move SPEC §7.3 refuses drawn instead of
                // written (ADR-0013 §D1).
                if isRolledOver, let scheduled = task.scheduled {
                    Text(RolloverMarker.text(for: scheduled))
                        .themedText(.caption, color: .taskOverdue)
                    Button("Porta a oggi") { vault.apply(.schedule(today), to: task) }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.color(.accentPrimary))
                        .help("Riscrive «>data» nella nota di origine (\(moveKey) sul task selezionato)")
                } else {
                    // Both shown together when both exist (R-06): a task past its deadline but
                    // rescheduled ahead of it used to lose one of the two markers silently.
                    if let due = task.due {
                        Text("!\(due)").themedText(.mono, color: .taskOverdue)
                    }
                    if let scheduled = task.scheduled {
                        Text(">\(scheduled)").themedText(.mono, color: .taskScheduled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .strokeBorder(isSelected ? theme.color(.canvasSelection) : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedTaskID = task.id
            // Shared with the Task menu so Cmd+0/1/2/3 act on what is selected here.
            vault.selectedTask = task
        }
        // The row is a stack of texts and buttons, and reported that way it has no
        // label of its own: from outside the app - to VoiceOver as much as to a test -
        // the list read as a column of blanks.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("task-row")
        .contextMenu { contextMenu(task) }
    }

    /// The row's second line: where the task is written, what it links to, its project, its
    /// assigned Workspace and its tags. Its own function so `row` stays inside the length
    /// SwiftLint asks for, which is the same reason the controls are their own view.
    private func details(_ task: TaskItem) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Button {
                vault.openNote(at: task.sourcePath)
            } label: {
                Text("↗ \(TaskArrangement.noteTitle(of: task))")
                    .themedText(.caption, color: .textTertiary)
            }
            .buttonStyle(.plain)

            // SPEC §7.2: each wikilink is clickable and opens its target.
            ForEach(task.links, id: \.self) { link in
                Button {
                    open(link: link)
                } label: {
                    Text(link).themedText(.caption, color: .accentPrimary)
                }
                .buttonStyle(.plain)
            }

            if let project = task.project {
                Text(project.description).themedText(.caption, color: .textTertiary)
            }

            workspaceSegment(task)

            ForEach(task.tags, id: \.self) { tag in
                ViewTagChip(text: "#\(tag.description)")
            }
        }
    }

    /// The assigned-Workspace segment of `details` (R-01…R-04): a clickable full path when the
    /// stored file name resolves to exactly one board, a bare name that opens `WorkspacePicker`
    /// when it is ambiguous, or plain text when the reference is orphaned. Nothing at all when
    /// the task carries no `^[[…]].canvas` marker.
    @ViewBuilder
    private func workspaceSegment(_ task: TaskItem) -> some View {
        switch WorkspaceBoardResolver.resolve(task.workspacePath, in: boards) {
        case .unique(let path):
            Button {
                vault.routeState.pendingCanvas = (path, nil)
            } label: {
                Text("▦ \(path)").themedText(.caption, color: .accentPrimary)
            }
            .buttonStyle(.plain)
        case .ambiguous:
            Button {
                assigningWorkspaceFor = task
            } label: {
                Text("▦ \(WorkspaceBoardResolver.fileName(of: task.workspacePath ?? ""))")
                    .themedText(.caption, color: .textTertiary)
            }
            .buttonStyle(.plain)
        case .notFound:
            if let workspacePath = task.workspacePath {
                Text("▦ \(workspacePath)").themedText(.caption, color: .textTertiary)
            }
        }
    }

    @ViewBuilder
    private func contextMenu(_ task: TaskItem) -> some View {
        Button(task.state == .done ? "Riapri" : "Completa") { vault.toggle(task) }
        Divider()
        // The Task menu's own entry, on the row it is about (ADR-0023 §D6, R-05). The
        // title comes from the shortcut catalogue rather than from a second literal, so
        // rewording the menu item rewords this one; the draft comes from
        // `TaskDraft.subtask(of:)`, so both entry points compose the same sub-task.
        //
        // Selecting the row is part of the command: the four rescheduling keys act on
        // `vault.selectedTask`, and a right-click that opened the composer while leaving
        // them pointed at whatever was clicked before would arm them at the wrong task.
        Button(ShortcutCommand.taskAddSubtask.title) {
            selectedTaskID = task.id
            vault.selectedTask = task
            vault.taskDraft = .subtask(of: task)
        }
        // The quick reschedule of SPEC §7.3.
        Button("Pianifica oggi") { vault.apply(.schedule(today), to: task) }
        Button("Domani") { vault.apply(.schedule(today.adding(days: 1)), to: task) }
        Button("+2 giorni") { vault.apply(.schedule(today.adding(days: 2)), to: task) }
        Button("Settimana prossima") { vault.apply(.schedule(today.adding(days: 7)), to: task) }
        Button("Togli la data") { vault.apply(.schedule(nil), to: task) }
        Button("Aggiungi scadenza…") { addingDueFor = task }
        Divider()
        Button("Collega nota o board…") { linking = task }
        Button("Assegna a un Workspace…") { assigningWorkspaceFor = task }
        Divider()
        Button("Annulla task") { vault.apply(.state(.cancelled), to: task) }
        Button("Vai alla nota di origine") { vault.openNote(at: task.sourcePath) }
    }

    /// The date picker for "Aggiungi scadenza…" (SPEC §7.1 `!YYYY-MM-DD`).
    private func dueDateSheet(for task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Scadenza").themedText(.title)
            MonthCalendar(
                selection: .constant(task.due),
                onPick: { date in
                    vault.apply(.due(date), to: task)
                    addingDueFor = nil
                }
            )
            HStack {
                if task.due != nil {
                    Button("Rimuovi scadenza") {
                        vault.apply(.due(nil), to: task)
                        addingDueFor = nil
                    }
                }
                Spacer()
                Button("Chiudi") { addingDueFor = nil }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 320)
    }

    private func open(link target: String) {
        // A link ending in .canvas points at a board; anything else is a note.
        if target.lowercased().hasSuffix(".canvas") { return }
        if let path = vault.index.resolve(title: target).first {
            vault.openNote(at: path)
        }
    }

}
