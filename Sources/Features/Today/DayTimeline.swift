import SwiftUI

/// The hourly timeline of the day view (SPEC §8.3): the hours set in Impostazioni,
/// the calendar's events, and the blocks written in the daily note.
///
/// Split out of `TodayView` when the note column grew its own sections: two columns in
/// one type was past what SwiftLint allows and past what is readable.
struct DayTimeline: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    let controller: DayController
    let calendar: EventKitStore
    /// The hours to draw, from `settings.json` (SPEC §8.3's 06:00 to 22:00 by default).
    let window: HourWindow

    private let hourHeight: CGFloat = 44

    /// The window widened to reach everything on the day: an event at 23:00 under a
    /// window ending at 18:00 would otherwise be drawn below the grid and never seen.
    private var hours: HourWindow {
        Self.hours(for: window, blocks: blocks, timed: projectedEvents.timed)
    }

    /// The window widened from what the grid actually draws on this day (ADR-0075 §D5):
    /// the part of each event the day covers, not the event's own start and length, so
    /// the middle day of a three-day event is not stretched to midnight. An event's extent
    /// is the one drawn, with the 15-minute floor the boxes keep.
    ///
    /// `nonisolated`: pure arithmetic, and a `View`'s members otherwise infer the main
    /// actor for the closure below, which traps when a test calls this off the main actor.
    nonisolated static func hours(
        for window: HourWindow, blocks: [TimeBlock], timed: [ProjectedEvent]
    ) -> HourWindow {
        hours(
            for: window,
            startMinutes: blocks.map(\.startMinutes) + timed.map(\.startMinute),
            endMinutes: blocks.map(\.endMinutes)
                + timed.map { min(24 * 60, max($0.endMinute, $0.startMinute + 15)) }
        )
    }

    /// The widening itself (ADR-0053 §D2 seam #10), over plain integers so a test can
    /// call it without building a `TimeBlock` or a `CalendarEvent`.
    static func hours(for window: HourWindow, startMinutes: [Int], endMinutes: [Int]) -> HourWindow {
        window.covering(startMinutes: startMinutes, endMinutes: endMinutes)
    }

    /// The hours whose row accepts a dropped task (ADR-0075 §D3): every drawn row but a
    /// «24:00» one. A window reaching midnight draws that row as the day's bottom edge, and a
    /// task cannot start at 24:00 (`TaskTime` would quietly read it as 23:00).
    nonisolated static func droppableHours(in window: HourWindow) -> ClosedRange<Int> {
        window.first...min(window.last, 23)
    }

    private var firstHour: Int { hours.first }
    private var lastHour: Int { hours.last }

    private var blocks: [TimeBlock] { controller.blocks }
    private var events: [CalendarEvent] { controller.events }

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                hourLines
                ForEach(Array(zip(timedEvents, eventLanes)), id: \.0.id) { projected, lane in
                    TimelineEntryBox(
                        entry: TimelineEntry(
                            title: projected.event.title, subtitle: projected.event.calendarTitle,
                            start: projected.startMinute,
                            duration: max(15, projected.endMinute - projected.startMinute),
                            token: .accentMuted, isEvent: true
                        ),
                        firstHour: firstHour,
                        hourHeight: hourHeight,
                        lane: lane,
                        accessory: { eventNoteMark(projected.event) }
                    )
                    .contextMenu { eventNoteMenuItem(projected.event) }
                }
                ForEach(blocks) { block in
                    TimelineBlockBox(
                        block: block, controller: controller, calendar: calendar,
                        firstHour: firstHour, hourHeight: hourHeight
                    )
                }
            }
            .padding(.vertical, theme.spacing(.s))
        }
        .background(theme.color(.backgroundSecondary))
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                header
                allDayStrip
            }
        }
    }

    // MARK: La nota dell'evento (ADR-0013 §D2)

    /// «Nota per questo evento» when there is none, and the way to it when there is.
    ///
    /// In the context menu and not on the box, for the reason the block's own menu item
    /// carries: an event at 30 minutes is 18 points tall on this grid, and a button in there
    /// would take the room the title needs. The mark below is what says the note exists.
    @ViewBuilder
    private func eventNoteMenuItem(_ event: CalendarEvent) -> some View {
        if vault.hasEventNote(for: event.title, on: controller.day) {
            Button("Apri la nota dell'evento") { openEventNote(event) }
                .accessibilityIdentifier("open-event-note")
        } else {
            Button("Nota per questo evento") { openEventNote(event) }
                .accessibilityIdentifier("create-event-note")
        }
    }

    /// A small mark on the box of an event that has a note, so the ones that do are visible
    /// without opening five context menus to find out.
    @ViewBuilder
    private func eventNoteMark(_ event: CalendarEvent) -> some View {
        if vault.hasEventNote(for: event.title, on: controller.day) {
            Image(systemName: "doc.text")
                .themedText(.caption, color: .accentPrimary)
                .padding(.horizontal, theme.spacing(.xs))
                .padding(.vertical, 2)
        }
    }

    /// Creates the note when it is missing and opens it either way.
    ///
    /// The hour and the attendees are stamped from the event, so the note says what the
    /// meeting was before anybody types a word into it (§D3).
    private func openEventNote(_ event: CalendarEvent) {
        // Nil for an all-day event, which has no hour to stamp: `minuteOfDay` would give
        // midnight, and «00:00–00:00 · Ferragosto» is worse than saying it lasts all day.
        // The event's own clock start and end, not the part this day covers: the note is
        // about the meeting, not about the slice of it on screen.
        let start = event.isAllDay ? nil : time(at: DayProjection.minuteOfDay(event.start))
        let end = event.isAllDay ? nil : time(at: DayProjection.minuteOfDay(event.end))
        Task { @MainActor in
            await vault.openEventNote(
                for: event.title,
                on: controller.day,
                start: start,
                end: end,
                attendees: event.attendees
            )
        }
    }

    /// The hours, and the hour a dragged task lands on (ADR-0013 §D5).
    ///
    /// The row is the target rather than the line: a one-point rule is not something a
    /// mouse can be asked to hit, and the hour a task is dropped *in* is the hour whose
    /// band it was let go over.
    ///
    /// A «24:00» row is still drawn, so the grid keeps its height and the day its bottom
    /// line, but it is not a target (`droppableHours`).
    private var hourLines: some View {
        let droppable = Self.droppableHours(in: hours)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(firstHour...lastHour, id: \.self) { hour in
                if droppable.contains(hour) {
                    TaskDropTarget(
                        cornerRadius: theme.radius(.control),
                        onDrop: { payload in
                            await controller.drop(payload, on: controller.day, at: TaskTime(hour: hour, minute: 0))
                        },
                        content: { hourRow(hour) }
                    )
                    .accessibilityIdentifier("timeline-hour-\(hour)")
                } else {
                    hourRow(hour)
                }
            }
        }
    }

    private func hourRow(_ hour: Int) -> some View {
        HStack(alignment: .top, spacing: theme.spacing(.s)) {
            Text(TimeOfDay.formatted(hour: hour))
                .themedText(.caption, color: .textTertiary)
                .frame(width: 44, alignment: .trailing)
            Rectangle()
                .fill(theme.color(.borderSubtle))
                .frame(height: 1)
        }
        .frame(height: hourHeight, alignment: .top)
        // Without this the band is `.clear` above its one-point rule, and
        // a drop anywhere but on the rule itself finds nothing to land on.
        .contentShape(Rectangle())
    }

    /// Events with no hour of their own, above the grid.
    ///
    /// The grid runs 06:00 to 22:00 (SPEC §8.3) and places an event by its start time.
    /// An all-day event starts at midnight, so laid out that way it lands above the
    /// first line and is drawn nowhere: on a real calendar a whole category of entry
    /// - holidays, deadlines, birthdays - was simply missing from the day.
    @ViewBuilder
    private var allDayStrip: some View {
        if !allDayEvents.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(allDayEvents) { event in
                    HStack(spacing: theme.spacing(.xs)) {
                        Text("TUTTO IL GIORNO").themedText(.caption, color: .textTertiary)
                        Text(event.title)
                            .themedText(.caption, color: .textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        eventNoteMark(event)
                    }
                    .padding(.horizontal, theme.spacing(.xs))
                    .padding(.vertical, 3)
                    .background(theme.color(.accentMuted))
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                    .help(event.calendarTitle)
                    // The strip gets the same menu as a box: a holiday or a conference is as
                    // much something to take notes about as a meeting with an hour on it.
                    .contextMenu { eventNoteMenuItem(event) }
                }
            }
            .padding(.horizontal, theme.spacing(.s))
            .padding(.bottom, theme.spacing(.xs))
            .background(theme.color(.backgroundSecondary))
        }
    }

    /// The day's events as this day covers them (ADR-0075 §D5): a timed event that spans
    /// the whole day goes in the strip, and the rest at the minutes they have on it.
    private var projectedEvents: (allDay: [CalendarEvent], timed: [ProjectedEvent]) {
        events.projected(on: controller.day)
    }

    private var allDayEvents: [CalendarEvent] { projectedEvents.allDay }

    private var timedEvents: [ProjectedEvent] { projectedEvents.timed }

    /// Side by side where events overlap (PG-339), each measured by the box it is drawn as:
    /// never shorter than the 15 minutes `TimelineEntry` gives it, or a short event would
    /// be judged free of the one its box covers.
    private var eventLanes: [TimelineLane] {
        TimelineLane.assign(timedEvents.map { projected in
            (projected.startMinute, projected.startMinute + max(15, projected.endMinute - projected.startMinute))
        })
    }

    private var header: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text("TIMELINE").themedText(.caption, color: .textTertiary)
            Spacer()
            if calendar.eventAccess == .notDetermined {
                Button("Consenti calendario") {
                    Task { await calendar.requestAccess(); await controller.load() }
                }
                .buttonStyle(.plain)
                .themedText(.caption, color: .accentPrimary)
            } else if calendar.eventAccess == .denied {
                // After a refusal the request is a no-op, so the timeline points at the
                // only thing that can still change the answer.
                Button("Calendario negato: apri Impostazioni") {
                    EventKitStore.openPrivacySettings(for: .event)
                }
                .buttonStyle(.plain)
                .themedText(.caption, color: .accentPrimary)
            }
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .background(theme.color(.backgroundSecondary))
    }

    /// One entry, placed on the grid.
    ///
    /// **The accessory is a parameter and not something the caller overlays afterwards**,
    /// and that is the whole point of this signature. `.offset` moves what is drawn and
    /// leaves the layout frame where it was, so an overlay applied *after* it aligns to
    /// the un-moved rectangle: the delete button of a block at 09:00 was drawn at the top
    /// of the timeline, an hour and a half of empty grid away from the block it belonged
    /// to. Inside, it is placed on the entry before the entry moves.
    private func time(at minutes: Int) -> TaskTime {
        TaskTime(hour: minutes / 60, minute: minutes % 60)
    }
}
