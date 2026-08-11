import EventKit
import Foundation
import Observation

/// One calendar event, as the timeline needs it.
///
/// A value type rather than an `EKEvent`: the timeline compares, sorts and diffs
/// these, and an `EKEvent` is a live object whose properties change under you when
/// the store reloads.
struct CalendarEvent: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarTitle: String
    /// Whether the app may edit it. A subscribed or delegated calendar is read-only.
    var isEditable: Bool
}

/// One reminder from the Reminders app.
struct CalendarReminder: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var due: CalendarDate?
    var isCompleted: Bool
    var listTitle: String
}

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
    func reminders(dueOn day: CalendarDate) -> [CalendarReminder]
    /// Performs the fetch `reminders(dueOn:)` reads from. Part of the protocol because
    /// a caller cannot know a day's reminders without it, and one that forgot to call
    /// it would show an empty list rather than an error.
    func refreshReminders(on day: CalendarDate) async

    @discardableResult
    func createEvent(title: String, start: Date, end: Date, calendarTitle: String?) throws -> CalendarEvent
    func setCompleted(_ completed: Bool, reminderID: String) throws
    /// Titles of the calendars that can be written to.
    var writableCalendarTitles: [String] { get }
}

enum CalendarAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case granted

    var isGranted: Bool { self == .granted }
}

/// The real EventKit-backed store.
///
/// Read-only on every calendar the Mac has, writing only where the user points it
/// (SPEC §8.2). EventKit is on-device only: there is no CalDAV path to Reminders,
/// which is why the spec treats that as a known constraint rather than a gap.
@MainActor
@Observable
final class EventKitStore: CalendarStore {
    private let store = EKEventStore()

    private(set) var eventAccess: CalendarAccess = .notDetermined
    private(set) var reminderAccess: CalendarAccess = .notDetermined
    /// The calendar Pergamenum writes time blocks to, by title (SPEC §8.3).
    var writeCalendarTitle: String?

    init() {
        refreshAccessStatus()
    }

    func refreshAccessStatus() {
        eventAccess = Self.access(for: EKEventStore.authorizationStatus(for: .event))
        reminderAccess = Self.access(for: EKEventStore.authorizationStatus(for: .reminder))
    }

    private static func access(for status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .fullAccess: .granted
        case .denied, .restricted, .writeOnly: .denied
        default: .notDetermined
        }
    }

    /// Asks for both permissions.
    ///
    /// Requested separately because the two are separate grants: a user may allow
    /// Calendar and refuse Reminders, and the app has to keep working with whichever
    /// it got rather than treating the pair as one switch.
    func requestAccess() async {
        if eventAccess == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
        if reminderAccess == .notDetermined {
            _ = try? await store.requestFullAccessToReminders()
        }
        refreshAccessStatus()
    }

    func events(on day: CalendarDate) -> [CalendarEvent] {
        guard eventAccess.isGranted else { return [] }
        guard let range = Self.dayRange(day) else { return [] }

        let predicate = store.predicateForEvents(
            withStart: range.start, end: range.end, calendars: nil
        )
        return store.events(matching: predicate)
            .map { event in
                CalendarEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "(senza titolo)",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarTitle: event.calendar.title,
                    isEditable: event.calendar.allowsContentModifications
                )
            }
            .sorted { $0.start < $1.start }
    }

    /// Reminders due on a day.
    ///
    /// EventKit's reminder fetch is callback-based and has no synchronous form, so
    /// this returns what the last refresh cached; `refreshReminders(on:)` performs the
    /// fetch. Blocking the main actor on a semaphore here would freeze the window.
    private(set) var cachedReminders: [CalendarReminder] = []

    func reminders(dueOn day: CalendarDate) -> [CalendarReminder] {
        cachedReminders.filter { $0.due == day }
    }

    func refreshReminders(on day: CalendarDate) async {
        guard reminderAccess.isGranted, let range = Self.dayRange(day) else { return }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: range.start, ending: range.end, calendars: nil
        )
        // Converted to value types inside the callback: `EKReminder` is not Sendable,
        // so the array itself cannot cross back over the continuation.
        cachedReminders = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let converted = (reminders ?? []).map { reminder in
                    CalendarReminder(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "(senza titolo)",
                        due: reminder.dueDateComponents.flatMap { components in
                            guard let year = components.year, let month = components.month,
                                  let day = components.day
                            else { return nil }
                            return CalendarDate(year: year, month: month, day: day)
                        },
                        isCompleted: reminder.isCompleted,
                        listTitle: reminder.calendar.title
                    )
                }
                continuation.resume(returning: converted)
            }
        }
    }

    var writableCalendarTitles: [String] {
        guard eventAccess.isGranted else { return [] }
        return store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map(\.title)
            .sorted()
    }

    @discardableResult
    func createEvent(
        title: String, start: Date, end: Date, calendarTitle: String?
    ) throws -> CalendarEvent {
        guard eventAccess.isGranted else { throw CalendarError.noAccess }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.calendar = calendar(named: calendarTitle) ?? store.defaultCalendarForNewEvents

        guard event.calendar != nil else { throw CalendarError.noWritableCalendar }
        try store.save(event, span: .thisEvent, commit: true)

        return CalendarEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: title,
            start: start,
            end: end,
            isAllDay: false,
            calendarTitle: event.calendar.title,
            isEditable: true
        )
    }

    func setCompleted(_ completed: Bool, reminderID: String) throws {
        guard reminderAccess.isGranted else { throw CalendarError.noAccess }
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
            throw CalendarError.reminderNotFound
        }
        reminder.isCompleted = completed
        try store.save(reminder, commit: true)
    }

    private func calendar(named title: String?) -> EKCalendar? {
        guard let title else { return nil }
        return store.calendars(for: .event).first { $0.title == title && $0.allowsContentModifications }
    }

    /// Midnight to midnight for a calendar date, in the user's own time zone.
    ///
    /// `nonisolated`: pure date arithmetic that touches no EventKit state, so binding
    /// it to the main actor would only force callers to hop for nothing.
    nonisolated static func dayRange(_ day: CalendarDate) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .day, value: 1, to: start)
        else { return nil }
        return (start, end)
    }

    /// A `Date` at a given hour and minute on a calendar date.
    nonisolated static func date(_ day: CalendarDate, hour: Int, minute: Int) -> Date? {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)
    }
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
