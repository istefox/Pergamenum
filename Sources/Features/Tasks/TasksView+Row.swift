import SwiftUI

/// `TasksView`'s single-task row: its two densities, its context menu, the due-date
/// sheet it opens, and its wikilink navigation (PG-035 — pure code motion off
/// `TasksView.swift`, which had drifted to `file_length`/`type_body_length` warnings,
/// the second of which crossed into an error).
extension TasksView {
    func row(_ task: TaskItem, isRolledOver: Bool = false) -> some View {
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
    func details(_ task: TaskItem) -> some View {
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
    func workspaceSegment(_ task: TaskItem) -> some View {
        switch WorkspaceBoardResolver.resolve(task.workspacePath, in: boards) {
        case .unique(let path):
            Button {
                vault.routeState.pendingCanvas = (path.value, nil)
            } label: {
                Text("▦ \(path.value)").themedText(.caption, color: .accentPrimary)
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
    func contextMenu(_ task: TaskItem) -> some View {
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
    func dueDateSheet(for task: TaskItem) -> some View {
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

    func open(link target: String) {
        // A link ending in .canvas points at a board; anything else is a note.
        if target.lowercased().hasSuffix(".canvas") { return }
        if let path = vault.index.resolve(title: target).first {
            vault.openNote(at: path)
        }
    }
}
