import AppKit
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

extension [CalendarEvent] {
    /// The day's events split by whether they have an hour of their own.
    ///
    /// The timeline draws its grid from 06:00 to 22:00 and places an entry by its start
    /// time. An all-day event starts at midnight, so drawn that way it lands above the
    /// first line and disappears: holidays, deadlines and birthdays were missing from
    /// every day that had them. Kept here rather than inside the view so the split is
    /// something a test can hold.
    var splitByAllDay: (allDay: [CalendarEvent], timed: [CalendarEvent]) {
        (filter(\.isAllDay), filter { !$0.isAllDay })
    }
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
    /// Creates a reminder in the Reminders app (SPEC §10, Calendario).
    @discardableResult
    func createReminder(title: String, due: CalendarDate?, listTitle: String?) throws -> CalendarReminder
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

    /// Bumped every time something outside this app moved: EventKit's store changed, or
    /// Pergamenum came back to the front.
    ///
    /// Observed by the day view. Two separate signals because they cover two different
    /// failures, and neither covers the other:
    ///
    /// - `EKEventStoreChanged` is what EventKit documents for content: an event created
    ///   in Calendar.app appears here without a relaunch.
    /// - Returning to the front is what covers permission. The status is read once at
    ///   launch, so a user who opens Impostazioni di Sistema, grants access and comes
    ///   back would otherwise still be told "nessun accesso" by a store that never
    ///   asked again.
    private(set) var changeCount = 0

    /// Cancelled from `deinit`, which cannot touch main-actor state, so the handles are
    /// held outside the isolation.
    private nonisolated(unsafe) var observations: [Task<Void, Never>] = []

    init() {
        refreshAccessStatus()
        observations = [
            // The content signal always counts: EventKit only sends it when something
            // actually moved.
            observe(.EKEventStoreChanged, alwaysCounts: true),
            // Activation does not. Switching back to the app is frequent, and reloading
            // the day on every window focus would be a visible stutter for nothing, so
            // this one counts only when the access status it re-read has changed.
            observe(NSApplication.didBecomeActiveNotification, alwaysCounts: false),
        ]
    }

    deinit {
        observations.forEach { $0.cancel() }
    }

    private func observe(_ name: Notification.Name, alwaysCounts: Bool) -> Task<Void, Never> {
        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: name) {
                guard let self else { return }
                await self.externalChange(alwaysCounts: alwaysCounts)
            }
        }
    }

    /// Something moved outside the app: re-read the access status, then let the views
    /// know. The status is re-read first so a view reacting to the count sees the new
    /// permission rather than the one from launch.
    private func externalChange(alwaysCounts: Bool) {
        let before = (eventAccess, reminderAccess)
        refreshAccessStatus()
        guard alwaysCounts || before != (eventAccess, reminderAccess) else { return }
        changeCount += 1
    }

    func refreshAccessStatus() {
        eventAccess = Self.access(for: EKEventStore.authorizationStatus(for: .event))
        reminderAccess = Self.access(for: EKEventStore.authorizationStatus(for: .reminder))
    }

    /// Whether asking again can still produce a dialog.
    ///
    /// macOS asks once. After a refusal `requestAccess()` returns immediately without
    /// showing anything, so a button wired to it is a button that does nothing: the
    /// only way back is the Privacy pane.
    var canStillBeAsked: Bool {
        eventAccess == .notDetermined || reminderAccess == .notDetermined
    }

    /// The Privacy pane that governs one of the two permissions.
    ///
    /// Built apart from the opening so it can be checked: the two entities land on two
    /// different panes, and sending a user refused on Reminders to the Calendar pane
    /// leaves them looking for a switch that is not there.
    /// `nonisolated`: it is string arithmetic, and it is the one piece of this that a
    /// test can check without a main actor.
    nonisolated static func privacyPaneURL(for entity: EKEntityType) -> URL? {
        let pane = entity == .event ? "Calendars" : "Reminders"
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)")
    }

    /// Opens Impostazioni di Sistema on that pane.
    static func openPrivacySettings(for entity: EKEntityType) {
        guard let url = privacyPaneURL(for: entity) else { return }
        NSWorkspace.shared.open(url)
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
    /// Why the last request failed, when it failed.
    ///
    /// Kept rather than swallowed. A `try?` here turns "macOS refused to even ask" into
    /// a status that reads "non richiesto" forever, which is indistinguishable from a
    /// button nobody pressed: the one state where the user needs to be told something
    /// is the one state that said nothing.
    private(set) var lastAccessError: String?

    func requestAccess() async {
        lastAccessError = nil
        if eventAccess == .notDetermined {
            do {
                _ = try await store.requestFullAccessToEvents()
            } catch {
                lastAccessError = "Calendario: \(error.localizedDescription)"
            }
        }
        if reminderAccess == .notDetermined {
            do {
                _ = try await store.requestFullAccessToReminders()
            } catch {
                let reminders = "Promemoria: \(error.localizedDescription)"
                lastAccessError = lastAccessError.map { "\($0)\n\(reminders)" } ?? reminders
            }
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
        // No lower bound, and that is the fix for a bug this app was creating for
        // itself. A reminder whose due date carries no time - which is what
        // `createReminder` below writes, and what the Reminders app calls a reminder
        // "on" a day - sits at exactly midnight. Bounded by `range.start`, also exactly
        // midnight, EventKit never returned it: Pergamenum created reminders it could
        // not then see. The upper bound still keeps the fetch bounded, and
        // `reminders(dueOn:)` does the day filtering itself, so nothing extra is shown.
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: range.end, calendars: nil
        )
        // Converted to value types inside the callback: `EKReminder` is not Sendable,
        // so the array itself cannot cross back over the continuation.
        //
        // `@Sendable` on the completion is load-bearing and was paid for with a crash.
        // EventKit calls this block on a private background queue. Written plainly in a
        // `@MainActor` class the block inherits that isolation, so the first thing it
        // does off the main thread is assert it is on the main thread: SIGTRAP inside
        // `dispatch_assert_queue`, the moment the day view is opened by a user who has
        // actually granted access. A stub cannot reproduce it - a stub answers
        // synchronously, on the main actor, which is the one case that works.
        cachedReminders = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { @Sendable reminders in
                continuation.resume(returning: Self.converted(reminders ?? []))
            }
        }
    }

    /// `nonisolated` for the same reason: it runs on EventKit's queue.
    nonisolated private static func converted(_ reminders: [EKReminder]) -> [CalendarReminder] {
        reminders.map { reminder in
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

        // The cache is corrected here rather than left to the next fetch. Ticking a
        // box has to register instantly, and `reminders(dueOn:)` reads this cache:
        // without the line the tick appeared only if something else happened to
        // refresh first.
        if let index = cachedReminders.firstIndex(where: { $0.id == reminderID }) {
            cachedReminders[index].isCompleted = completed
        }
    }

    /// Creates a reminder in the Reminders app (SPEC §10, Calendario).
    @discardableResult
    func createReminder(
        title: String, due: CalendarDate?, listTitle: String?
    ) throws -> CalendarReminder {
        guard reminderAccess.isGranted else { throw CalendarError.noAccess }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        if let due {
            reminder.dueDateComponents = DateComponents(
                year: due.year, month: due.month, day: due.day
            )
        }
        let lists = store.calendars(for: .reminder).filter(\.allowsContentModifications)
        guard let list = listTitle.flatMap({ title in lists.first { $0.title == title } })
            ?? store.defaultCalendarForNewReminders()
            ?? lists.first
        else { throw CalendarError.noWritableCalendar }
        reminder.calendar = list

        try store.save(reminder, commit: true)
        let created = CalendarReminder(
            id: reminder.calendarItemIdentifier,
            title: title,
            due: due,
            isCompleted: false,
            listTitle: list.title
        )
        // Added to the cache immediately, for the same reason as above. `createEvent`
        // has no equivalent because events are read live; reminders go through a cache,
        // and a cache that does not know about a write the same object just made is a
        // cache that lies. It happened to look right only because the store-changed
        // observer fired first, which is luck, not design.
        cachedReminders.append(created)
        return created
    }

    /// Titles of the reminder lists that can be written to.
    var writableReminderListTitles: [String] {
        guard reminderAccess.isGranted else { return [] }
        return store.calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .map(\.title)
            .sorted()
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
