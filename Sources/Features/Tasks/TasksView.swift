import SwiftUI

/// The Attività sidebar and its five views (SPEC §7.4).
struct TasksView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @State private var view: IndexSnapshot.TaskView = .today
    @State private var selectedTaskID: String?
    /// The task waiting for a note to link to (SPEC §7.2, "collegamento assistito").
    @State private var linking: TaskItem?
    /// Every view's controls in one JSON map (ADR-0013 §D6).
    ///
    /// One key rather than five: `@AppStorage` takes a literal key, so a property per view
    /// would need a sixth the day a sixth view exists - and §7.4's five are closed precisely
    /// so that nothing else has to know how many there are.
    @AppStorage("taskListOptions") private var storedOptions = ""

    private var today: CalendarDate { .today }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
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

    // MARK: Sidebar

    private var sidebar: some View {
        let counts = vault.index.taskCounts(on: today)
        return VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("ATTIVITÀ").themedText(.caption, color: .textTertiary)

            ForEach(IndexSnapshot.TaskView.allCases) { item in
                HStack {
                    Text(item.title)
                        .themedText(.body, color: item == view ? .textPrimary : .textSecondary)
                    Spacer()
                    if let count = counts[item], count > 0 {
                        Text("\(count)").themedText(.caption, color: .textTertiary)
                    }
                }
                .padding(.horizontal, theme.spacing(.s))
                .padding(.vertical, theme.spacing(.xs))
                .background(item == view ? theme.color(.accentMuted) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { view = item }
            }

            Spacer()

            Button {
                vault.beginTaskCapture()
            } label: {
                Label("Cattura rapida", systemImage: "plus.circle")
                    .themedText(.caption, color: .accentPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(theme.spacing(.s))
        .frame(width: 200, alignment: .leading)
        .background(theme.color(.backgroundSecondary))
    }

    // MARK: List

    private var list: some View {
        let arranged = groups
        return VStack(alignment: .leading, spacing: 0) {
            TaskListControls(title: view.title, options: optionsBinding)
                .padding(.horizontal, theme.spacing(.l))
                .padding(.top, theme.spacing(.s))

            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                    ForEach(arranged) { group in
                        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                            // An ungrouped list has one group with no title, and no heading
                            // is drawn for it: a single "Oggi" above the day's own view says
                            // nothing the sidebar has not already said.
                            if !group.title.isEmpty {
                                Text(group.title).themedText(.heading)
                            }
                            ForEach(group.tasks) { task in
                                row(task)
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
    private var groups: [TaskGroup] {
        TaskArrangement.groups(
            vault.index.tasks(for: view, on: today),
            options: options,
            // Only *Tutti* floats its starred notes, which is where the roadmap asks for them:
            // in a view already grouped by day or by project, a star would fight the grouping
            // the user chose rather than help it.
            priorityPaths: view == .all ? Set(vault.starredNotes.map(\.relativePath)) : []
        )
    }

    private func row(_ task: TaskItem) -> some View {
        let isSelected = selectedTaskID == task.id
        return ThemedCard(padding: .s) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.s)) {
                Image(systemName: task.state == .done ? "checkmark.square" : "square")
                    .foregroundStyle(theme.color(task.isOverdue(on: today) ? .taskOverdue : .taskOpen))
                    .onTapGesture { vault.toggle(task) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.text)
                        .themedText(.body, color: task.state == .done ? .taskDone : .textPrimary)
                    // The second line is what the compact density drops (ADR-0013 §D6): the
                    // task itself and its marker are what a list is read for, and the note it
                    // came from is what it is worked from.
                    if options.density == .expanded { details(task) }
                }

                Spacer()

                if let due = task.due {
                    Text("!\(due)").themedText(.mono, color: .taskOverdue)
                } else if let scheduled = task.scheduled {
                    Text(">\(scheduled)").themedText(.mono, color: .taskScheduled)
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

    /// The row's second line: where the task is written, what it links to, and its project.
    /// Its own function so `row` stays inside the length SwiftLint asks for, which is the same
    /// reason the controls are their own view.
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
        }
    }

    @ViewBuilder
    private func contextMenu(_ task: TaskItem) -> some View {
        Button(task.state == .done ? "Riapri" : "Completa") { vault.toggle(task) }
        Divider()
        // The quick reschedule of SPEC §7.3.
        Button("Pianifica oggi") { vault.apply(.schedule(today), to: task) }
        Button("Domani") { vault.apply(.schedule(today.adding(days: 1)), to: task) }
        Button("+2 giorni") { vault.apply(.schedule(today.adding(days: 2)), to: task) }
        Button("Settimana prossima") { vault.apply(.schedule(today.adding(days: 7)), to: task) }
        Button("Togli la data") { vault.apply(.schedule(nil), to: task) }
        Divider()
        Button("Collega nota o board…") { linking = task }
        Divider()
        Button("Annulla task") { vault.apply(.state(.cancelled), to: task) }
        Button("Vai alla nota di origine") { vault.openNote(at: task.sourcePath) }
    }

    private func open(link target: String) {
        // A link ending in .canvas points at a board; anything else is a note.
        if target.lowercased().hasSuffix(".canvas") { return }
        if let path = vault.index.resolve(title: target).first {
            vault.openNote(at: path)
        }
    }

}
