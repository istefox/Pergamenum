import SwiftUI

/// The "Task collegati" panel of SPEC §7.2.
///
/// Lists every task in the vault whose text links to a note or a board, with its
/// state and dates, completable where it is shown. Completing here rewrites the file
/// the task lives in, never a copy: a task exists in exactly one place, and the panel
/// is a view of it.
///
/// One view used by both the editor inspector and the Workspace, because §7.2 asks
/// for the same panel in both and two implementations would drift.
struct LinkedTasksPanel: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    /// The exact title a task must link to. For a board this is the `.canvas` file
    /// name, which is how a wikilink names it.
    let title: String
    /// Shown when nothing links here yet.
    var emptyText = "nessuno"

    var body: some View {
        let tasks = vault.index.tasks(linkingTo: title)
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(spacing: theme.spacing(.xs)) {
                Text("TASK COLLEGATI").themedText(.caption, color: .textTertiary)
                if !tasks.isEmpty {
                    Text("\(tasks.filter { $0.state != .done }.count)/\(tasks.count)")
                        .themedText(.caption, color: .textTertiary)
                }
            }

            if tasks.isEmpty {
                Text(emptyText).themedText(.caption, color: .textTertiary)
            } else {
                ForEach(tasks) { task in
                    TaskPanelRow(task: task, identifierPrefix: "linked-task")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Task collegati a \(title)")
    }
}

/// One task as a side panel draws it: a checkbox that completes it in place, its text,
/// the note it lives in, and its `!`/`>` date.
///
/// Its own view rather than a method on `LinkedTasksPanel`, because the board's "Task
/// assegnati" section (ADR-0021 §D7) draws the same row from a different query, and two
/// copies of a row are two rows that drift. The header above makes that argument about
/// the panel; this makes it true one level down.
struct TaskPanelRow: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(CommandActions.self) private var actions

    let task: TaskItem
    /// Distinguishes the sections a row can appear in, so a UI test names the one it
    /// means. `CLAUDE.md`: a UI test must never find a control by the words on it.
    let identifierPrefix: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
            Image(systemName: task.state == .done ? "checkmark.square" : "square")
                .foregroundStyle(theme.color(
                    task.isOverdue(on: .today) ? .taskOverdue : (task.state == .done ? .taskDone : .taskOpen)
                ))
                .onTapGesture { Task { await vault.toggle(task) } }
                .help("Completa o riapri: scrive nella nota di origine")

            VStack(alignment: .leading, spacing: 1) {
                Text(task.text)
                    .themedText(.caption, color: task.state == .done ? .taskDone : .textPrimary)
                    .lineLimit(2)
                Button {
                    actions.run(.goToNote, on: task)
                } label: {
                    Text(NoteName.title(fromFileName: (task.sourcePath as NSString).lastPathComponent))
                        .themedText(.caption, color: .textTertiary)
                }
                .buttonStyle(.plain)
                .help(task.sourcePath)
            }

            Spacer(minLength: 0)

            if let due = task.due {
                // `verbatim`: a plain interpolation here goes through LocalizedStringKey,
                // which renders a date as its debug description.
                Text(verbatim: "!\(due.italianForm)").themedText(.caption, color: .taskOverdue)
            } else if let scheduled = task.scheduled {
                Text(verbatim: ">\(scheduled.italianForm)").themedText(.caption, color: .taskScheduled)
            }
        }
        .contextMenu {
            Button(task.state == .done ? "Riapri" : "Completa") { Task { await vault.toggle(task) } }
            Button("Pianifica oggi") { Task { await vault.apply(.schedule(.today), to: task) } }
            Button("Domani") {
                Task { await vault.apply(.schedule(CalendarDate.today.adding(days: 1)), to: task) }
            }
            Divider()
            ForEach(TaskCommand.available(for: task), id: \.self) { command in
                Button(command.title) { actions.run(command, on: task) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(task.state == .done ? "Completato" : "Da fare"): \(task.text)")
        .accessibilityIdentifier("\(identifierPrefix)-\(task.id)")
    }
}
