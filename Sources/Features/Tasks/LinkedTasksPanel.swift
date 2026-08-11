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
                    row(task)
                }
            }
        }
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
            Image(systemName: task.state == .done ? "checkmark.square" : "square")
                .foregroundStyle(theme.color(
                    task.isOverdue(on: .today) ? .taskOverdue : (task.state == .done ? .taskDone : .taskOpen)
                ))
                .onTapGesture { vault.toggle(task) }
                .help("Completa o riapri: scrive nella nota di origine")

            VStack(alignment: .leading, spacing: 1) {
                Text(task.text)
                    .themedText(.caption, color: task.state == .done ? .taskDone : .textPrimary)
                    .lineLimit(2)
                Button {
                    vault.openNote(at: task.sourcePath)
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
                Text(verbatim: "!\(due)").themedText(.caption, color: .taskOverdue)
            } else if let scheduled = task.scheduled {
                Text(verbatim: ">\(scheduled)").themedText(.caption, color: .taskScheduled)
            }
        }
        .contextMenu {
            Button(task.state == .done ? "Riapri" : "Completa") { vault.toggle(task) }
            Button("Pianifica oggi") { vault.apply(.schedule(.today), to: task) }
            Button("Domani") { vault.apply(.schedule(CalendarDate.today.adding(days: 1)), to: task) }
            Divider()
            Button("Vai alla nota di origine") { vault.openNote(at: task.sourcePath) }
        }
    }
}
