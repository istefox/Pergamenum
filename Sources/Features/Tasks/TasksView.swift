import SwiftUI

/// The Attività sidebar and its five views (SPEC §7.4).
struct TasksView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @State private var view: NoteIndex.TaskView = .today
    @State private var selectedTaskID: String?
    /// The task waiting for a note to link to (SPEC §7.2, "collegamento assistito").
    @State private var linking: TaskItem?

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
            QuickSwitcher { path in
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
        view = switch capture.deadline {
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

            ForEach(NoteIndex.TaskView.allCases) { item in
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
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                        Text(group.title).themedText(.heading)
                        ForEach(group.tasks) { task in
                            row(task)
                        }
                    }
                }
                if groups.isEmpty {
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

    private struct Group {
        var title: String
        var tasks: [TaskItem]
    }

    /// Groups the current view's tasks the way that view reads best: overdue first in
    /// Oggi, by day in Prossimi, by project in Per progetto, by source note otherwise.
    private var groups: [Group] {
        let tasks = vault.index.tasks(for: view, on: today)
        guard !tasks.isEmpty else { return [] }

        switch view {
        case .today:
            let late = tasks.filter { $0.isOverdue(on: today) }
            let due = tasks.filter { !$0.isOverdue(on: today) }
            return [Group(title: "In ritardo", tasks: late), Group(title: "Oggi", tasks: due)]
                .filter { !$0.tasks.isEmpty }
        case .upcoming:
            return Dictionary(grouping: tasks) { $0.scheduled?.description ?? "—" }
                .sorted { $0.key < $1.key }
                .map { Group(title: $0.key, tasks: $0.value) }
        case .byProject:
            return Dictionary(grouping: tasks) { $0.project?.description ?? "senza progetto" }
                .sorted { $0.key < $1.key }
                .map { Group(title: $0.key, tasks: $0.value) }
        case .inbox:
            return [Group(title: "Inbox", tasks: tasks)]
        case .all:
            return Dictionary(grouping: tasks) { NoteName.title(fromFileName: ($0.sourcePath as NSString).lastPathComponent) }
                .sorted { $0.key < $1.key }
                .map { Group(title: $0.key, tasks: $0.value) }
        }
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
                    HStack(spacing: theme.spacing(.xs)) {
                        Button {
                            vault.openNote(at: task.sourcePath)
                        } label: {
                            Text("↗ \(NoteName.title(fromFileName: (task.sourcePath as NSString).lastPathComponent))")
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

extension CalendarDate {
    /// The date some whole days later, through the calendar so month ends behave.
    func adding(days: Int) -> CalendarDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let start = DateComponents(
                calendar: calendar, year: year, month: month, day: day
              ).date,
              let moved = calendar.date(byAdding: .day, value: days, to: start)
        else { return self }
        return CalendarDate(moved, in: calendar)
    }
}
