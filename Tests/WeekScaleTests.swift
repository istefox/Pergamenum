import Foundation
import Testing
@testable import Pergamenum

// The week and the month as the controller builds them (ADR-0013 §D4). Apart from
// `DayControllerTests`, which is about what the day view writes, and from
// `WeekPlanTests`, which is the arithmetic underneath with no vault in it.

/// Seven columns, anchored on the day the view was already showing, with the day's own
/// sources in it. The scale is a way of looking at the same anchor, not a second one.
@MainActor
@Test func theWeekScaleBuildsSevenColumnsAroundTheAnchor() async throws {
    let vault = try DayVault()
    try vault.write(emptyDailyNote, to: "Calendar/20260811.md")
    try vault.write("""
    ---
    date: 2026-08-11
    tags:
      - type-note
    ---

    - [ ] Sopralluogo pressa 4 >2026-08-11
    - [ ] Consegna disegni !2026-08-14
    """, to: "Attivita.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    dayController.scale = .week

    // 2026-08-11 is a Tuesday: the week runs Monday the 10th to Sunday the 16th.
    #expect(dayController.columns.count == 7)
    #expect(dayController.columns.first?.day == CalendarDate(iso: "2026-08-10"))
    #expect(dayController.columns.last?.day == CalendarDate(iso: "2026-08-16"))

    let tuesday = try #require(dayController.columns.first { $0.day == testDay })
    #expect(tuesday.hasNote, "la nota del giorno esiste e la colonna non la segnala")
    #expect(tuesday.entries.map(\.title) == ["Sopralluogo pressa 4"])

    let friday = try #require(dayController.columns.first { $0.day == CalendarDate(iso: "2026-08-14") })
    #expect(friday.entries.map(\.kind) == [.deadline])
    #expect(!friday.hasNote)
    vaultController.close()
}

/// A block written into the daily note shows up in the column for that day: the week
/// reads the same four sources the day does, from the same files.
@MainActor
@Test func aBlockWrittenOnTheDayReachesTheWeeksColumn() async throws {
    let vault = try DayVault()
    try vault.write(emptyDailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    let task = TaskParser.parse(line: "- [ ] Calcolo trasmissibilità", sourcePath: "x.md", lineIndex: 0)!
    _ = dayController.addBlock(from: task)
    dayController.scale = .week

    let tuesday = try #require(dayController.columns.first { $0.day == testDay })
    #expect(tuesday.entries.map(\.kind) == [.block])
    #expect(tuesday.entries.first?.timeText == "09:00")
    vaultController.close()
}

/// The month covers whole weeks, so it starts on a Monday and ends on a Sunday even
/// when that means showing the neighbouring months.
@MainActor
@Test func theMonthScaleCoversWholeWeeks() async throws {
    let vault = try DayVault()
    try vault.write(emptyDailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    dayController.scale = .month

    #expect(dayController.columns.count % 7 == 0)
    #expect(dayController.columns.first?.day == CalendarDate(iso: "2026-07-27"))
    #expect(dayController.columns.last?.day == CalendarDate(iso: "2026-09-06"))
    vaultController.close()
}

/// The navigators move by a unit of the scale, which is the whole reason `moveSpan`
/// exists: `Cmd+←` in the week has to move a week.
@MainActor
@Test func theNavigatorsFollowTheScale() async throws {
    let vault = try DayVault()
    try vault.write(emptyDailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, _) = try await makeController(vault: vault, store: store)

    dayController.moveSpan(by: 1)
    #expect(dayController.day == CalendarDate(iso: "2026-08-12"))

    dayController.scale = .week
    dayController.moveSpan(by: 1)
    #expect(dayController.day == CalendarDate(iso: "2026-08-19"))

    dayController.scale = .month
    dayController.moveSpan(by: -1)
    #expect(dayController.day == CalendarDate(iso: "2026-07-19"))
}

/// Going back to the day scale leaves the anchor where the week left it: one anchor,
/// three scales.
@MainActor
@Test func switchingBackToTheDayKeepsWhereTheWeekWas() async throws {
    let vault = try DayVault()
    try vault.write(emptyDailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, _) = try await makeController(vault: vault, store: store)

    dayController.scale = .week
    dayController.show(CalendarDate(iso: "2026-08-14")!)
    dayController.scale = .day

    #expect(dayController.day == CalendarDate(iso: "2026-08-14"))
    #expect(dayController.columns.isEmpty, "la scala giorno non ha colonne da tenere")
}
