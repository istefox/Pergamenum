import SwiftUI

/// The hourly timeline of the day view (SPEC §8.3): the hours set in Impostazioni,
/// the calendar's events, and the blocks written in the daily note.
///
/// Split out of `TodayView` when the note column grew its own sections: two columns in
/// one type was past what SwiftLint allows and past what is readable.
struct DayTimeline: View {
    @Environment(\.theme) private var theme

    let controller: DayController
    let calendar: EventKitStore
    /// The hours to draw, from `settings.json` (SPEC §8.3's 06:00 to 22:00 by default).
    let window: HourWindow

    private let hourHeight: CGFloat = 44

    /// The window widened to reach everything on the day: an event at 23:00 under a
    /// window ending at 18:00 would otherwise be drawn below the grid and never seen.
    private var hours: HourWindow {
        window.covering(
            startMinutes: blocks.map(\.startMinutes) + timedEvents.map { minutes(from: $0.start) },
            endMinutes: blocks.map(\.endMinutes)
                + timedEvents.map { minutes(from: $0.start) + duration(of: $0) }
        )
    }

    private var firstHour: Int { hours.first }
    private var lastHour: Int { hours.last }

    private var blocks: [TimeBlock] { controller.blocks }
    private var events: [CalendarEvent] { controller.events }

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                hourLines
                ForEach(timedEvents) { event in
                    TimelineEntryBox(
                        entry: TimelineEntry(
                            title: event.title, subtitle: event.calendarTitle,
                            start: minutes(from: event.start), duration: duration(of: event),
                            token: .accentMuted, isEvent: true
                        ),
                        firstHour: firstHour,
                        hourHeight: hourHeight
                    )
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

    /// The hours, and the hour a dragged task lands on (ADR-0013 §D5).
    ///
    /// The row is the target rather than the line: a one-point rule is not something a
    /// mouse can be asked to hit, and the hour a task is dropped *in* is the hour whose
    /// band it was let go over.
    private var hourLines: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(firstHour...lastHour, id: \.self) { hour in
                TaskDropTarget(
                    cornerRadius: theme.radius(.control),
                    onDrop: { payload in
                        controller.drop(payload, on: controller.day, at: TaskTime(hour: hour, minute: 0))
                    },
                    content: {
                        HStack(alignment: .top, spacing: theme.spacing(.s)) {
                            Text(String(format: "%02d:00", hour))
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
                )
                .accessibilityIdentifier("timeline-hour-\(hour)")
            }
        }
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
                    }
                    .padding(.horizontal, theme.spacing(.xs))
                    .padding(.vertical, 3)
                    .background(theme.color(.accentMuted))
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                    .help(event.calendarTitle)
                }
            }
            .padding(.horizontal, theme.spacing(.s))
            .padding(.bottom, theme.spacing(.xs))
            .background(theme.color(.backgroundSecondary))
        }
    }

    private var allDayEvents: [CalendarEvent] { events.splitByAllDay.allDay }
    private var timedEvents: [CalendarEvent] { events.splitByAllDay.timed }

    private var header: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Text("TIMELINE").themedText(.caption, color: .textTertiary)
            Spacer()
            if calendar.eventAccess == .notDetermined {
                Button("Consenti Calendario") {
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
    private func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func duration(of event: CalendarEvent) -> Int {
        max(15, Int(event.end.timeIntervalSince(event.start) / 60))
    }
}
