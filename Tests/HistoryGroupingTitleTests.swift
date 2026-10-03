import Foundation
import Testing
@testable import Pergamenum

// PG-263 (burn-down 2026-10-03): `HistoryGrouping` dropped its private `DateFormatter`s for the
// Core helpers (`DateEntry`, `TimeOfDay`), and its `locale:` parameter with them. The existing
// `NoteHistoryTests` pin Oggi/Ieri and one older day; these pin the edges the swap could move:
// the day boundary read in the calendar's own zone, month and year turns, a single-digit day,
// and the padded time.
// (coverage): the tests below assert only what `HistoryGrouping`'s doc comments state.

@Suite struct HistoryGroupingTitleTests {
    private static func calendar(_ zone: String = "Europe/Rome") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    private static func instant(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, in calendar: Calendar
    ) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )))
    }

    private static func title(_ day: Date, now: Date, calendar: Calendar) -> String {
        HistoryGrouping.title(for: calendar.startOfDay(for: day), now: now, calendar: calendar)
    }

    @Test func todayAndYesterdayAreNamedWhateverTheClockTime() throws {
        let calendar = Self.calendar()
        let now = try Self.instant(2026, 8, 18, 0, 5, in: calendar)

        #expect(Self.title(try Self.instant(2026, 8, 18, 23, 59, in: calendar), now: now, calendar: calendar) == "Oggi")
        #expect(Self.title(try Self.instant(2026, 8, 17, 0, 0, in: calendar), now: now, calendar: calendar) == "Ieri")
    }

    @Test func yesterdayCrossesAMonthAndAYear() throws {
        let calendar = Self.calendar()

        let firstOfMarch = try Self.instant(2026, 3, 1, in: calendar)
        #expect(Self.title(try Self.instant(2026, 2, 28, in: calendar), now: firstOfMarch, calendar: calendar) == "Ieri")

        let newYear = try Self.instant(2027, 1, 1, in: calendar)
        #expect(Self.title(try Self.instant(2026, 12, 31, in: calendar), now: newYear, calendar: calendar) == "Ieri")
    }

    @Test func twoDaysBackIsNamedByWeekdayAndDate() throws {
        let calendar = Self.calendar()
        let now = try Self.instant(2026, 8, 18, in: calendar)

        // 16 August 2026 is a Sunday.
        #expect(Self.title(try Self.instant(2026, 8, 16, in: calendar), now: now, calendar: calendar) == "domenica 16 agosto")
    }

    @Test func aSingleDigitDayIsNotPadded() throws {
        let calendar = Self.calendar()
        let now = try Self.instant(2026, 8, 18, in: calendar)

        // 5 August 2026 is a Wednesday. The old `EEEE d MMMM` never padded the day either.
        #expect(Self.title(try Self.instant(2026, 8, 5, in: calendar), now: now, calendar: calendar) == "mercoledì 5 agosto")
    }

    @Test func theDayIsReadInTheCalendarsZoneNotInUTC() throws {
        // 23:30 UTC on 14 August is already 01:30 on the 15th in Rome (UTC+2 in summer).
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let late = try Self.instant(2026, 8, 14, 23, 30, in: utc)
        let rome = Self.calendar()
        let now = try Self.instant(2026, 8, 18, in: rome)

        let groups = HistoryGrouping.groups(
            for: [NoteHistory.Snapshot(date: late, text: "x\n")], now: now, calendar: rome
        )
        #expect(groups.map(\.title) == ["sabato 15 agosto"])
    }

    @Test func sameDaySnapshotsShareOneGroupAndAnotherDayStartsANewOne() throws {
        let calendar = Self.calendar()
        let now = try Self.instant(2026, 8, 18, 18, 0, in: calendar)
        let snapshots = [
            NoteHistory.Snapshot(date: try Self.instant(2026, 8, 18, 17, 0, in: calendar), text: "c\n"),
            NoteHistory.Snapshot(date: try Self.instant(2026, 8, 18, 9, 0, in: calendar), text: "b\n"),
            NoteHistory.Snapshot(date: try Self.instant(2026, 8, 5, 9, 0, in: calendar), text: "a\n"),
        ]

        let groups = HistoryGrouping.groups(for: snapshots, now: now, calendar: calendar)
        #expect(groups.map(\.title) == ["Oggi", "mercoledì 5 agosto"])
        #expect(groups.map(\.entries.count) == [2, 1])
    }

    @Test func theTimeIsPaddedAndReadInTheCalendarsZone() throws {
        let rome = Self.calendar()
        #expect(HistoryGrouping.time(for: try Self.instant(2026, 8, 18, 9, 5, in: rome), calendar: rome) == "09:05")
        #expect(HistoryGrouping.time(for: try Self.instant(2026, 8, 18, 0, 0, in: rome), calendar: rome) == "00:00")
        #expect(HistoryGrouping.time(for: try Self.instant(2026, 8, 18, 23, 59, in: rome), calendar: rome) == "23:59")

        // The same instant, read through another zone, is another wall-clock time.
        let instant = try Self.instant(2026, 8, 18, 9, 5, in: rome)
        #expect(HistoryGrouping.time(for: instant, calendar: Self.calendar("UTC")) == "07:05")
    }
}
