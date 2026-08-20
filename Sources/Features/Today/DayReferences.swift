import SwiftUI

/// The reference area of the day view (SPEC §8.1): what is planned for the day, what
/// falls due soon, the Apple reminders, and the blocks the day is cut into.
///
/// Its own type rather than four properties on `TodayView`, which is already the
/// largest view in the app: the day's lists are one subject and they move together.
struct DayReferences: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    let controller: DayController

    private var day: CalendarDate { controller.day }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            planned
            if controller.showsDueTasks { upcomingDue }
            if !controller.blocks.isEmpty { blocks }
        }
    }

    // MARK: Planned

    /// Tasks scheduled on this day, shown by reference: the task stays in its own note
    /// and this is a pointer to it (SPEC §7.3, "pianificare = link, non copia").
    private var planned: some View {
        let scheduled = vault.index.tasks(
            for: .today, on: day, includingCompleted: controller.showsCompleted
        )
        return ThemedCard {
            VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                Text("PIANIFICATI OGGI").themedText(.caption, color: .textTertiary)
                if scheduled.isEmpty {
                    Text("nessun task").themedText(.caption, color: .textTertiary)
                }
                ForEach(scheduled) { task in
                    taskRow(task)
                }

                if !controller.reminders.isEmpty {
                    Divider()
                    Text("PROMEMORIA").themedText(.caption, color: .textTertiary)
                    ForEach(controller.reminders) { reminder in
                        HStack(spacing: theme.spacing(.xs)) {
                            Image(systemName: reminder.isCompleted ? "checkmark.square" : "square")
                                .foregroundStyle(theme.color(.taskOpen))
                                .onTapGesture { controller.toggle(reminder) }
                            Text(reminder.title).themedText(.body)
                            Text(reminder.listTitle).themedText(.caption, color: .textTertiary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Draggable onto an hour of the timeline beside it (ADR-0013 §D5), which is the
    /// only reason this list and that grid are on screen together.
    ///
    /// Every row here is a task with a `>` marker - the list is built from
    /// `tasks(for: .today, on:)` - so there is no kind to refuse, unlike the week's
    /// rows. The deadlines below have their own list and stay where they are: a drag
    /// rewrites `>`, and they are on the day because of `!`.
    private func taskRow(_ task: TaskItem) -> some View {
        let row = HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
            Image(systemName: task.state == .done ? "checkmark.square" : "square")
                .foregroundStyle(theme.color(task.isOverdue(on: day) ? .taskOverdue : .taskOpen))
                .onTapGesture { vault.toggle(task) }
            Text(task.text)
                .themedText(.body, color: task.state == .done ? .taskDone : .textPrimary)
            if let time = task.scheduledTime ?? task.dueTime {
                Text(time.text).themedText(.mono, color: .textTertiary)
            }
            Button {
                vault.openNote(at: task.sourcePath)
            } label: {
                Text("↗ \(NoteName.title(fromFileName: (task.sourcePath as NSString).lastPathComponent))")
                    .themedText(.caption, color: .textTertiary)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        return row
            .draggable(TaskDragPayload(path: task.sourcePath, lineIndex: task.lineIndex).text)
            .contextMenu { blockMenuItem(for: task) }
    }

    /// What «Inserisci Blocco Tempo» was, in the menu instead of on the row.
    ///
    /// The button took a third of the row's width from the thing the row is about, and
    /// since §D5 the ordinary way to block out a task is to drag it onto the hour you
    /// mean. It stays here because a gesture is not an affordance: a drag is invisible
    /// until somebody tries it, and this is the entry that says the feature exists.
    private func blockMenuItem(for task: TaskItem) -> some View {
        Button("Inserisci Blocco Tempo") { controller.addBlock(from: task) }
            .help("Mette il task sulla timeline del giorno, \(vault.settings.blockMinutes) minuti")
            .accessibilityIdentifier("insert-time-block")
    }

    // MARK: Due

    /// What falls due from this day on, which is what the bell in the toolbar shows.
    private var upcomingDue: some View {
        let due = vault.index.dueTasks(from: day)
        return ThemedCard {
            VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                Text("SCADENZE IN ARRIVO").themedText(.caption, color: .textTertiary)
                if due.isEmpty {
                    Text("nessuna scadenza nei prossimi 30 giorni")
                        .themedText(.caption, color: .textTertiary)
                }
                ForEach(due) { task in
                    HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
                        Image(systemName: "flag")
                            .foregroundStyle(theme.color(task.isOverdue(on: day) ? .taskOverdue : .taskScheduled))
                        Text(task.text).themedText(.body)
                        Spacer()
                        Text(dueText(task))
                            .themedText(.mono, color: task.isOverdue(on: day) ? .taskOverdue : .textSecondary)
                        Button {
                            controller.show(task.due ?? day)
                        } label: {
                            Image(systemName: "arrow.right.circle")
                                .foregroundStyle(theme.color(.accentPrimary))
                        }
                        .buttonStyle(.plain)
                        .help("Vai al giorno della scadenza")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // `.contain` alongside the identifier: naming a container without it promotes
        // the card to one element and hides every control inside it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("due-tasks-card")
    }

    private func dueText(_ task: TaskItem) -> String {
        guard let due = task.due else { return "" }
        return due.italianForm + (task.dueTime.map { " \($0.text)" } ?? "")
    }

    // MARK: Blocks

    /// The day's blocks, each removable here as well as from the timeline: the section
    /// they live in is markdown, and deleting a line of markdown by hand to undo a
    /// click is not an undo.
    private var blocks: some View {
        ThemedCard {
            VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                Text("BLOCCHI TEMPO").themedText(.caption, color: .textTertiary)
                ForEach(controller.blocks) { block in
                    HStack(spacing: theme.spacing(.xs)) {
                        Text("\(block.startText)–\(block.endText)")
                            .themedText(.mono, color: .textSecondary)
                        Text(block.title).themedText(.body)
                        if block.isPublished {
                            Image(systemName: "calendar")
                                .foregroundStyle(theme.color(.textTertiary))
                                .help("Pubblicato sul Calendario")
                        }
                        Spacer()
                        Button {
                            controller.remove(block)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(theme.color(.textTertiary))
                        }
                        .buttonStyle(.plain)
                        .help("Elimina il blocco")
                        .accessibilityIdentifier("remove-block")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blocks-card")
    }
}
