import Foundation
@testable import Pergamenum

/// The scaffolding the day view's tests share: a calendar that never touches EventKit,
/// a vault on disk that cleans up after itself, and the controllers wired to both.
///
/// In a file of its own because two suites need it - `DayControllerTests` and
/// `TimeBlockDeletionTests` - and a copy in each is a copy that drifts.

/// A `CalendarStore` that never touches EventKit.
///
/// EventKit needs a permission dialog only a person can answer, which is exactly why
/// the protocol exists: everything this app does around it is ordinary logic and is
/// tested here.
@MainActor
final class StubCalendarStore: CalendarStore {
    var eventAccess: CalendarAccess = .granted
    var reminderAccess: CalendarAccess = .granted
    var writableCalendarTitles: [String] = ["Pergamenum", "Lavoro"]

    private(set) var createdEvents: [CalendarEvent] = []
    private(set) var completedCalls: [(id: String, completed: Bool)] = []
    var storedReminders: [CalendarReminder] = []
    /// When set, every write fails with it.
    var failure: CalendarError?

    func requestAccess() async {}

    /// The real store fetches reminders here; this one already has them.
    func refreshReminders(on day: CalendarDate) async {}

    func events(on day: CalendarDate) -> [CalendarEvent] { createdEvents }

    func reminders(dueOn day: CalendarDate) -> [CalendarReminder] {
        storedReminders.filter { $0.due == day }
    }

    @discardableResult
    func createEvent(title: String, start: Date, end: Date, calendarTitle: String?) throws -> CalendarEvent {
        if let failure { throw failure }
        let event = CalendarEvent(
            id: "event-\(createdEvents.count)", title: title, start: start, end: end,
            isAllDay: false, calendarTitle: calendarTitle ?? "Predefinito", isEditable: true
        )
        createdEvents.append(event)
        return event
    }

    @discardableResult
    func createReminder(title: String, due: CalendarDate?, listTitle: String?) throws -> CalendarReminder {
        if let failure { throw failure }
        let reminder = CalendarReminder(
            id: "reminder-\(storedReminders.count)", title: title, due: due,
            isCompleted: false, listTitle: listTitle ?? "Predefinito"
        )
        storedReminders.append(reminder)
        return reminder
    }

    func setCompleted(_ completed: Bool, reminderID: String) throws {
        if let failure { throw failure }
        completedCalls.append((reminderID, completed))
        storedReminders = storedReminders.map { reminder in
            var copy = reminder
            if copy.id == reminderID { copy.isCompleted = completed }
            return copy
        }
    }
}

let testDay = CalendarDate(iso: "2026-08-11")!

let dayNoteWithProse = """
---
date: 2026-08-11
tags:
  - type-note
---

Sopralluogo in reparto stampaggio.
"""

/// A daily note as the app writes it when a block has to go somewhere: frontmatter and
/// nothing else.
let emptyDailyNote = """
---
date: 2026-08-11
tags:
  - type-note
---

"""

/// `openingTheDailyNote: false` for the tests about what the day view does to the
/// editor: with it open from the start there is no way to tell a pane the user asked
/// for from one a block opened behind their back.
@MainActor
func makeController(
    vault: borrowing TemporaryVault,
    store: StubCalendarStore,
    openingTheDailyNote: Bool = true
) async throws -> (DayController, VaultController) {
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    if openingTheDailyNote { controller.openNote(at: "Calendar/20260811.md") }

    let day = DayController(store: store, vault: controller)
    day.show(CalendarDate(iso: "2026-08-11")!)
    return (day, controller)
}
