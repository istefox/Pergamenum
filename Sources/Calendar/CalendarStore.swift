import Foundation

/// What the app needs from EventKit, behind a protocol.
///
/// EventKit cannot run in tests: the first call opens a system permission dialog that
/// only a person can answer. Everything above this line is therefore written against
/// the protocol and tested with a stub, and the real implementation stays thin enough
/// to be checked by using it.
@MainActor
protocol CalendarStore: AnyObject {
    var eventAccess: CalendarAccess { get }
    var reminderAccess: CalendarAccess { get }

    func requestAccess() async
    func events(on day: CalendarDate) -> [CalendarEvent]
    /// Events across a span of days, keyed by the day each one is drawn on.
    ///
    /// On the protocol rather than left to the caller because the week reads seven days
    /// and the month up to forty-two, and forty-two EventKit predicates on the main
    /// actor every time somebody pages a month is a stutter you can see. The default
    /// implementation loops `events(on:)`, so a store that has nothing better to offer
    /// - a stub, in particular - needs no code at all.
    func events(from first: CalendarDate, through last: CalendarDate) -> [CalendarDate: [CalendarEvent]]
    func reminders(dueOn day: CalendarDate) -> [CalendarReminder]
    /// Performs the fetch `reminders(dueOn:)` reads from. Part of the protocol because
    /// a caller cannot know a day's reminders without it, and one that forgot to call
    /// it would show an empty list rather than an error.
    func refreshReminders(on day: CalendarDate) async

    @discardableResult
    func createEvent(title: String, start: Date, end: Date, calendarTitle: String?) throws -> CalendarEvent
    func setCompleted(_ completed: Bool, reminderID: String) throws
    /// Creates a reminder in the Reminders app (SPEC §10, Calendario).
    @discardableResult
    func createReminder(title: String, due: CalendarDate?, listTitle: String?) throws -> CalendarReminder
    /// Titles of the calendars that can be written to.
    var writableCalendarTitles: [String] { get }
}

extension CalendarStore {
    func events(from first: CalendarDate, through last: CalendarDate) -> [CalendarDate: [CalendarEvent]] {
        var days: [CalendarDate: [CalendarEvent]] = [:]
        var cursor = first
        while cursor <= last {
            let found = events(on: cursor)
            if !found.isEmpty { days[cursor] = found }
            cursor = cursor.adding(days: 1)
        }
        return days
    }
}

enum CalendarAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case granted

    var isGranted: Bool { self == .granted }
}

enum CalendarError: Error, CustomStringConvertible {
    case noAccess
    case noWritableCalendar
    case reminderNotFound

    var description: String {
        switch self {
        case .noAccess: "accesso a Calendario o Promemoria non concesso"
        case .noWritableCalendar: "nessun calendario scrivibile"
        case .reminderNotFound: "il promemoria non esiste più"
        }
    }
}
