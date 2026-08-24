import SwiftUI

/// Cattura rapida (SPEC §7.4), in the shape Craft gives it: destination on top, the
/// text in the middle, the dates and the create button along the bottom.
///
/// One panel rather than a form, because capture competes with not capturing at all:
/// everything past the text is optional and one click away, and Enter alone files the
/// task in the inbox with no date, which is what quick capture means.
struct TaskComposer: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation

    let onClose: () -> Void

    @State private var draft = VaultController.TaskDraft()
    @State private var isChoosingDestination = false
    @State private var open: DatePopover?
    /// Bumped to put the caret back in the text after a popover or a menu took focus.
    @State private var focusRequest = 0

    /// Which of the two date chips has its panel open. One at a time, and held as a
    /// value so opening the second closes the first.
    private enum DatePopover: String, Identifiable {
        /// `>`: the day the task shows up on, with the quick choices and the reminder.
        case scheduled
        /// `!`: the day past which it is late, a calendar and nothing else.
        case due
        var id: String { rawValue }
    }

    private var canCreate: Bool { !draft.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            header
            parentRow
            ComposerTextField(
                text: $draft.text,
                placeholder: draft.parent == nil ? "Nuovo task" : "Nuovo sotto-task",
                font: theme.nsFont(.body),
                color: NSColor(theme.color(.textPrimary)),
                focusRequest: focusRequest,
                identifier: "task-composer-text",
                onSubmit: create
            )
            .frame(height: theme.spacing(.l))
            blockRow
            footer
        }
        .padding(theme.spacing(.m))
        .frame(width: 520)
        .background(theme.color(.surfaceCard))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        .onAppear {
            // The controller carries the destination the command chose, so "Nuovo task
            // in questa nota" opens the composer already pointed at it.
            if let pending = vault.taskDraft { draft = pending }
            focusRequest += 1
        }
        // Back to the text whenever a popover closes: the caret goes to the end of
        // what was already typed, not over it.
        .onChange(of: open) { _, now in
            if now == nil { focusRequest += 1 }
        }
        .onChange(of: isChoosingDestination) { _, now in
            if !now { focusRequest += 1 }
        }
        .onExitCommand(perform: onClose)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Button { isChoosingDestination = true } label: {
                HStack(spacing: theme.spacing(.xs)) {
                    Image(systemName: destinationSymbol)
                    Text(destinationTitle).themedText(.body)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .foregroundStyle(theme.color(.textPrimary))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("task-composer-destination")
            .help("Scegli la nota in cui scrivere il task")
            // A sub-task has no destination to choose: `^id` is note-local (ADR-0021
            // D2), so it goes in the parent's own note and nowhere else. Shown greyed
            // rather than hidden, so the panel does not change shape between the two
            // ways of reaching it.
            .disabled(draft.parent != nil)
            .popover(isPresented: $isChoosingDestination, arrowEdge: .bottom) {
                DestinationPicker(destination: $draft.destination) { isChoosingDestination = false }
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.color(.textTertiary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chiudi")
            .help("Chiudi senza creare")
        }
    }

    private var destinationTitle: String {
        switch draft.destination {
        case .inbox: "Inbox"
        case .note(let path): NoteName.title(fromFileName: (path as NSString).lastPathComponent)
        }
    }

    private var destinationSymbol: String {
        draft.destination == .inbox ? "tray" : "doc.text"
    }

    // MARK: Parent

    /// Which task this one becomes a child of (ADR-0021 D9, A9), drawn only when the
    /// composer was opened by «Aggiungi sotto-task».
    ///
    /// Read-only on purpose: the parent is chosen by selecting a task before running the
    /// command, and a second way to change it here would be a second selection to keep
    /// in step with the list's.
    @ViewBuilder
    private var parentRow: some View {
        if let parent = draft.parent {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(theme.color(.textTertiary))
                Text("Sotto-task di")
                    .themedText(.caption, color: .textTertiary)
                Text(parent.text)
                    .themedText(.caption, color: .textSecondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Sotto-task di \(parent.text)")
            .accessibilityIdentifier("task-composer-parent")
        }
    }

    // MARK: Timeline

    /// Asked rather than assumed: a task with an hour can also be a block on that day's
    /// timeline, and whether the day gets planned that way is the user's call. Shown
    /// only once there is an hour, since a block with no time has nowhere to go.
    @ViewBuilder
    private var blockRow: some View {
        if let slot = draft.blockSlot {
            Toggle(isOn: $draft.blocksTheDay) {
                Text("Mettilo anche nell'orario del giorno, alle \(slot.time.text)")
                    .themedText(.caption, color: .textSecondary)
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("task-composer-block")
            .help("Crea un blocco tempo nella nota del \(slot.day.italianForm)")
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: theme.spacing(.s)) {
            chip(
                .scheduled,
                symbol: "calendar",
                title: "Programma",
                value: value(draft.scheduled, draft.scheduledTime)
            )
            chip(
                .due,
                symbol: "flag",
                title: "Scadenza",
                value: value(draft.due, draft.dueTime)
            )
            // The reminder is set inside the Programma panel, where Craft keeps it, so
            // it shows here only once there is one to show.
            if let reminder = draft.reminder {
                Label(
                    String(format: "%02d:%02d", reminder.hour, reminder.minute),
                    systemImage: "alarm"
                )
                .themedText(.caption, color: .textSecondary)
                .accessibilityIdentifier("task-composer-reminder-badge")
            }
            if let recurrence = draft.recurrence {
                Label("\(recurrence.total)×", systemImage: "arrow.triangle.2.circlepath")
                    .themedText(.caption, color: .textSecondary)
                    .accessibilityIdentifier("task-composer-repeat-badge")
            }

            Spacer()

            // Split button: the click creates, the chevron offers the variant that
            // opens the note the task landed in.
            HStack(spacing: 0) {
                Button(action: create) {
                    Text("Crea")
                        .themedText(.body, color: canCreate ? .textInverted : .textTertiary)
                        .padding(.horizontal, theme.spacing(.m))
                        .padding(.vertical, theme.spacing(.xs))
                }
                .buttonStyle(.plain)
                // Also on Enter from anywhere in the panel, not only from the text
                // field: the date popovers take focus and give it back.
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
                .accessibilityIdentifier("task-composer-create")

                Menu {
                    Button("Crea e apri la nota") { create(opening: true) }
                    Button("Crea e continua") { create(keepingOpen: true) }
                } label: {
                    Image(systemName: "chevron.down")
                        .foregroundStyle(theme.color(canCreate ? .textInverted : .textTertiary))
                        .padding(.trailing, theme.spacing(.s))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(!canCreate)
                .accessibilityLabel("Altre opzioni di creazione")
            }
            // Muted rather than a faded accent: an accent-coloured button that does
            // nothing when clicked is worse than one that plainly looks unavailable.
            .background(theme.color(canCreate ? .accentPrimary : .surfaceRaised))
            .clipShape(Capsule())
        }
    }

    /// What a chip reads once it has a date: `20/08/2026`, and the hour when there is
    /// one. Italian, like the day view's header - the ISO form belongs in the file.
    private func value(_ date: CalendarDate?, _ time: TaskTime?) -> String? {
        guard let date else { return nil }
        return date.italianForm + (time.map { " \($0.text)" } ?? "")
    }

    /// One date chip: label alone when unset, value plus a clear button when set.
    private func chip(_ popover: DatePopover, symbol: String, title: String, value: String?) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Button {
                open = popover
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                    Text(value ?? title)
                        .themedText(.caption, color: value == nil ? .textTertiary : .textPrimary)
                }
                .foregroundStyle(theme.color(value == nil ? .textTertiary : .accentPrimary))
            }
            .buttonStyle(.plain)
            .help(title)
            .accessibilityIdentifier("task-composer-\(popover.rawValue)")

            if value != nil {
                Button {
                    clear(popover)
                } label: {
                    Image(systemName: "xmark").font(.caption2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Togli \(title.lowercased())")
            }
        }
        .padding(.horizontal, theme.spacing(.xs))
        .padding(.vertical, 2)
        .background(value == nil ? Color.clear : theme.color(.accentMuted))
        .clipShape(Capsule())
        // One popover per chip, bound to whether this chip is the open one. Bound to
        // the shared value with `.popover(item:)` all three would try to present at
        // once, and the one that won was not the one clicked.
        .popover(
            isPresented: Binding(
                get: { open == popover },
                set: { if !$0, open == popover { open = nil } }
            ),
            arrowEdge: .top
        ) {
            popoverContent(for: popover)
        }
    }

    @ViewBuilder
    private func popoverContent(for popover: DatePopover) -> some View {
        switch popover {
        case .scheduled:
            SchedulePanel(
                date: $draft.scheduled,
                time: $draft.scheduledTime,
                reminder: $draft.reminder,
                recurrence: $draft.recurrence
            ) { open = nil }
        case .due:
            DuePanel(date: $draft.due, time: $draft.dueTime) { open = nil }
        }
    }

    private func clear(_ popover: DatePopover) {
        switch popover {
        case .scheduled:
            draft.scheduled = nil
            draft.scheduledTime = nil
            // The reminder hangs off the day the task shows up on; left behind it would
            // fire for a task with no date at all.
            draft.reminder = nil
        case .due:
            draft.due = nil
            draft.dueTime = nil
        }
        // Nothing left to block out: the checkbox is gone from the panel, and leaving
        // it set would plan a day the task no longer has.
        if draft.blockSlot == nil { draft.blocksTheDay = false }
    }

    // MARK: Creating

    private func create() { create(opening: false) }

    private func create(opening: Bool = false, keepingOpen: Bool = false) {
        guard canCreate, vault.captureTask(draft) else { return }
        if opening {
            // The pane too, or the note opens behind whatever section is showing and
            // "apri la nota" appears to have done nothing.
            navigation.pane = .notes
            vault.openNote(at: draft.destination.relativePath)
        }

        if keepingOpen {
            // Same destination and same dates, empty text: capturing a list of tasks is
            // the case where reopening the composer three times is the friction.
            draft.text = ""
            focusRequest += 1
        } else {
            onClose()
        }
    }
}

/// Picks the note a task is written into, searching by title the way the quick
/// switcher does.
private struct DestinationPicker: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Binding var destination: VaultController.TaskDestination
    let onPick: () -> Void

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Cerca una nota…", text: $query)
                .textFieldStyle(.plain)
                .padding(theme.spacing(.s))
                .accessibilityIdentifier("task-composer-destination-search")
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    row(title: "Inbox", subtitle: VaultController.TaskDestination.inboxPath, symbol: "tray") {
                        destination = .inbox
                    }
                    ForEach(results, id: \.relativePath) { note in
                        row(title: note.title, subtitle: note.folder, symbol: "doc.text") {
                            destination = .note(note.relativePath)
                        }
                    }
                }
            }
            .frame(height: 260)
        }
        .frame(width: 360)
    }

    private var results: [NoteRecord] {
        vault.index.search(query, limit: 40)
    }

    private func row(title: String, subtitle: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            onPick()
        } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: symbol).foregroundStyle(theme.color(.textTertiary))
                Text(title).themedText(.body).lineLimit(1)
                Spacer()
                Text(subtitle).themedText(.caption, color: .textTertiary).lineLimit(1)
            }
            .padding(.horizontal, theme.spacing(.s))
            .padding(.vertical, theme.spacing(.xs))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
