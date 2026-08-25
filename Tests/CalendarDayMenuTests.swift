import Foundation
import Testing
@testable import Pergamenum

/// ADR-0023 §D1, §D10 (plan 2026-08-25-universal-command-surface-parity, Task 7).
///
/// `CalendarDayCommand.entries(eventAccess:reminderAccess:)` is the one catalogue
/// `MonthView`, `WeekView` and `MiniCalendar` all read for their «Nuovo evento» / «Nuovo
/// promemoria» pair (R-09, R-13): titles taken from `ShortcutCommand.newEvent.title` /
/// `.newReminder.title` by identity, so a rewording of either menu-bar entry cannot
/// leave a day cell behind. Disabled rather than omitted without EventKit access
/// (ADR-0023 §D10) - a day cell that silently drops «Nuovo evento» teaches nobody
/// Pergamenum can make one.
///
/// The catalogue takes no `CalendarDate`: its shape is what makes "identici tra loro"
/// (R-09) a property of the three call sites sharing one function rather than a
/// convention kept by hand across `MonthView.swift`, `WeekView.swift` and
/// `MiniCalendar.swift`.
///
/// RED (Task 7): `CalendarDayCommand.entries` is a stub returning `[]`, so the `#require`
/// count guard below fails cleanly at RED instead of the two `#expect` subscripts that
/// followed it crashing the process on an out-of-range index - `#expect` does not stop
/// execution the way `#require` does.

@Test func bothEntriesArePresentInOrderAndEnabledWithFullAccess() throws {
    let entries = CalendarDayCommand.entries(eventAccess: true, reminderAccess: true)

    try #require(entries.count == 2)
    #expect(entries[0].command == .newEvent)
    #expect(entries[1].command == .newReminder)
    #expect(entries[0].isEnabled)
    #expect(entries[1].isEnabled)
}

// MARK: - R-09/ADR-0023 §D10: disabled, not absent, without EventKit access

@Test func newEventIsPresentButDisabledWithoutEventAccess() throws {
    let entries = CalendarDayCommand.entries(eventAccess: false, reminderAccess: true)

    try #require(entries.count == 2)
    #expect(entries[0].command == .newEvent)
    #expect(!entries[0].isEnabled)
    #expect(entries[1].isEnabled)
}

@Test func newReminderIsPresentButDisabledWithoutReminderAccess() throws {
    let entries = CalendarDayCommand.entries(eventAccess: true, reminderAccess: false)

    try #require(entries.count == 2)
    #expect(entries[1].command == .newReminder)
    #expect(entries[0].isEnabled)
    #expect(!entries[1].isEnabled)
}

// MARK: - R-09/R-13: the two titles are the Calendario menu's own, by identity

@Test func theTwoTitlesAreTheMenuBarsOwnByIdentity() throws {
    let entries = CalendarDayCommand.entries(eventAccess: true, reminderAccess: true)

    try #require(entries.count == 2)
    #expect(entries[0].title == ShortcutCommand.newEvent.title)
    #expect(entries[1].title == ShortcutCommand.newReminder.title)
}
