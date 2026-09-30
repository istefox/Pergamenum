import Foundation

/// The part of an event one day covers (ADR-0075 §D5).
///
/// `CalendarService.bucketed` puts an event on every day it touches; this says where on
/// each of them. Before it, every copy of a Monday-to-Wednesday event was drawn at
/// Monday's hour on all three days, and a dinner from 22:00 to 01:00 at 22:00 on the next
/// day too. One helper for the Day and the Week views, so the two cannot place the same
/// event differently again.
///
/// Pure Foundation and app-only: neither connector knows EventKit, and `CalendarEvent`
/// is declared beside an `import EventKit`.
enum DayProjection: Equatable, Sendable {
    /// The event does not touch the day - including one that ends exactly at its start.
    case none
    /// The event covers the day from midnight to midnight, or EventKit flags it all-day.
    case allDay
    /// Clock minutes on the day, with 1440 for an end at the next midnight.
    case timed(startMinute: Int, endMinute: Int)

    /// The day runs from its local midnight to the next one, the same computation as
    /// `EventKitStore.dayRange`: a DST day is 23 or 25 hours long, and the minutes are
    /// the clock's, so an event from 00:00 to 12:00 is `timed(0, 720)` on it too.
    static func of(start: Date, end: Date, on day: CalendarDate, calendar: Calendar = .current) -> DayProjection {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        guard let dayStart = calendar.date(from: components),
              let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
        else { return .none }

        if start <= dayStart, end >= dayEnd { return .allDay }
        // A zero-length event inside the day is a moment on it, drawn at the view's own
        // floor rather than made invisible.
        if start == end, start >= dayStart, start < dayEnd {
            let minute = minuteOfDay(start, calendar: calendar)
            return .timed(startMinute: minute, endMinute: minute)
        }
        let clippedStart = max(start, dayStart)
        let clippedEnd = min(end, dayEnd)
        guard clippedEnd > clippedStart else { return .none }

        return .timed(
            startMinute: minuteOfDay(clippedStart, calendar: calendar),
            endMinute: clippedEnd == dayEnd ? 24 * 60 : minuteOfDay(clippedEnd, calendar: calendar)
        )
    }

    /// The clock minute of a moment, from its own day's midnight - the one date-to-minute
    /// conversion the Day and Week views share.
    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

/// A timed event with the minutes it covers on the day being drawn.
struct ProjectedEvent: Identifiable {
    let event: CalendarEvent
    let startMinute: Int
    let endMinute: Int

    var id: String { event.id }
}

extension CalendarEvent {
    /// Where this event sits on `day`. The flag wins: an event EventKit calls all-day is
    /// all-day on every day it touches, whatever end it reports, so the minute rule never
    /// depends on EventKit's end convention for one.
    func projection(on day: CalendarDate, calendar: Calendar = .current) -> DayProjection {
        let projection = DayProjection.of(start: start, end: end, on: day, calendar: calendar)
        guard isAllDay else { return projection }
        return projection == .none ? .none : .allDay
    }
}

extension [CalendarEvent] {
    /// The day's events as the timeline draws them: the flagged all-day events plus every
    /// timed one that covers the whole day in the strip, and the rest at their clipped
    /// minutes. An event that does not touch the day is in neither.
    func projected(
        on day: CalendarDate, calendar: Calendar = .current
    ) -> (allDay: [CalendarEvent], timed: [ProjectedEvent]) {
        let split = splitByAllDay
        var allDay = split.allDay
        var timed: [ProjectedEvent] = []
        for event in split.timed {
            switch event.projection(on: day, calendar: calendar) {
            case .none:
                continue
            case .allDay:
                allDay.append(event)
            case .timed(let startMinute, let endMinute):
                timed.append(ProjectedEvent(event: event, startMinute: startMinute, endMinute: endMinute))
            }
        }
        return (allDay, timed)
    }
}
