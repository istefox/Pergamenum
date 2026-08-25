import SwiftUI

/// The day view of SPEC §8.1: references, the daily note itself, and the timeline.
struct TodayView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(EventKitStore.self) private var calendar

    /// Created at app level so the Calendario menu can act on the same day (SPEC §10).
    @Environment(DayController.self) private var controller

    /// The note column's width, handed to the month so it tracks the divider.
    @State private var columnWidth: CGFloat = 0

    /// The scale the view was left on, remembered like the tabs and the panels are.
    /// The anchor is not: a day view that opened on last Tuesday would be a day view
    /// that has to be told it is today.
    @AppStorage("todayScale") private var storedScale = DayScale.day.rawValue

    @State private var draftTitle = ""
    @State private var draftStartHour = 9
    @State private var draftDurationMinutes = 60

    private var day: CalendarDate { controller.day }

    var body: some View {
        scale
        .safeAreaInset(edge: .top) {
            if let drop = controller.lastDrop { dropBanner(drop) }
        }
        .background(theme.color(.backgroundPrimary))
        .onAppear { controller.scale = DayScale(rawValue: storedScale) ?? .day }
        .onChange(of: controller.scale) { _, newScale in storedScale = newScale.rawValue }
        .toolbar { DayToolbar(controller: controller, calendar: calendar, vault: vault) }
        .task(id: day) { await controller.load() }
        // Reloads when EventKit says the store moved, or when the app comes back to
        // the front having been granted access in the meantime. Without this the
        // permission the user has just given stays invisible until the next launch.
        .task(id: calendar.changeCount) {
            guard calendar.changeCount > 0 else { return }
            await controller.load()
        }
        // A task captured from the day view can land on this very day, and the block it
        // may have created lands in this note: reread rather than leave the day showing
        // what it held a moment ago.
        .onChange(of: vault.taskGeneration) { _, _ in controller.reload() }
        .sheet(isPresented: Bindable(controller).isChoosingDate) {
            GoToDateSheet(
                day: day,
                onGo: { controller.show($0) },
                onCancel: { controller.isChoosingDate = false }
            )
        }
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

    /// What the last drag wrote, and the way back (ADR-0013 §D5).
    ///
    /// At the top of the view rather than inside one scale, because the same drag is
    /// made in the week, in the month and on the timeline, and three banners saying the
    /// same thing in three places would be three things to dismiss.
    private func dropBanner(_ drop: DayController.Drop) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: drop.isRefusal ? "exclamationmark.triangle" : "checkmark")
                .themedText(.caption, color: drop.isRefusal ? .taskOverdue : .textTertiary)
            Text(drop.summary)
                .themedText(.caption, color: drop.isRefusal ? .taskOverdue : .textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if drop.journalID != nil {
                Button("Annulla") { controller.undoLastDrop() }
                    .accessibilityIdentifier("undo-task-drop")
            }
            Button("Chiudi") { controller.lastDrop = nil }
                .buttonStyle(.plain)
                .themedText(.caption, color: .textTertiary)
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.vertical, theme.spacing(.xs))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.backgroundSecondary))
        .accessibilityIdentifier("task-drop-banner")
    }

    /// One of three scales of the same day (ADR-0013 §D4), all anchored on
    /// `controller.day`.
    @ViewBuilder
    private var scale: some View {
        switch controller.scale {
        case .day: daySplit
        case .week: WeekView(controller: controller)
        case .month: MonthView(controller: controller)
        }
    }

    // MARK: Note column

    /// A split rather than two fixed columns: how much of the day is note and how much
    /// is timeline is the user's call, and it changes with what they are doing.
    private var daySplit: some View {
        HSplitView {
            noteColumn
                .frame(minWidth: 420)
            DayTimeline(controller: controller, calendar: calendar, window: vault.settings.dayHours)
                .frame(minWidth: 220, idealWidth: 300, maxWidth: 520)
        }
    }

    private var noteColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                header
                DayMonthSection(
                    day: day,
                    onSelect: { controller.show($0) },
                    onOpenDailyNote: { date in
                        controller.show(date)
                        controller.openDailyNote()
                    },
                    // The day first, then the flag, in both: the two sheets above read
                    // `controller.day`, so setting the flag alone would compose on the day
                    // the view is anchored on rather than on the cell that was clicked.
                    onNewEvent: { date in
                        controller.show(date)
                        controller.isCreatingEvent = true
                    },
                    onNewReminder: { date in
                        controller.show(date)
                        controller.isCreatingReminder = true
                    },
                    columnWidth: columnWidth,
                    dueDays: vault.index.dueDays
                )
                DayReferences(controller: controller)
                noteBody
            }
            .padding(theme.spacing(.l))
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            columnWidth = width
        }
    }

    /// The day being shown. The three buttons that used to sit here moved to the
    /// window toolbar: two day navigators a few centimetres apart is not a toolbar,
    /// it is a duplicate.
    private var header: some View {
        HStack(spacing: theme.spacing(.s)) {
            // The date as it is written in Italian. The compact `20260813` is the file
            // name (naming.md 4.6) and belongs where the file is named, not here.
            Text(day.italianForm).themedText(.title)
            Text(weekday).themedText(.body, color: dayKind.token ?? .textSecondary)
            // The name of the holiday, where the two grids only have room for a colour.
            if let holiday = ItalianHolidays.name(of: day, patron: vault.settings.patronSaint) {
                Text(holiday).themedText(.body, color: .calendarHoliday)
            }
            Spacer()
        }
    }

    /// `giovedì`, beside the date rather than repeating it.
    private var weekday: String { DateEntry.weekdayName(of: day) }

    /// Whether the day is ordinary, a Saturday, a Sunday or a holiday - the same rule
    /// the week and the month colour their numbers by.
    private var dayKind: ItalianHolidays.DayKind {
        ItalianHolidays.kind(of: day, patron: vault.settings.patronSaint)
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
                spellCheck: vault.settings.spellCheck,
                hidesMarkup: vault.settings.hidesMarkup,
                onFollowLink: { title in
                    if let path = vault.index.resolve(title: title).first { vault.openNote(at: path) }
                },
                vaultRoot: vault.root,
                notePath: note.relativePath,
                thumbnails: vault.thumbnails
            )
            .frame(minHeight: 320)
        } else {
            Button("Apri la nota di \(day.compactForm)") { controller.openDailyNote() }
                .buttonStyle(.plain)
                .themedText(.body, color: .accentPrimary)
        }
    }

    // MARK: Actions

    /// The sheet behind "Nuovo evento" and "Nuovo promemoria".
    private func draftSheet(
        title: String,
        showsTime: Bool,
        confirm: @escaping () -> Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(title).themedText(.title)
            Text("Sul giorno mostrato: \(day.italianForm)")
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
                        ForEach(VaultSettings.blockDurations, id: \.self) { minutes in
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
