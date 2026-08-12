import SwiftUI

/// The day view of SPEC §8.1: references, the daily note itself, and the timeline.
struct TodayView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(EventKitStore.self) private var calendar

    /// Created at app level so the Calendario menu can act on the same day (SPEC §10).
    @Environment(DayController.self) private var controller

    @State private var draftTitle = ""
    @State private var draftStartHour = 9
    @State private var draftDurationMinutes = 60
    @State private var draftDate = CalendarDate.today

    private var day: CalendarDate { controller.day }
    private var blocks: [TimeBlock] { controller.blocks }
    private var events: [CalendarEvent] { controller.events }
    private var reminders: [CalendarReminder] { controller.reminders }

    /// The hours the timeline shows (SPEC §8.3).
    private let firstHour = 6
    private let lastHour = 22
    private let hourHeight: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            noteColumn
            Divider()
            timeline
        }
        .background(theme.color(.backgroundPrimary))
        .task(id: day) { await controller.load() }
        .sheet(isPresented: Bindable(controller).isChoosingDate) { datePicker }
        .sheet(isPresented: Bindable(controller).isCreatingEvent) {
            draftSheet(title: "Nuovo evento", showsTime: true) {
                controller.createEvent(
                    title: draftTitle,
                    startMinutes: draftStartHour * 60,
                    durationMinutes: draftDurationMinutes,
                    calendarTitle: calendar.writeCalendarTitle
                )
            }
        }
        .sheet(isPresented: Bindable(controller).isCreatingReminder) {
            draftSheet(title: "Nuovo promemoria", showsTime: false) {
                controller.createReminder(title: draftTitle)
            }
        }
    }

    // MARK: Note column

    private var noteColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                header
                MiniCalendar(
                    day: day,
                    onSelect: { controller.show($0) },
                    onOpenDailyNote: { date in
                        controller.show(date)
                        controller.openDailyNote()
                    }
                )
                references
                noteBody
            }
            .padding(theme.spacing(.l))
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: theme.spacing(.s)) {
            Text(day.compactForm).themedText(.title)
            Text(longDate).themedText(.body, color: .textSecondary)
            Spacer()
            Button { move(by: -1) } label: { Image(systemName: "chevron.left") }
            Button { controller.show(.today) } label: { Text("Oggi").themedText(.caption) }
            Button { move(by: 1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.color(.textSecondary))
    }

    private var longDate: String {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        guard let date = Calendar.current.date(from: components) else { return "" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "it_IT")))
    }

    /// Tasks scheduled on this day, shown by reference: the task stays in its own note
    /// and this is a pointer to it (SPEC §7.3, "pianificare = link, non copia").
    private var references: some View {
        let scheduled = vault.index.tasks(for: .today, on: day)
        return ThemedCard {
            VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                Text("PIANIFICATI OGGI").themedText(.caption, color: .textTertiary)
                if scheduled.isEmpty {
                    Text("nessun task").themedText(.caption, color: .textTertiary)
                }
                ForEach(scheduled) { task in
                    HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
                        Image(systemName: "square")
                            .foregroundStyle(theme.color(task.isOverdue(on: day) ? .taskOverdue : .taskOpen))
                            .onTapGesture { vault.toggle(task) }
                        Text(task.text).themedText(.body)
                        Button {
                            vault.openNote(at: task.sourcePath)
                        } label: {
                            Text("↗ \(NoteName.title(fromFileName: (task.sourcePath as NSString).lastPathComponent))")
                                .themedText(.caption, color: .textTertiary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button("Blocca") { controller.addBlock(from: task) }
                            .buttonStyle(.plain)
                            .themedText(.caption, color: .accentPrimary)
                            .help("Crea un time block da questo task")
                    }
                }

                if !reminders.isEmpty {
                    Divider()
                    Text("PROMEMORIA").themedText(.caption, color: .textTertiary)
                    ForEach(reminders) { reminder in
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

    @ViewBuilder
    private var noteBody: some View {
        if let note = vault.openNote, note.relativePath.contains(day.compactForm) {
            NoteTextView(
                text: Binding(
                    get: { vault.openNote?.text ?? "" },
                    set: { vault.updateOpenNoteText($0) }
                ),
                theme: theme,
                noteTitles: vault.index.allNotes.map(\.title),
                tagSuggestions: [],
                onFollowLink: { title in
                    if let path = vault.index.resolve(title: title).first { vault.openNote(at: path) }
                }
            )
            .frame(minHeight: 320)
        } else {
            Button("Apri la nota di \(day.compactForm)") { controller.openDailyNote() }
                .buttonStyle(.plain)
                .themedText(.body, color: .accentPrimary)
        }
    }

    // MARK: Timeline

    private var timeline: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(firstHour...lastHour, id: \.self) { hour in
                        HStack(alignment: .top, spacing: theme.spacing(.s)) {
                            Text(String(format: "%02d:00", hour))
                                .themedText(.caption, color: .textTertiary)
                                .frame(width: 44, alignment: .trailing)
                            Rectangle()
                                .fill(theme.color(.borderSubtle))
                                .frame(height: 1)
                        }
                        .frame(height: hourHeight, alignment: .top)
                    }
                }

                ForEach(events) { event in
                    entry(title: event.title, subtitle: event.calendarTitle,
                          start: minutes(from: event.start), duration: duration(of: event),
                          token: .accentMuted, isEvent: true)
                }
                ForEach(blocks) { block in
                    entry(title: block.title, subtitle: block.isPublished ? "pubblicato" : "solo nella nota",
                          start: block.startMinutes, duration: block.durationMinutes,
                          token: .stickyBlue, isEvent: false)
                        .contextMenu {
                            Button(block.isPublished ? "Già pubblicato" : "Pubblica sul Calendario") {
                                controller.publish(block, toCalendarTitled: calendar.writeCalendarTitle)
                            }
                            .disabled(block.isPublished || !calendar.eventAccess.isGranted)
                            Button("Rimuovi") { controller.remove(block) }
                        }
                }
            }
            .padding(.vertical, theme.spacing(.s))
        }
        .frame(width: 300)
        .background(theme.color(.backgroundSecondary))
        .safeAreaInset(edge: .top) { timelineHeader }
    }

    private var timelineHeader: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text("TIMELINE").themedText(.caption, color: .textTertiary)
            Spacer()
            if !calendar.eventAccess.isGranted {
                Button("Consenti Calendario") {
                    Task { await calendar.requestAccess(); await controller.load() }
                }
                .buttonStyle(.plain)
                .themedText(.caption, color: .accentPrimary)
            }
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .background(theme.color(.backgroundSecondary))
    }

    private func entry(
        title: String, subtitle: String, start: Int, duration: Int,
        token: ColorToken, isEvent: Bool
    ) -> some View {
        let offset = CGFloat(start - firstHour * 60) / 60 * hourHeight
        let height = max(18, CGFloat(duration) / 60 * hourHeight)

        return VStack(alignment: .leading, spacing: 0) {
            Text(title).themedText(.caption).lineLimit(1)
            if height > 30 {
                Text(subtitle).themedText(.caption, color: .textTertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, theme.spacing(.xs))
        .padding(.vertical, 2)
        .frame(width: 236, height: height, alignment: .topLeading)
        .background(theme.color(token))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .overlay(alignment: .leading) {
            // Events from the calendar and blocks from the note are distinguishable at
            // a glance: only one of them is something this app owns.
            Rectangle()
                .fill(theme.color(isEvent ? .accentPrimary : .taskScheduled))
                .frame(width: 2)
        }
        .offset(x: 52, y: offset)
    }

    private func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func duration(of event: CalendarEvent) -> Int {
        max(15, Int(event.end.timeIntervalSince(event.start) / 60))
    }

    // MARK: Actions

    private func move(by days: Int) {
        controller.move(by: days)
    }

    /// "Vai a data…" from the Calendario menu.
    private var datePicker: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Vai a data").themedText(.title)
            DatePicker(
                "Giorno",
                selection: Binding(
                    get: { EventKitStore.date(draftDate, hour: 12, minute: 0) ?? Date() },
                    set: { draftDate = CalendarDate($0) }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)

            HStack {
                Spacer()
                Button("Annulla") { controller.isChoosingDate = false }
                    .keyboardShortcut(.cancelAction)
                Button("Vai") {
                    controller.show(draftDate)
                    controller.isChoosingDate = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(theme.spacing(.l))
        .background(theme.color(.surfaceCard))
    }

    /// The sheet behind "Nuovo evento" and "Nuovo promemoria".
    private func draftSheet(
        title: String,
        showsTime: Bool,
        confirm: @escaping () -> Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(title).themedText(.title)
            Text("Sul giorno mostrato: \(day.description)")
                .themedText(.caption, color: .textSecondary)
            TextField("Titolo", text: $draftTitle)
                .textFieldStyle(.roundedBorder)

            if showsTime {
                HStack(spacing: theme.spacing(.m)) {
                    Picker("Ora", selection: $draftStartHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    Picker("Durata", selection: $draftDurationMinutes) {
                        ForEach([15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Annulla") { dismissDraft() }
                    .keyboardShortcut(.cancelAction)
                Button("Crea") {
                    _ = confirm()
                    dismissDraft()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 460)
        .background(theme.color(.surfaceCard))
    }

    private func dismissDraft() {
        draftTitle = ""
        controller.isCreatingEvent = false
        controller.isCreatingReminder = false
    }
}
