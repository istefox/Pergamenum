import Foundation
import Testing
@testable import Pergamenum

private func date(_ iso: String) -> CalendarDate { CalendarDate(iso: iso)! }

@Test func aMonthStartsOnTheRightWeekday() {
    // 1 August 2026 is a Saturday, so the first row holds five empty cells.
    let weeks = MonthGrid.weeks(of: date("2026-08-11"))
    let first = weeks[0]
    #expect(first.prefix(5).allSatisfy { $0 == nil })
    #expect(first[5] == date("2026-08-01"))
    #expect(first[6] == date("2026-08-02"))
}

@Test func everyDayOfTheMonthAppearsExactlyOnce() {
    let days = MonthGrid.weeks(of: date("2026-02-10")).flatMap { $0 }.compactMap { $0 }
    #expect(days.count == 28)
    #expect(days.first == date("2026-02-01"))
    #expect(days.last == date("2026-02-28"))
    #expect(Set(days).count == 28)
}

@Test func aLeapFebruaryHasItsTwentyNinth() {
    let days = MonthGrid.weeks(of: date("2028-02-10")).flatMap { $0 }.compactMap { $0 }
    #expect(days.count == 29)
    #expect(days.last == date("2028-02-29"))
}

@Test func everyRowIsAFullWeek() {
    for month in 1...12 {
        let weeks = MonthGrid.weeks(of: CalendarDate(year: 2026, month: month, day: 1)!)
        #expect(weeks.allSatisfy { $0.count == 7 })
    }
}

@Test func noDayFromAnotherMonthLeaksIn() {
    let days = MonthGrid.weeks(of: date("2026-08-11")).flatMap { $0 }.compactMap { $0 }
    #expect(days.allSatisfy { $0.month == 8 && $0.year == 2026 })
}

// MARK: - Paging

@Test func pagingForwardCrossesTheYear() {
    #expect(MonthGrid.month(date("2026-11-15"), offsetBy: 3) == date("2027-02-15"))
}

@Test func pagingBackCrossesTheYear() {
    #expect(MonthGrid.month(date("2026-02-15"), offsetBy: -3) == date("2025-11-15"))
}

@Test func pagingFromTheThirtyFirstLandsOnTheLastDayOfAShorterMonth() {
    // Not the 1st of the month after, which is what a naive date arithmetic gives.
    #expect(MonthGrid.month(date("2026-01-31"), offsetBy: 1) == date("2026-02-28"))
    #expect(MonthGrid.month(date("2026-03-31"), offsetBy: 1) == date("2026-04-30"))
}

@Test func pagingIntoALeapFebruaryKeepsTheTwentyNinth() {
    #expect(MonthGrid.month(date("2028-01-31"), offsetBy: 1) == date("2028-02-29"))
}

@Test func pagingByZeroChangesNothing() {
    #expect(MonthGrid.month(date("2026-08-11"), offsetBy: 0) == date("2026-08-11"))
}

// MARK: - Identities the view draws by (ADR-0075 §D7)

/// The blanks at either end of a month all hold nil, and an identity drawn from the
/// date made them one view; every cell is its own position now.
@Test(arguments: ["2026-09-01", "2026-02-01"])
func everyCellOfTheGridHasItsOwnIdentity(_ iso: String) {
    let month = date(iso)
    let cells = MonthGrid.cells(of: month).flatMap { $0 }

    #expect(cells.contains { $0.date == nil })
    #expect(Set(cells.map(\.id)).count == cells.count)
    #expect(cells.map(\.date) == MonthGrid.weeks(of: month).flatMap { $0 })
}

/// Tuesday and Wednesday are both «M».
@Test func theSevenWeekdayHeadersAreSevenIdentities() {
    let headers = MonthGrid.weekdayHeaders

    #expect(Set(headers.map(\.id)).count == 7)
    #expect(headers.map(\.initial) == ["L", "M", "M", "G", "V", "S", "D"])
}

// MARK: - PG-263: the leading blanks come from `DateEntry.weekday(of:)`

/// `MonthGrid` used to carry its own weekday helper; it now asks `DateEntry`. Checked against a
/// calendar built independently here, for every month of six years, so a helper that is wrong
/// on one month in twelve cannot hide (`(coverage)`).
@Test func theFirstCellOfEveryMonthSitsInTheColumnOfItsWeekdayMondayFirst() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    for year in 2024...2029 {
        for month in 1...12 {
            let first = try #require(CalendarDate(year: year, month: month, day: 1))
            let noon = try #require(calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)))
            // `Calendar` numbers Sunday 1; Monday-first column is (weekday + 5) % 7.
            let column = (calendar.component(.weekday, from: noon) + 5) % 7

            let row = MonthGrid.weeks(of: first)[0]
            #expect(row.firstIndex { $0 != nil } == column, "\(year)-\(month)")
            #expect(row[column] == first, "\(year)-\(month)")
        }
    }
}
