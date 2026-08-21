import Foundation
import Testing
@testable import Pergamenum

// The relative date bounds of ADR-0014. Every test here fixes the day it asks about, which is
// the whole reason §D3 makes the day a parameter: a test that reads the clock is a test that
// fails one day a year and passes the other three hundred and sixty-four.

/// A Friday, chosen because it is where `today-7` and `week-start` disagree, which is the
/// disagreement the ADR exists for.
private let friday = CalendarDate(iso: "2026-08-21")!

@Test func anIsoDateStillReadsAsItself() {
    #expect(ViewDateBound.parse("2026-08-17") == .day(CalendarDate(iso: "2026-08-17")!))
    #expect(ViewDateBound.parse("2026-08-17")?.resolved(on: friday) == CalendarDate(iso: "2026-08-17"))
}

@Test func theThreeWordsParseAndNothingElseDoes() {
    #expect(ViewDateBound.parse("today") == .today)
    #expect(ViewDateBound.parse("today-7") == .daysBeforeToday(7))
    #expect(ViewDateBound.parse("week-start") == .weekStart)
    // Case-insensitive, like the `and`/`or`/`not` the lexer already lowercases.
    #expect(ViewDateBound.parse("Week-Start") == .weekStart)

    // The vocabulary is closed, and each of these is a shape somebody will try.
    #expect(ViewDateBound.parse("oggi") == nil)
    #expect(ViewDateBound.parse("this-week") == nil)
    #expect(ViewDateBound.parse("today-") == nil)
    #expect(ViewDateBound.parse("today-abc") == nil)
    #expect(ViewDateBound.parse("7d") == nil)
    #expect(ViewDateBound.parse("2026-8-1") == nil)
    // Refused by §D2, and this pins the refusal: `+` is not in the lexer's word set, so a
    // forward bound must not creep in through this parser either.
    #expect(ViewDateBound.parse("today+7") == nil)
}

@Test func todayResolvesToTheDayItIsGiven() {
    #expect(ViewDateBound.today.resolved(on: friday) == friday)
    // `today-0` is `today` written the long way. Allowed rather than refused: refusing it
    // would be a rule to explain for no gain.
    #expect(ViewDateBound.daysBeforeToday(0).resolved(on: friday) == friday)
}

@Test func aWindowInDaysCountsBackwardsAndCrossesAMonth() {
    #expect(ViewDateBound.daysBeforeToday(7).resolved(on: friday) == CalendarDate(iso: "2026-08-14"))
    #expect(ViewDateBound.daysBeforeToday(30).resolved(on: friday) == CalendarDate(iso: "2026-07-22"))
    // Across a year boundary, and a leap day, since the arithmetic goes through Calendar.
    let january = CalendarDate(iso: "2028-01-02")!
    #expect(ViewDateBound.daysBeforeToday(5).resolved(on: january) == CalendarDate(iso: "2027-12-28"))
    #expect(ViewDateBound.daysBeforeToday(1).resolved(on: CalendarDate(iso: "2028-03-01")!)
        == CalendarDate(iso: "2028-02-29"))
}

@Test func weekStartIsTheMondayAndThatIsWhyItExists() {
    // 21 August 2026 is a Friday; its Monday is the 17th. `today-7` would say the 14th, which
    // is the Friday before - last week's finished work inside this week's review.
    #expect(ViewDateBound.weekStart.resolved(on: friday) == CalendarDate(iso: "2026-08-17"))
    #expect(ViewDateBound.daysBeforeToday(7).resolved(on: friday) == CalendarDate(iso: "2026-08-14"))

    // Monday is its own week-start, and Sunday belongs to the week that started six days back -
    // Monday and not Sunday, because that is the week every grid in this app draws.
    #expect(ViewDateBound.weekStart.resolved(on: CalendarDate(iso: "2026-08-17")!)
        == CalendarDate(iso: "2026-08-17"))
    #expect(ViewDateBound.weekStart.resolved(on: CalendarDate(iso: "2026-08-23")!)
        == CalendarDate(iso: "2026-08-17"))
    // And across a month boundary.
    #expect(ViewDateBound.weekStart.resolved(on: CalendarDate(iso: "2026-09-02")!)
        == CalendarDate(iso: "2026-08-31"))
}

@Test func aBoundWritesItselfBackTheWayItWasRead() {
    // A block rendered back out has to be the block that was read: `week-start` resolved to a
    // date in the text would freeze the question into one of its answers.
    for text in ["2026-08-17", "today", "today-7", "week-start"] {
        #expect(ViewDateBound.parse(text)?.text == text)
    }
}

// MARK: - Nella grammatica

@Test func theFilterParsesARelativeBound() throws {
    #expect(try ViewFilter.parse("modified >= week-start", line: 1)
        == .comparison(.modified, .atLeast, .weekStart))
    #expect(try ViewFilter.parse("date > today-30", line: 1)
        == .comparison(.date, .greaterThan, .daysBeforeToday(30)))
    #expect(try ViewFilter.parse("date = today", line: 1)
        == .comparison(.date, .equalTo, .today))
}

@Test func aBoundThatIsNeitherNamesTheLine() throws {
    // Never an empty result and never a silently dropped term: ADR-0009 §D1's rule, which is
    // the reason a relative bound had to go through the parser rather than around it.
    let error = #expect(throws: ViewBlockError.self) {
        try ViewFilter.parse("modified >= questa-settimana", line: 4)
    }
    #expect(error?.line == 4)
    #expect(error?.reason.contains("week-start") == true)
}

@Test func theSampleWeeklyReviewAsksAboutTheWeek() throws {
    // The template shipped with a workaround and a paragraph explaining it; both are gone.
    let review = try #require(SampleViews.all.first { $0.name == "Revisione settimanale" })
    let text = review.text

    #expect(text.contains("where: modified >= week-start"))
    #expect(text.contains("where: tag(\"project-*\") and modified >= week-start"))
    #expect(!text.contains("senza avere una data dentro"))
}
