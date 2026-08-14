import SwiftUI

/// Programma: the day the task shows up on (`>` of SPEC §7.1).
///
/// A list rather than a calendar, because the day wanted at capture time is nearly
/// always one of a handful - today, tomorrow, next week - and paging a calendar to find
/// it is work. The calendar is one row away for the rest, and the field takes a date
/// typed straight in.
struct SchedulePanel: View {
    @Environment(\.theme) private var theme

    @Binding var date: CalendarDate?
    @Binding var time: TaskTime?
    @Binding var reminder: TaskReminder?
    @Binding var recurrence: TaskRecurrence?
    let onDone: () -> Void

    /// What the panel is showing. One popover with pages, rather than a popover opening
    /// another one, which on macOS closes the first.
    private enum Page { case options, calendar, reminder, repetition }

    @State private var page = Page.options
    @State private var query = ""
    @State private var hovered: String?

    private var today: CalendarDate { .today }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch page {
            case .options:
                field(placeholder: "Data", onSubmit: pickFirst)
                Divider()
                options
                Divider()
                extras
            case .calendar:
                field(placeholder: "Data", onSubmit: pickFirst)
                Divider()
                MonthCalendar(selection: $date, today: today) { _ in onDone() }
                    .padding(theme.spacing(.s))
            case .reminder:
                ReminderPage(reminder: $reminder, day: date ?? today) { page = .options }
            case .repetition:
                repetitionPage
            }
        }
        .frame(width: 340)
    }

    // MARK: Field

    private func field(placeholder: String, onSubmit: @escaping () -> Void) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.color(.textTertiary))
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(theme.font(.body))
                .accessibilityIdentifier("date-panel-field")
                .onSubmit(onSubmit)
        }
        .padding(theme.spacing(.s))
    }

    // MARK: Rows

    private var options: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let typed {
                row(id: "typed", title: DateEntry.hint(for: typed), hint: "\(typed)") { pick(typed) }
            }
            ForEach(matches) { option in
                row(id: option.id, title: option.title, hint: DateEntry.hint(for: option.date)) {
                    pick(option.date)
                }
            }
            row(id: "choose", title: "Seleziona data…", hint: nil) { page = .calendar }
            if date != nil {
                row(id: "clear", title: "Togli la data", hint: nil, action: clearDate)
            }
        }
        .padding(.vertical, theme.spacing(.xs))
    }

    private var extras: some View {
        VStack(alignment: .leading, spacing: 0) {
            TaskTimeRow(time: $time, isEnabled: date != nil)

            row(
                id: "remind",
                symbol: "alarm",
                title: "Ricordami…",
                hint: reminder.map { String(format: "%@ %02d:%02d", DateEntry.hint(for: $0.date), $0.hour, $0.minute) },
                trailing: reminder == nil ? "plus" : nil
            ) { page = .reminder }

            // A finite recurrence is `@repeat(n/N)` (SPEC §7.1); anything endless is
            // Apple Reminders' job (SPEC §14), so the choices stop at a count.
            row(
                id: "repeat",
                symbol: "arrow.triangle.2.circlepath",
                title: "Ripeti…",
                hint: recurrence.map { "\($0.total) volte" },
                trailing: "chevron.right"
            ) { page = .repetition }
        }
        .padding(.vertical, theme.spacing(.xs))
    }

    /// How many times a task comes back, as `@repeat(0/N)`.
    private var repetitionPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: theme.spacing(.xs)) {
                Button { page = .options } label: {
                    Image(systemName: "chevron.left").foregroundStyle(theme.color(.textSecondary))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("repeat-back")
                Text("Ripeti").themedText(.heading)
            }
            .padding(theme.spacing(.s))

            Divider()

            ForEach([2, 3, 5, 10], id: \.self) { total in
                row(id: "repeat-\(total)", title: "\(total) volte", hint: nil) {
                    recurrence = TaskRecurrence(completed: 0, total: total)
                    page = .options
                }
            }
            if recurrence != nil {
                row(id: "repeat-none", title: "Nessuna ripetizione", hint: nil) {
                    recurrence = nil
                    page = .options
                }
            }
        }
        .padding(.bottom, theme.spacing(.xs))
    }

    private func row(
        id: String,
        symbol: String? = nil,
        title: String,
        hint: String?,
        trailing: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            rowLabel(symbol: symbol, title: title, hint: hint, trailing: trailing)
                .background(hovered == id ? theme.color(.accentMuted) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("date-option-\(id)")
        .onHover { hovered = $0 ? id : (hovered == id ? nil : hovered) }
    }

    private func rowLabel(symbol: String?, title: String, hint: String?, trailing: String?) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(theme.color(.textTertiary))
            }
            Text(title).themedText(.body).lineLimit(1)
            Spacer(minLength: theme.spacing(.s))
            if let hint {
                Text(hint).themedText(.caption, color: .textTertiary).lineLimit(1)
            }
            if let trailing {
                Image(systemName: trailing).font(.caption2).foregroundStyle(theme.color(.textTertiary))
            }
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.s))
        .contentShape(Rectangle())
    }

    // MARK: Choosing

    /// The date typed into the field, when it reads as one.
    private var typed: CalendarDate? {
        DateEntry.parse(query, today: today)
    }

    private var matches: [DateEntry.Option] {
        let all = DateEntry.options(from: today)
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty, typed == nil else { return typed == nil ? all : [] }
        return all.filter { $0.title.lowercased().contains(needle) }
    }

    private func pick(_ day: CalendarDate) {
        date = day
        onDone()
    }

    /// Clearing the day clears the hour with it: `>` carries both, and an hour with no
    /// day is written nowhere.
    private func clearDate() {
        date = nil
        time = nil
        onDone()
    }

    private func pickFirst() {
        if let typed {
            pick(typed)
        } else if let first = matches.first {
            pick(first.date)
        }
    }
}

/// Scadenza: the day past which the task is late (`!` of SPEC §7.1).
///
/// A calendar and nothing else, because a deadline is a particular day someone already
/// has in mind - there is no "next week" about it.
struct DuePanel: View {
    @Environment(\.theme) private var theme

    @Binding var date: CalendarDate?
    @Binding var time: TaskTime?
    let onDone: () -> Void

    @State private var query = ""

    private var today: CalendarDate { .today }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.color(.textTertiary))
                TextField("Scadenza", text: $query)
                    .textFieldStyle(.plain)
                    .font(theme.font(.body))
                    .accessibilityIdentifier("due-panel-field")
                    .onSubmit {
                        guard let typed = DateEntry.parse(query, today: today) else { return }
                        date = typed
                        onDone()
                    }
                    .onChange(of: query) { _, now in
                        // Typing moves the calendar as you go, so what you typed is
                        // visible before you commit to it.
                        if let typed = DateEntry.parse(now, today: today) { date = typed }
                    }
            }
            .padding(theme.spacing(.s))

            Divider()

            // Picking a day still closes the panel, as it did before and as the
            // Programma panel does: a day is a decision. The hour is set by clicking
            // the chip again - it then reopens on that day with the Orario row live.
            MonthCalendar(selection: $date, today: today) { _ in onDone() }
                .padding(theme.spacing(.s))

            Divider()
            TaskTimeRow(time: $time, isEnabled: date != nil)

            Divider()
            HStack {
                if date != nil {
                    Button("Togli la scadenza") {
                        date = nil
                        time = nil
                        onDone()
                    }
                    .buttonStyle(.plain)
                    .themedText(.caption, color: .accentPrimary)
                    .accessibilityIdentifier("due-panel-clear")
                }
                Spacer()
                Button("Fatto", action: onDone)
                    .buttonStyle(.plain)
                    .themedText(.caption, color: .accentPrimary)
                    .accessibilityIdentifier("due-panel-done")
            }
            .padding(theme.spacing(.s))
        }
        .frame(width: 340)
    }
}

/// The reminder page of the Programma panel: the day, the hour, and nothing else.
private struct ReminderPage: View {
    @Environment(\.theme) private var theme

    @Binding var reminder: TaskReminder?
    let day: CalendarDate
    let onBack: () -> Void

    @State private var selection: CalendarDate?
    @State private var moment = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            HStack(spacing: theme.spacing(.xs)) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").foregroundStyle(theme.color(.textSecondary))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reminder-back")
                Text("Ricordami").themedText(.heading)
            }

            MonthCalendar(selection: $selection, today: .today)

            DatePicker("Ora", selection: $moment, displayedComponents: .hourAndMinute)
                .fixedSize()

            HStack {
                Button("Togli") {
                    reminder = nil
                    onBack()
                }
                Spacer()
                Button("Fatto") {
                    let clock = Calendar.current.dateComponents([.hour, .minute], from: moment)
                    reminder = TaskReminder(
                        date: selection ?? day,
                        hour: clock.hour ?? 9,
                        minute: clock.minute ?? 0
                    )
                    onBack()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("reminder-done")
            }
        }
        .padding(theme.spacing(.s))
        .onAppear {
            selection = reminder?.date ?? day
            // Nine in the morning, the hour the Inserisci menu writes too: a reminder
            // defaulting to "now" fires while you are still typing the task.
            moment = EventKitStore.date(
                reminder?.date ?? day, hour: reminder?.hour ?? 9, minute: reminder?.minute ?? 0
            ) ?? moment
        }
    }
}
