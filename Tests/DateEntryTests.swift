import Foundation
import Testing
@testable import Pergamenum

// The dates the Programma panel offers, and the ones typed into its field.

private let thursday = CalendarDate(iso: "2026-08-13")!

@Test func theQuickChoicesAreTheOnesThePanelLists() {
    let options = DateEntry.options(from: thursday)
    #expect(options.map(\.id) == ["today", "tomorrow", "next-week", "two-weeks", "three-weeks", "one-month"])
    #expect(options.map(\.title) == [
        "Oggi", "Domani", "La prossima settimana", "Fra 2 settimane", "Fra 3 settimane", "Fra un mese",
    ])
    #expect(options.map(\.date) == [
        CalendarDate(iso: "2026-08-13"),
        CalendarDate(iso: "2026-08-14"),
        CalendarDate(iso: "2026-08-17"),
        CalendarDate(iso: "2026-08-27"),
        CalendarDate(iso: "2026-09-03"),
        CalendarDate(iso: "2026-09-13"),
    ])
}

/// Chosen on a Monday, "la prossima settimana" is the next one. Today would be a
/// choice that changes nothing while looking like it did.
@Test func nextWeekFromAMondayIsTheFollowingMonday() {
    let monday = CalendarDate(iso: "2026-08-17")!
    #expect(DateEntry.nextMonday(after: monday) == CalendarDate(iso: "2026-08-24"))
    let sunday = CalendarDate(iso: "2026-08-16")!
    #expect(DateEntry.nextMonday(after: sunday) == CalendarDate(iso: "2026-08-17"))
}

/// A month from the 31st, where naive arithmetic invents the 31st of the next month.
@Test func aMonthFromTheEndOfAMonthLandsOnADayThatExists() {
    #expect(DateEntry.adding(months: 1, to: CalendarDate(iso: "2026-01-31")!) == CalendarDate(iso: "2026-02-28"))
    #expect(DateEntry.adding(months: 1, to: CalendarDate(iso: "2026-08-31")!) == CalendarDate(iso: "2026-09-30"))
}

@Test func aDateTypedIntoTheFieldIsRead() {
    #expect(DateEntry.parse("oggi", today: thursday) == thursday)
    #expect(DateEntry.parse("Domani", today: thursday) == CalendarDate(iso: "2026-08-14"))
    #expect(DateEntry.parse("2026-09-01", today: thursday) == CalendarDate(iso: "2026-09-01"))
    #expect(DateEntry.parse("20/08", today: thursday) == CalendarDate(iso: "2026-08-20"))
    #expect(DateEntry.parse("20-08-2026", today: thursday) == CalendarDate(iso: "2026-08-20"))
    #expect(DateEntry.parse("1.9.26", today: thursday) == CalendarDate(iso: "2026-09-01"))
}

/// A day and a month that have gone by mean next year: a task panel is not where
/// anyone types a date in the past.
@Test func aDayAndMonthAlreadyPastMeanNextYear() {
    #expect(DateEntry.parse("5/8", today: thursday) == CalendarDate(iso: "2027-08-05"))
    #expect(DateEntry.parse("13/8", today: thursday) == thursday)
}

/// Refused rather than guessed: a panel that silently picks the wrong day is worse
/// than one that picks none.
@Test func whatIsNotADateIsNotTurnedIntoOne() {
    for text in ["", "   ", "prossimo mese", "32/13", "20/", "banana", "2026-13-01"] {
        #expect(DateEntry.parse(text, today: thursday) == nil, "«\(text)» è stato letto come una data")
    }
}

@Test func theHintBesideEachChoiceIsTheDayInItalian() {
    #expect(DateEntry.hint(for: thursday).contains("13"))
    #expect(DateEntry.monthName(month: 8, year: 2026) == "agosto")
    #expect(DateEntry.monthName(month: 1, year: 2026) == "gennaio")
}
