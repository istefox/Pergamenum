import Foundation
import Testing
@testable import Pergamenum

// The arithmetic and the composition behind the week and the month scales (ADR-0013
// §D4). Pure, and checked here rather than by looking at a grid: a calendar that is
// wrong on one month in twelve is not something to notice by looking at it.

// MARK: - The days a scale covers

@Test func theWeekStartsOnMondayWhicheverDayItIsAskedFor() {
    let wednesday = CalendarDate(iso: "2026-08-12")!
    let sunday = CalendarDate(iso: "2026-08-16")!

    for day in [wednesday, sunday] {
        let week = WeekPlan.week(containing: day)
        #expect(week.count == 7)
        #expect(week.first == CalendarDate(iso: "2026-08-10"))
        #expect(week.last == CalendarDate(iso: "2026-08-16"))
        #expect(week.contains(day))
    }
}

@Test func theMonthKeepsTheNeighbouringDaysInsteadOfLeavingHoles() {
    // August 2026 opens on a Saturday and closes on a Monday, so it needs six rows and
    // both ends run into another month.
    let weeks = WeekPlan.monthWeeks(of: CalendarDate(iso: "2026-08-20")!)

    #expect(weeks.count == 6)
    #expect(weeks.allSatisfy { $0.count == 7 })
    #expect(weeks.first?.first == CalendarDate(iso: "2026-07-27"))
    #expect(weeks.last?.last == CalendarDate(iso: "2026-09-06"))

    // Every day of the month itself is in there exactly once.
    let august = weeks.flatMap { $0 }.filter { $0.month == 8 }
    #expect(august.count == 31)
    #expect(Set(august).count == 31)
}

@Test func aShortMonthTakesFiveRows() {
    let weeks = WeekPlan.monthWeeks(of: CalendarDate(iso: "2026-02-14")!)

    #expect(weeks.count == 5)
    #expect(weeks.first?.first == CalendarDate(iso: "2026-01-26"))
    #expect(weeks.last?.last == CalendarDate(iso: "2026-03-01"))
}

// MARK: - What a day holds

private let planDay = CalendarDate(iso: "2026-08-20")!

private func event(_ title: String, hour: Int, allDay: Bool = false) -> CalendarEvent {
    let start = EventKitStore.date(planDay, hour: hour, minute: 0)!
    return CalendarEvent(
        id: title, title: title, start: start, end: start.addingTimeInterval(3600),
        isAllDay: allDay, calendarTitle: "Lavoro", isEditable: true
    )
}

private func task(_ line: String, lineIndex: Int = 0) -> TaskItem {
    TaskParser.parse(line: line, sourcePath: "Note/lavoro.md", lineIndex: lineIndex)!
}

@Test func theFourSourcesComeInOneOrder() {
    let entries = WeekPlan.entries(
        on: planDay,
        events: [event("Sopralluogo", hour: 11), event("Riunione", hour: 9)],
        blocks: [TimeBlock(
            day: planDay, startMinutes: 15 * 60, durationMinutes: 60,
            title: "Disegno presse", sourceTaskID: nil, isPublished: false
        )],
        tasks: [
            task("- [ ] Rivedere capitolato >2026-08-20"),
            task("- [ ] Consegna disegni !2026-08-20", lineIndex: 1),
        ]
    )

    #expect(entries.map(\.kind) == [.event, .event, .block, .task, .deadline])
    // Events by their hour, and the hour is the prefix the row shows.
    #expect(entries[0].title == "Riunione")
    #expect(entries[0].timeText == "09:00")
    #expect(entries[2].timeText == "15:00")
    #expect(entries[3].title == "Rivedere capitolato")
    #expect(entries[4].title == "Consegna disegni")
}

@Test func anAllDayEventComesBeforeTheHoursAndCarriesNoTime() {
    let entries = WeekPlan.entries(
        on: planDay,
        events: [event("Riunione", hour: 9), event("Ferie", hour: 0, allDay: true)],
        blocks: [],
        tasks: []
    )

    #expect(entries.map(\.title) == ["Ferie", "Riunione"])
    #expect(entries[0].timeText == nil)
}

@Test func aTaskScheduledAndDueTheSameDayIsOneRow() {
    let entries = WeekPlan.entries(
        on: planDay,
        events: [],
        blocks: [],
        tasks: [task("- [ ] Capitolato >2026-08-20 !2026-08-20")]
    )

    // Two rows for one line of markdown would make the week say the day holds more
    // than it does.
    #expect(entries.count == 1)
    #expect(entries[0].kind == .task)
}

@Test func aDayOnlyShowsWhatBelongsToIt() {
    let entries = WeekPlan.entries(
        on: planDay,
        events: [],
        blocks: [],
        tasks: [
            task("- [ ] Altro giorno >2026-08-21"),
            task("- [ ] Scadenza altrove !2026-08-25", lineIndex: 1),
        ]
    )

    #expect(entries.isEmpty)
}

@Test func aTaskRowKnowsWhichNoteToOpenAndAnEventDoesNot() {
    let entries = WeekPlan.entries(
        on: planDay,
        events: [event("Riunione", hour: 9)],
        blocks: [],
        tasks: [task("- [ ] Capitolato >2026-08-20")]
    )

    #expect(entries[0].sourcePath == nil)
    #expect(entries[1].sourcePath == "Note/lavoro.md")
    // And the line inside it, so the click lands on the task rather than on the note.
    #expect(entries[0].lineIndex == nil)
    #expect(entries[1].lineIndex == 0)
}

// MARK: - What a column cannot show

@Test func aFullColumnSaysHowManyAreLeft() {
    let entries = (0..<11).map { index in
        WeekEntry(id: "\(index)", kind: .task, title: "t\(index)", timeText: nil,
                  minutes: nil, sourcePath: nil, lineIndex: nil)
    }

    let split = WeekPlan.split(entries, limit: 4)
    #expect(split.shown.count == 4)
    #expect(split.hidden == 7)
}

@Test func aColumnThatFitsSaysNothing() {
    let entries = [WeekEntry(id: "a", kind: .task, title: "t", timeText: nil,
                             minutes: nil, sourcePath: nil, lineIndex: nil)]

    // Exactly at the limit is not an overflow: "altri 0" is a row about nothing.
    #expect(WeekPlan.split(entries, limit: 1).hidden == 0)
    #expect(WeekPlan.split(entries, limit: 4).hidden == 0)
    #expect(WeekPlan.split([], limit: 4).shown.isEmpty)
}

// MARK: - The range fetch

@Test func aMultiDayEventLandsOnEveryDayItCovers() {
    let start = EventKitStore.date(CalendarDate(iso: "2026-08-18")!, hour: 14, minute: 0)!
    let end = EventKitStore.date(CalendarDate(iso: "2026-08-20")!, hour: 10, minute: 0)!
    let spanning = CalendarEvent(
        id: "fiera", title: "Fiera", start: start, end: end,
        isAllDay: false, calendarTitle: "Lavoro", isEditable: true
    )

    let days = EventKitStore.bucketed(
        [spanning],
        from: CalendarDate(iso: "2026-08-17")!,
        through: CalendarDate(iso: "2026-08-23")!
    )

    #expect(days[CalendarDate(iso: "2026-08-18")!]?.count == 1)
    #expect(days[CalendarDate(iso: "2026-08-19")!]?.count == 1)
    #expect(days[CalendarDate(iso: "2026-08-20")!]?.count == 1)
    #expect(days[CalendarDate(iso: "2026-08-17")!] == nil)
    #expect(days[CalendarDate(iso: "2026-08-21")!] == nil)
}

@Test func anEventIsClippedToTheRangeAsked() {
    let start = EventKitStore.date(CalendarDate(iso: "2026-08-18")!, hour: 9, minute: 0)!
    let end = EventKitStore.date(CalendarDate(iso: "2026-08-25")!, hour: 9, minute: 0)!
    let long = CalendarEvent(
        id: "cantiere", title: "Cantiere", start: start, end: end,
        isAllDay: false, calendarTitle: "Lavoro", isEditable: true
    )

    let days = EventKitStore.bucketed(
        [long],
        from: CalendarDate(iso: "2026-08-19")!,
        through: CalendarDate(iso: "2026-08-21")!
    )

    #expect(Set(days.keys) == Set([
        CalendarDate(iso: "2026-08-19")!,
        CalendarDate(iso: "2026-08-20")!,
        CalendarDate(iso: "2026-08-21")!,
    ]))
}

@Test func anEventEndingAtMidnightBelongsToTheDayBefore() {
    let start = EventKitStore.date(CalendarDate(iso: "2026-08-20")!, hour: 22, minute: 0)!
    let end = EventKitStore.date(CalendarDate(iso: "2026-08-21")!, hour: 0, minute: 0)!
    let late = CalendarEvent(
        id: "turno", title: "Turno", start: start, end: end,
        isAllDay: false, calendarTitle: "Lavoro", isEditable: true
    )

    let days = EventKitStore.bucketed(
        [late],
        from: CalendarDate(iso: "2026-08-20")!,
        through: CalendarDate(iso: "2026-08-22")!
    )

    #expect(Set(days.keys) == Set([CalendarDate(iso: "2026-08-20")!]))
}

// MARK: - The part of an event a day covers (ADR-0075 §D5)

/// A fixed zone, so the projection's minutes do not depend on the machine running it.
private let rome: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
    return calendar
}()

private func romeDate(_ iso: String, _ hour: Int, _ minute: Int = 0) -> Date {
    let day = CalendarDate(iso: iso)!
    return rome.date(from: DateComponents(year: day.year, month: day.month, day: day.day,
                                          hour: hour, minute: minute))!
}

private func romeEvent(from start: Date, to end: Date, allDay: Bool = false) -> CalendarEvent {
    CalendarEvent(id: "evento", title: "Evento", start: start, end: end,
                  isAllDay: allDay, calendarTitle: "Lavoro", isEditable: true)
}

private func projection(_ event: CalendarEvent, on iso: String) -> DayProjection {
    event.projection(on: CalendarDate(iso: iso)!, calendar: rome)
}

@Test func aThreeDayEventIsProjectedAsThePartEachDayCovers() {
    let fair = romeEvent(from: romeDate("2026-08-17", 9), to: romeDate("2026-08-19", 11))

    #expect(projection(fair, on: "2026-08-17") == .timed(startMinute: 540, endMinute: 1440))
    #expect(projection(fair, on: "2026-08-18") == .allDay)
    #expect(projection(fair, on: "2026-08-19") == .timed(startMinute: 0, endMinute: 660))
    #expect(projection(fair, on: "2026-08-20") == DayProjection.none)
}

@Test func aDinnerPastMidnightIsSplitAtMidnight() {
    let dinner = romeEvent(from: romeDate("2026-08-20", 22), to: romeDate("2026-08-21", 1))

    #expect(projection(dinner, on: "2026-08-20") == .timed(startMinute: 1320, endMinute: 1440))
    #expect(projection(dinner, on: "2026-08-21") == .timed(startMinute: 0, endMinute: 60))
}

@Test func anEventEndingAtMidnightIsNotOnTheNextDay() {
    let late = romeEvent(from: romeDate("2026-08-20", 22), to: romeDate("2026-08-21", 0))

    #expect(projection(late, on: "2026-08-21") == DayProjection.none)
}

@Test func midnightToMidnightIsAllDay() {
    let whole = romeEvent(from: romeDate("2026-08-20", 0), to: romeDate("2026-08-21", 0))

    #expect(projection(whole, on: "2026-08-20") == .allDay)
}

@Test func aFlaggedAllDayEventIsAllDayOnEveryDayItTouches() {
    let holiday = romeEvent(from: romeDate("2026-08-14", 0), to: romeDate("2026-08-15", 23, 59),
                            allDay: true)

    #expect(projection(holiday, on: "2026-08-14") == .allDay)
    #expect(projection(holiday, on: "2026-08-15") == .allDay)
    #expect(projection(holiday, on: "2026-08-16") == DayProjection.none)
}

@Test func aZeroLengthEventIsAMomentOnTheDay() {
    let reminder = romeEvent(from: romeDate("2026-08-20", 10), to: romeDate("2026-08-20", 10))

    #expect(projection(reminder, on: "2026-08-20") == .timed(startMinute: 600, endMinute: 600))
}

/// The clocks go back an hour on 2026-10-25 in Rome: the day is 25 hours long, and the
/// projection speaks clock minutes, not elapsed ones.
@Test func aDSTDayIsProjectedInClockMinutes() {
    let morning = romeEvent(from: romeDate("2026-10-25", 0), to: romeDate("2026-10-25", 12))

    #expect(projection(morning, on: "2026-10-25") == .timed(startMinute: 0, endMinute: 720))
}

@Test func theMiddleDayOfAMultiDayEventGoesInTheAllDayStrip() {
    let fair = romeEvent(from: romeDate("2026-08-17", 9), to: romeDate("2026-08-19", 11))

    let tuesday = [fair].projected(on: CalendarDate(iso: "2026-08-18")!, calendar: rome)

    #expect(tuesday.allDay.map(\.id) == ["evento"])
    #expect(tuesday.timed.isEmpty)
}

/// The week plan reads the same projection: on Tuesday the event is all-day and sorted
/// first, on Wednesday it starts at midnight rather than at Monday's 09:00 (R-10).
@Test func theWeekPlacesAMultiDayEventAtThePartEachDayCovers() {
    let start = EventKitStore.date(CalendarDate(iso: "2026-08-17")!, hour: 9, minute: 0)!
    let end = EventKitStore.date(CalendarDate(iso: "2026-08-19")!, hour: 11, minute: 0)!
    let fair = CalendarEvent(id: "fiera", title: "Fiera", start: start, end: end,
                             isAllDay: false, calendarTitle: "Lavoro", isEditable: true)
    let meeting = event("Riunione", hour: 9)

    let tuesday = WeekPlan.entries(on: CalendarDate(iso: "2026-08-18")!, events: [meeting, fair],
                                   blocks: [], tasks: [])
    #expect(tuesday.first?.title == "Fiera")
    #expect(tuesday.first?.minutes == nil)

    let wednesday = WeekPlan.entries(on: CalendarDate(iso: "2026-08-19")!, events: [fair],
                                     blocks: [], tasks: [])
    #expect(wednesday.first?.minutes == 0)
    #expect(wednesday.first?.timeText == "00:00")
}

// MARK: - A deadline is red only once it has passed (ADR-0075 §D6)

private func deadline(_ line: String, today iso: String) throws -> WeekEntry {
    let entries = WeekPlan.entries(on: planDay, events: [], blocks: [], tasks: [task(line)],
                                   today: CalendarDate(iso: iso)!)
    return try #require(entries.first { $0.kind == .deadline })
}

@Test func aPassedDeadlineOnAnOpenTaskIsOverdue() throws {
    let entry = try deadline("- [ ] Consegna disegni !2026-08-20", today: "2026-08-21")

    #expect(entry.isOverdue)
    #expect(entry.token == .taskOverdue)
}

@Test func aDeadlineNotYetPassedIsNotRed() throws {
    for today in ["2026-08-20", "2026-08-19"] {
        let entry = try deadline("- [ ] Consegna disegni !2026-08-20", today: today)
        #expect(!entry.isOverdue)
        #expect(entry.token == .textSecondary)
    }
}

@Test func aDoneTaskIsNeverOverdue() throws {
    let entry = try deadline("- [x] Consegna disegni !2026-08-20", today: "2026-08-21")

    #expect(!entry.isOverdue)
}

@Test func theOtherKindsKeepTheirOwnColour() {
    let entries = WeekPlan.entries(
        on: planDay,
        events: [event("Riunione", hour: 9)],
        blocks: [TimeBlock(day: planDay, startMinutes: 900, durationMinutes: 60,
                           title: "Disegno", sourceTaskID: nil, isPublished: false)],
        tasks: [task("- [ ] Rivedere capitolato >2026-08-20")],
        today: CalendarDate(iso: "2026-08-25")!
    )

    #expect(entries.map(\.kind) == [.event, .block, .task])
    for entry in entries {
        #expect(entry.token == entry.kind.token)
    }
}

// MARK: - The scale itself

@Test func eachScaleMovesByItsOwnUnit() {
    let day = CalendarDate(iso: "2026-08-20")!

    #expect(DayScale.day.anchor(day, movedBy: 1) == CalendarDate(iso: "2026-08-21"))
    #expect(DayScale.week.anchor(day, movedBy: -1) == CalendarDate(iso: "2026-08-13"))
    #expect(DayScale.month.anchor(day, movedBy: 1) == CalendarDate(iso: "2026-09-20"))
    // The last of a month into a shorter one is clamped, not skipped.
    #expect(DayScale.month.anchor(CalendarDate(iso: "2026-08-31")!, movedBy: 1)
        == CalendarDate(iso: "2026-09-30"))
}

// MARK: - Landing on the line

private let jumpNote = """
---
date: 2026-08-20
tags:
  - type-note
---

Prima riga.

## Attività

- [ ] Rivedere capitolato >2026-08-20
- [ ] Chiamare Ceramiche >2026-08-20
"""

@Test func aLineIsFoundByItsNumber() throws {
    let range = try #require(NoteJump.lineRange(10, in: jumpNote))
    #expect(jumpNote[range] == "- [ ] Rivedere capitolato >2026-08-20")

    // The first line and the last one, which are where an off-by-one shows up.
    #expect(jumpNote[try #require(NoteJump.lineRange(0, in: jumpNote))] == "---")
    #expect(jumpNote[try #require(NoteJump.lineRange(11, in: jumpNote))]
        == "- [ ] Chiamare Ceramiche >2026-08-20")
}

@Test func aLineThatIsNotThereAnyMoreIsNotGuessed() {
    // The index is a snapshot: a note edited since the scan can be shorter than it was,
    // and answering with the end of the file would call that a hit.
    #expect(NoteJump.lineRange(99, in: jumpNote) == nil)
    #expect(NoteJump.lineRange(-1, in: jumpNote) == nil)
}

@Test func theOrdinalIsTheSectionTheLineSitsIn() throws {
    // `## Attività` is the note's only heading, so a task under it is under entry zero
    // and the prose above it has nothing to be under - which is also zero, and that is
    // the reading view scrolling to the top rather than to a section it has no way to
    // name.
    let inSection = try #require(NoteJump.lineRange(10, in: jumpNote))
    #expect(NoteJump.ordinal(of: inSection.lowerBound, in: jumpNote) == 0)

    let twoSections = jumpNote + "\n\n## Scadenze\n\n- [ ] Consegna !2026-08-21"
    let underTheSecond = try #require(NoteJump.lineRange(15, in: twoSections))
    #expect(twoSections[underTheSecond] == "- [ ] Consegna !2026-08-21")
    #expect(NoteJump.ordinal(of: underTheSecond.lowerBound, in: twoSections) == 1)
}
