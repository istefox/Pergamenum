import Foundation
import Testing
@testable import Pergamenum

private let day = CalendarDate(iso: "2026-08-11")!

// MARK: - Time block arithmetic

@Test func rendersTimesFromMinutesPastMidnight() {
    #expect(TimeBlock.timeText(0) == "00:00")
    #expect(TimeBlock.timeText(9 * 60) == "09:00")
    #expect(TimeBlock.timeText(14 * 60 + 30) == "14:30")
    #expect(TimeBlock.timeText(23 * 60 + 59) == "23:59")
}

@Test func snapsToTheNearestQuarterHour() {
    // Dragging should produce times a person would write down.
    #expect(TimeBlock.snap(0) == 0)
    #expect(TimeBlock.snap(7) == 0)
    #expect(TimeBlock.snap(8) == 15)
    #expect(TimeBlock.snap(541) == 540)
    #expect(TimeBlock.snap(-30) == 0)
}

@Test func detectsOverlappingBlocks() {
    let morning = TimeBlock(day: day, startMinutes: 540, durationMinutes: 60,
                            title: "A", sourceTaskID: nil, isPublished: false)
    let overlapping = TimeBlock(day: day, startMinutes: 570, durationMinutes: 60,
                                title: "B", sourceTaskID: nil, isPublished: false)
    let adjacent = TimeBlock(day: day, startMinutes: 600, durationMinutes: 60,
                             title: "C", sourceTaskID: nil, isPublished: false)
    let otherDay = TimeBlock(day: CalendarDate(iso: "2026-08-12")!, startMinutes: 570,
                             durationMinutes: 60, title: "D", sourceTaskID: nil, isPublished: false)

    #expect(morning.overlaps(overlapping))
    // Touching is not overlapping: a block ending at 10:00 and one starting at 10:00
    // are a normal back-to-back pair.
    #expect(!morning.overlaps(adjacent))
    #expect(!morning.overlaps(otherDay))
}

// MARK: - Timeline section

private let dailyNote = """
---
date: 2026-08-11
tags:
  - type-note
---

Sopralluogo in reparto stampaggio.

## Timeline

- 09:00-10:30 Sopralluogo pressa 4 [published]
- 14:00-15:00 Calcolo trasmissibilità

## Note correlate

- [[Curva di trasmissibilità]] — dati
"""

@Test func readsTheTimelineSection() {
    let blocks = TimeBlockSection.parse(from: dailyNote, day: day)
    #expect(blocks.count == 2)
    #expect(blocks[0].startMinutes == 540)
    #expect(blocks[0].durationMinutes == 90)
    #expect(blocks[0].title == "Sopralluogo pressa 4")
    #expect(blocks[0].isPublished)
    #expect(!blocks[1].isPublished)
}

@Test func stopsAtTheNextHeading() {
    // The bullet under "Note correlate" is a link, not a time block.
    let blocks = TimeBlockSection.parse(from: dailyNote, day: day)
    #expect(!blocks.contains { $0.title.contains("Curva") })
}

@Test func ignoresMalformedTimelineLines() {
    let note = """
    ## Timeline

    - 09:00 senza fine
    - 25:00-26:00 ore impossibili
    - 11:00-10:00 fine prima dell'inizio
    - 09:00-10:00 valido
    """
    let blocks = TimeBlockSection.parse(from: note, day: day)
    #expect(blocks.map(\.title) == ["valido"])
}

@Test func rewritesTheSectionInPlace() {
    let blocks = [
        TimeBlock(day: day, startMinutes: 600, durationMinutes: 60,
                  title: "Nuovo blocco", sourceTaskID: nil, isPublished: false),
    ]
    let updated = TimeBlockSection.write(blocks, into: dailyNote)

    #expect(updated.contains("- 10:00-11:00 Nuovo blocco"))
    #expect(!updated.contains("Sopralluogo pressa 4"))
    // Everything outside the section survives.
    #expect(updated.contains("Sopralluogo in reparto stampaggio."))
    #expect(updated.contains("## Note correlate"))
    #expect(updated.contains("[[Curva di trasmissibilità]]"))
}

@Test func createsTheSectionWhenTheNoteHasNone() {
    let note = "---\ndate: 2026-08-11\n---\n\nCorpo.\n"
    let blocks = [
        TimeBlock(day: day, startMinutes: 540, durationMinutes: 30,
                  title: "Primo", sourceTaskID: nil, isPublished: false),
    ]
    let updated = TimeBlockSection.write(blocks, into: note)
    #expect(updated.contains("## Timeline"))
    #expect(updated.contains("- 09:00-09:30 Primo"))
    #expect(updated.hasPrefix("---\ndate: 2026-08-11\n---\n\nCorpo.\n"))
}

@Test func writingNoBlocksToANoteWithoutASectionChangesNothing() {
    let note = "Corpo senza timeline.\n"
    #expect(TimeBlockSection.write([], into: note) == note)
}

@Test func removingTheLastBlockRemovesTheSection() {
    let updated = TimeBlockSection.write([], into: dailyNote)

    #expect(!updated.contains("## Timeline"))
    #expect(!updated.contains("Sopralluogo pressa 4"))
    // Everything the user wrote is still there, spaced as it was.
    #expect(updated.contains("Sopralluogo in reparto stampaggio.\n\n## Note correlate"))
    #expect(updated.contains("[[Curva di trasmissibilità]]"))
}

@Test func removingTheLastBlockOfATrailingSectionLeavesTheNoteClosed() {
    let note = "---\ndate: 2026-08-11\n---\n\nCorpo.\n\n## Timeline\n\n- 09:00-09:30 Primo\n"
    #expect(TimeBlockSection.write([], into: note) == "---\ndate: 2026-08-11\n---\n\nCorpo.\n")
}

@Test func removingTheLastBlockOfANoteThatIsOnlyASection() {
    #expect(TimeBlockSection.write([], into: "## Timeline\n\n- 09:00-09:30 Primo\n").isEmpty)
}

@Test func addingABlockBackRecreatesTheSection() {
    let emptied = TimeBlockSection.write([], into: dailyNote)
    let blocks = [
        TimeBlock(day: day, startMinutes: 600, durationMinutes: 60,
                  title: "Di nuovo", sourceTaskID: nil, isPublished: false),
    ]
    let refilled = TimeBlockSection.write(blocks, into: emptied)

    #expect(TimeBlockSection.parse(from: refilled, day: day).map(\.title) == ["Di nuovo"])
    #expect(refilled.contains("## Note correlate"))
}

@Test func roundTripsTheSection() {
    let original = TimeBlockSection.parse(from: dailyNote, day: day)
    let rewritten = TimeBlockSection.write(original, into: dailyNote)
    #expect(TimeBlockSection.parse(from: rewritten, day: day) == original)
}

@Test func keepsBlocksSortedByStartTime() {
    let blocks = [
        TimeBlock(day: day, startMinutes: 840, durationMinutes: 60, title: "Dopo",
                  sourceTaskID: nil, isPublished: false),
        TimeBlock(day: day, startMinutes: 540, durationMinutes: 60, title: "Prima",
                  sourceTaskID: nil, isPublished: false),
    ]
    let written = TimeBlockSection.write(blocks, into: "## Timeline")
    let firstIndex = written.range(of: "Prima")?.lowerBound
    let secondIndex = written.range(of: "Dopo")?.lowerBound
    #expect(firstIndex != nil && secondIndex != nil && firstIndex! < secondIndex!)
}

@Test(arguments: [("09:00", 540), ("00:00", 0), ("23:59", 1439)])
func parsesValidTimes(_ testCase: (text: String, minutes: Int)) {
    #expect(TimeBlockSection.minutes(from: testCase.text) == testCase.minutes)
}

@Test(arguments: ["24:00", "09:60", "9:00:00", "nove", "", "0900"])
func rejectsInvalidTimes(_ text: String) {
    #expect(TimeBlockSection.minutes(from: text) == nil)
}

// MARK: - Day ranges

@Test func buildsADayRangeOfExactlyOneDay() throws {
    let range = try #require(EventKitStore.dayRange(day))
    let seconds = range.end.timeIntervalSince(range.start)
    // 23 or 25 hours on the two DST days; every other day is 24.
    #expect(seconds >= 23 * 3600 && seconds <= 25 * 3600)
}

@Test func buildsATimeOnADay() throws {
    let date = try #require(EventKitStore.date(day, hour: 9, minute: 30))
    let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    #expect(components.year == 2026)
    #expect(components.month == 8)
    #expect(components.day == 11)
    #expect(components.hour == 9)
    #expect(components.minute == 30)
}

// MARK: - Access states

@Test func treatsWriteOnlyAccessAsDenied() {
    // Write-only lets an app add events but not read them, which would show an empty
    // timeline beside a full calendar. Reporting it as denied is the honest state.
    #expect(!CalendarAccess.denied.isGranted)
    #expect(!CalendarAccess.notDetermined.isGranted)
    #expect(CalendarAccess.granted.isGranted)
}

// MARK: - Reminder scheduling

private func task(_ line: String) -> TaskItem {
    TaskParser.parse(line: line, sourcePath: "01 Progetti/Nota.md", lineIndex: 0)!
}

private let beforeReminders = EventKitStore.date(CalendarDate(iso: "2026-08-10")!, hour: 0, minute: 0)!

@Test func schedulesOnlyOpenTasksWithAFutureReminder() {
    let tasks = [
        task("- [ ] Con promemoria @remind(2026-08-15 09:00)"),
        task("- [x] Fatto @remind(2026-08-15 09:00)"),
        task("- [-] Annullato @remind(2026-08-15 09:00)"),
        task("- [ ] Senza promemoria"),
        task("- [ ] Promemoria passato @remind(2026-08-01 09:00)"),
    ]
    let requests = ReminderScheduler.requests(for: tasks, after: beforeReminders)

    // A completed or cancelled task must not still ring, and a past reminder is not
    // scheduled at all.
    #expect(requests.count == 1)
    #expect(requests[0].content.title == "Con promemoria")
}

@Test func aRescheduledTaskStillRings() {
    // `- [>]` means moved, not done.
    let requests = ReminderScheduler.requests(
        for: [task("- [>] Rimandato @remind(2026-08-15 09:00)")], after: beforeReminders
    )
    #expect(requests.count == 1)
}

@Test func theNotificationNamesItsSourceNoteAndCarriesItsRoute() throws {
    let requests = ReminderScheduler.requests(
        for: [task("- [ ] Richiamare @remind(2026-08-15 09:00)")], after: beforeReminders
    )
    let request = try #require(requests.first)
    #expect(request.content.body == "Nota")

    let route = try #require(request.content.userInfo["route"] as? String)
    // Tapping it must open the note it came from, not just the app.
    #expect(URL(string: route).flatMap(PergamenumRoute.init) == .note(path: "01 Progetti/Nota.md"))
}

@Test func identifiersAreStablePerTask() {
    let item = task("- [ ] Con promemoria @remind(2026-08-15 09:00)")
    let first = ReminderScheduler.requests(for: [item], after: beforeReminders)
    let second = ReminderScheduler.requests(for: [item], after: beforeReminders)
    // Stable ids are what let a rescan replace rather than duplicate.
    #expect(first.first?.identifier == second.first?.identifier)
    #expect(first.first?.identifier == item.id)
}

// MARK: - Access state

/// `EventKitStore` can be constructed in tests: reading the authorization status never
/// opens a dialog, and nothing here touches the store's contents. Everything below is
/// about the state the app is in *before* anyone has said yes, which is exactly the
/// state that was never checked.

@MainActor
@Test func aStoreThatHasNeverBeenAskedCanStillBeAsked() {
    let store = EventKitStore()
    // Whatever this machine's real answer is, "can still be asked" must agree with it
    // rather than with a guess: a button offering to ask is only honest while asking
    // can still produce a dialog.
    let expected = store.eventAccess == .notDetermined || store.reminderAccess == .notDetermined
    #expect(store.canStillBeAsked == expected)
}

@MainActor
@Test func aDeniedStoreIsNeverOfferedTheRequestAgain() {
    let store = EventKitStore()
    if store.eventAccess == .denied, store.reminderAccess == .denied {
        // macOS asks once. Offering it again would be a button that does nothing.
        #expect(!store.canStillBeAsked)
    }
}

@MainActor
@Test func noExternalChangeHasBeenSeenAtBirth() {
    // The day view reloads on a change; a store that claimed one at launch would make
    // it reload twice on every start.
    #expect(EventKitStore().changeCount == 0)
}

@Test func thePrivacyPaneURLNamesTheRightPane() {
    // The two entities land on two different panes, and sending a user refused on
    // Reminders to the Calendar pane is the kind of thing nobody notices until they
    // are already lost in Impostazioni di Sistema.
    #expect(EventKitStore.privacyPaneURL(for: .event)?.absoluteString
        == "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
    #expect(EventKitStore.privacyPaneURL(for: .reminder)?.absoluteString
        == "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
}

// MARK: - All-day events

private func event(_ title: String, allDay: Bool, hour: Int) -> CalendarEvent {
    let start = EventKitStore.date(day, hour: hour, minute: 0)!
    return CalendarEvent(
        id: title, title: title, start: start, end: start.addingTimeInterval(3600),
        isAllDay: allDay, calendarTitle: "Personale", isEditable: true
    )
}

@Test func anAllDayEventIsKeptOutOfTheHourGrid() {
    // Found on a real calendar: the grid starts at 06:00 and places an entry by its
    // start time, so an all-day event at midnight was drawn above the first line and
    // vanished. Holidays and deadlines were missing from every day that had them.
    let split = [
        event("Assunzione di Maria", allDay: true, hour: 0),
        event("Qualifiche", allDay: false, hour: 15),
    ].splitByAllDay

    #expect(split.allDay.map(\.title) == ["Assunzione di Maria"])
    #expect(split.timed.map(\.title) == ["Qualifiche"])
}

@Test func aDayWithNoAllDayEventHasAnEmptyStrip() {
    // The strip is hidden on an empty list rather than drawn as a blank band.
    #expect([event("Sprint", allDay: false, hour: 11)].splitByAllDay.allDay.isEmpty)
}

@Test func everyEventLandsOnExactlyOneSideOfTheSplit() {
    let events = [
        event("A", allDay: true, hour: 0), event("B", allDay: false, hour: 9),
        event("C", allDay: true, hour: 0), event("D", allDay: false, hour: 18),
    ]
    let split = events.splitByAllDay
    // Neither dropped nor counted twice: the bug being guarded against was a whole
    // category silently disappearing.
    #expect(split.allDay.count + split.timed.count == events.count)
}
