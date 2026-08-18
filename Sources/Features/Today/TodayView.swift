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

    @State private var draftTitle = ""
    @State private var draftStartHour = 9
    @State private var draftDurationMinutes = 60

    private var day: CalendarDate { controller.day }

    var body: some View {
        // A split rather than two fixed columns: how much of the day is note and how
        // much is timeline is the user's call, and it changes with what they are doing.
        HSplitView {
            noteColumn
                .frame(minWidth: 420)
            DayTimeline(controller: controller, calendar: calendar, window: vault.settings.dayHours)
                .frame(minWidth: 220, idealWidth: 300, maxWidth: 520)
        }
        .background(theme.color(.backgroundPrimary))
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

    // MARK: Note column

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
            Text(weekday).themedText(.body, color: .textSecondary)
            Spacer()
        }
    }

    /// `giovedì`, beside the date rather than repeating it.
    private var weekday: String { DateEntry.weekdayName(of: day) }

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
