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

/// The day view's title. The compact form is the file name (naming.md 4.6) and was
/// what the header showed: `20260813` is not how anyone writes a date.
@Test func aDateIsWrittenTheItalianWayForTheInterface() {
    #expect(thursday.italianForm == "13/08/2026")
    #expect(CalendarDate(iso: "2026-01-05")?.italianForm == "05/01/2026")
    // And the file name is untouched by it.
    #expect(thursday.compactForm == "20260813")
    #expect(thursday.description == "2026-08-13")
}

@Test func theWeekdayIsNamedInItalian() {
    #expect(DateEntry.weekdayName(of: thursday) == "giovedì")
    #expect(DateEntry.weekdayName(of: CalendarDate(iso: "2026-08-16")!) == "domenica")
}

/// The month follows the column: the grip it replaces was one handle too many next to
/// a divider that was already there.
@Test func theMonthWidthFollowsTheColumnBetweenItsBounds() {
    #expect(DayMonthSection.calendarWidth(inColumnOf: 0) == DayMonthSection.narrowest)
    #expect(DayMonthSection.calendarWidth(inColumnOf: 200) == DayMonthSection.narrowest)
    #expect(DayMonthSection.calendarWidth(inColumnOf: 2000) == DayMonthSection.widest)

    let narrow = DayMonthSection.calendarWidth(inColumnOf: 420)
    let wide = DayMonthSection.calendarWidth(inColumnOf: 620)
    #expect(narrow < wide, "allargando la colonna il mese non è cresciuto")
    #expect(narrow >= DayMonthSection.narrowest && wide <= DayMonthSection.widest)
}

/// A seven-column grid 460 wide with 22-point cells draws rectangles four times wider
/// than tall, which is the look this replaces.
@Test func theCellsKeepTheirProportionsAsTheGridGrows() {
    #expect(DayMonthSection.cellHeight(forWidth: 210) == 22)
    #expect(DayMonthSection.cellHeight(forWidth: 460) > 22)
    #expect(DayMonthSection.cellHeight(forWidth: 2000) == 34)
}
