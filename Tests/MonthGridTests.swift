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
