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

    /// Which of the two date chips has its popover open. One at a time, and held as a
    /// value so opening the second closes the first.
    private enum DatePopover: String, Identifiable {
        case deadline, reminder
        var id: String { rawValue }
    }

    private var canCreate: Bool { !draft.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            header
            ComposerTextField(
                text: $draft.text,
                placeholder: "Nuovo task",
                font: theme.nsFont(.body),
                color: NSColor(theme.color(.textPrimary)),
                focusRequest: focusRequest,
                identifier: "task-composer-text",
                onSubmit: create
            )
            .frame(height: theme.spacing(.l))
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

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: theme.spacing(.s)) {
            chip(
                .deadline,
                symbol: "calendar",
                title: "Scadenza",
                value: draft.deadline.map { "\($0)" }
            )
            chip(
                .reminder,
                symbol: "bell",
                title: "Promemoria",
                value: draft.reminder.map { reminder in
                    String(format: "%@ %02d:%02d", reminder.date.description, reminder.hour, reminder.minute)
                }
            )

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
        case .deadline:
            DateChoice(title: "Scadenza", date: $draft.deadline) { open = nil }
        case .reminder:
            ReminderChoice(reminder: $draft.reminder, day: draft.deadline ?? .today) { open = nil }
        }
    }

    private func clear(_ popover: DatePopover) {
        switch popover {
        case .deadline: draft.deadline = nil
        case .reminder: draft.reminder = nil
        }
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

/// A day, with the shortcuts that cover most of the choices (SPEC §7.3).
private struct DateChoice: View {
    @Environment(\.theme) private var theme
    let title: String
    @Binding var date: CalendarDate?
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text(title).themedText(.caption, color: .textTertiary)
            HStack {
                quick("Oggi", days: 0)
                quick("Domani", days: 1)
                quick("Settimana prossima", days: 7)
            }
            DatePicker(
                "",
                selection: Binding(
                    // Midday, through the one conversion the app already has: a date
                    // built at midnight lands on the previous day in some zones.
                    get: { EventKitStore.date(date ?? .today, hour: 12, minute: 0) ?? Date() },
                    set: { date = CalendarDate($0) }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .frame(width: 260)

            HStack {
                Button("Togli") {
                    date = nil
                    onDone()
                }
                Spacer()
                Button("Fatto", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(theme.spacing(.m))
    }

    private func quick(_ label: String, days: Int) -> some View {
        Button(label) {
            date = CalendarDate.today.adding(days: days)
            onDone()
        }
        .buttonStyle(.link)
        .accessibilityIdentifier("date-quick-\(days)")
    }
}

/// A day and a time, which is what `@remind(...)` carries.
private struct ReminderChoice: View {
    @Environment(\.theme) private var theme
    @Binding var reminder: TaskReminder?
    /// The day the reminder starts on: the task's own deadline when it has one, since
    /// a reminder for a task due on Friday is almost never wanted for today.
    let day: CalendarDate
    let onDone: () -> Void

    /// Nine in the morning, which is the hour the Inserisci menu writes too - a
    /// reminder defaulting to "now" fires while you are still typing the task.
    @State private var moment = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text("Promemoria").themedText(.caption, color: .textTertiary)
            DatePicker("", selection: $moment, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(width: 260)
            // The hour as a field rather than in the graphical picker, which draws a
            // clock face you have to aim at to set nine o'clock.
            DatePicker("Ora", selection: $moment, displayedComponents: .hourAndMinute)
                .fixedSize()

            HStack {
                Button("Togli") {
                    reminder = nil
                    onDone()
                }
                Spacer()
                Button("Fatto") {
                    let clock = Calendar.current.dateComponents([.hour, .minute], from: moment)
                    reminder = TaskReminder(
                        date: CalendarDate(moment),
                        hour: clock.hour ?? 9,
                        minute: clock.minute ?? 0
                    )
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(theme.spacing(.m))
        .onAppear {
            moment = if let reminder {
                EventKitStore.date(reminder.date, hour: reminder.hour, minute: reminder.minute) ?? moment
            } else {
                EventKitStore.date(day, hour: 9, minute: 0) ?? moment
            }
        }
    }
}
