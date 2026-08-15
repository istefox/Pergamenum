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

    @State private var hoveredBlock: String?

    private var blocks: [TimeBlock] { controller.blocks }
    private var events: [CalendarEvent] { controller.events }

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                hourLines
                ForEach(timedEvents) { event in
                    entry(Entry(
                        title: event.title, subtitle: event.calendarTitle,
                        start: minutes(from: event.start), duration: duration(of: event),
                        token: .accentMuted, isEvent: true
                    ))
                }
                ForEach(blocks) { block in
                    blockEntry(block)
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

    private var hourLines: some View {
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
    }

    /// A block, with the delete the context menu used to hide.
    ///
    /// A menu you have to know is there is not a way to undo a click; the button
    /// appears on hover, and the menu keeps its entry for the keyboard.
    private func blockEntry(_ block: TimeBlock) -> some View {
        entry(Entry(
            title: block.title,
            subtitle: block.isPublished ? "pubblicato" : "solo nella nota",
            start: block.startMinutes, duration: block.durationMinutes,
            token: .stickyBlue, isEvent: false
        ))
            .overlay(alignment: .topTrailing) {
                // Always in the hierarchy, only its opacity follows the pointer. Built
                // by `if hoveredBlock == block.id` it left on mouse-down - the rebuild
                // took the button away between press and release - so the click landed
                // on nothing and the block stayed, on the timeline and in the note.
                Button {
                    controller.remove(block)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.color(.textSecondary))
                }
                .buttonStyle(.plain)
                .padding(2)
                .opacity(hoveredBlock == block.id ? 1 : 0.35)
                .help("Elimina il blocco")
                .accessibilityIdentifier("timeline-remove-block")
            }
            .onHover { hoveredBlock = $0 ? block.id : (hoveredBlock == block.id ? nil : hoveredBlock) }
            .contextMenu {
                Button(block.isPublished ? "Già pubblicato" : "Pubblica sul Calendario") {
                    controller.publish(block, toCalendarTitled: calendar.writeCalendarTitle)
                }
                .disabled(block.isPublished || !calendar.eventAccess.isGranted)
                Button("Elimina il blocco") { controller.remove(block) }
            }
            // `.contain` before the identifier, or the hover delete inside disappears
            // from XCUI along with everything else the entry draws.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("timeline-block")
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

    /// What the timeline draws in a slot, whichever side it came from.
    private struct Entry {
        var title: String
        var subtitle: String
        var start: Int
        var duration: Int
        var token: ColorToken
        /// From the calendar rather than from the note, which is drawn differently.
        var isEvent: Bool
    }

    private func entry(_ entry: Entry) -> some View {
        let offset = CGFloat(entry.start - firstHour * 60) / 60 * hourHeight
        let height = max(18, CGFloat(entry.duration) / 60 * hourHeight)

        return VStack(alignment: .leading, spacing: 0) {
            Text(entry.title).themedText(.caption).lineLimit(1)
            if height > 30 {
                Text(entry.subtitle).themedText(.caption, color: .textTertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, theme.spacing(.xs))
        .padding(.vertical, 2)
        .frame(width: 236, height: height, alignment: .topLeading)
        .background(theme.color(entry.token))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .overlay(alignment: .leading) {
            // Events from the calendar and blocks from the note are distinguishable at
            // a glance: only one of them is something this app owns.
            Rectangle()
                .fill(theme.color(entry.isEvent ? .accentPrimary : .taskScheduled))
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
}
