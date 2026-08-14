import Foundation
import Testing
@testable import Pergamenum

/// A `CalendarStore` that never touches EventKit.
///
/// EventKit needs a permission dialog only a person can answer, which is exactly why
/// the protocol exists: everything this app does around it is ordinary logic and is
/// tested here.
@MainActor
private final class StubCalendarStore: CalendarStore {
    var eventAccess: CalendarAccess = .granted
    var reminderAccess: CalendarAccess = .granted
    var writableCalendarTitles: [String] = ["Pergamenum", "Lavoro"]

    private(set) var createdEvents: [CalendarEvent] = []
    private(set) var completedCalls: [(id: String, completed: Bool)] = []
    var storedReminders: [CalendarReminder] = []
    /// When set, every write fails with it.
    var failure: CalendarError?

    func requestAccess() async {}

    /// The real store fetches reminders here; this one already has them.
    func refreshReminders(on day: CalendarDate) async {}

    func events(on day: CalendarDate) -> [CalendarEvent] { createdEvents }

    func reminders(dueOn day: CalendarDate) -> [CalendarReminder] {
        storedReminders.filter { $0.due == day }
    }

    @discardableResult
    func createEvent(title: String, start: Date, end: Date, calendarTitle: String?) throws -> CalendarEvent {
        if let failure { throw failure }
        let event = CalendarEvent(
            id: "event-\(createdEvents.count)", title: title, start: start, end: end,
            isAllDay: false, calendarTitle: calendarTitle ?? "Predefinito", isEditable: true
        )
        createdEvents.append(event)
        return event
    }

    @discardableResult
    func createReminder(title: String, due: CalendarDate?, listTitle: String?) throws -> CalendarReminder {
        if let failure { throw failure }
        let reminder = CalendarReminder(
            id: "reminder-\(storedReminders.count)", title: title, due: due,
            isCompleted: false, listTitle: listTitle ?? "Predefinito"
        )
        storedReminders.append(reminder)
        return reminder
    }

    func setCompleted(_ completed: Bool, reminderID: String) throws {
        if let failure { throw failure }
        completedCalls.append((reminderID, completed))
        storedReminders = storedReminders.map { reminder in
            var copy = reminder
            if copy.id == reminderID { copy.isCompleted = completed }
            return copy
        }
    }
}

private struct DayVault: ~Copyable {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-day-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    func write(_ contents: String, to relativePath: String) throws {
        let url = root.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }
}

private let day = CalendarDate(iso: "2026-08-11")!

private let dailyNote = """
---
date: 2026-08-11
tags:
  - type-note
---

Sopralluogo in reparto stampaggio.
"""

@MainActor
private func makeController(
    vault: borrowing DayVault,
    store: StubCalendarStore
) async throws -> (DayController, VaultController) {
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)
    controller.openNote(at: "Calendar/20260811.md")

    let day = DayController(store: store, vault: controller)
    day.show(CalendarDate(iso: "2026-08-11")!)
    return (day, controller)
}

@MainActor
@Test func turnsATaskIntoABlockAndWritesItIntoTheNote() async throws {
    let vault = try DayVault()
    try vault.write(dailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    let task = TaskParser.parse(line: "- [ ] Sopralluogo pressa 4", sourcePath: "x.md", lineIndex: 0)!
    let block = try #require(dayController.addBlock(from: task))

    #expect(block.startMinutes == 9 * 60)
    #expect(block.durationMinutes == TimeBlock.defaultDuration)
    #expect(!block.isPublished)

    // The plan lives in the note, so it survives this app (SPEC §8.3).
    let onDisk = try String(contentsOf: vault.root.appending(path: "Calendar/20260811.md"), encoding: .utf8)
    #expect(onDisk.contains("## Timeline"))
    #expect(onDisk.contains("- 09:00-09:30 Sopralluogo pressa 4"))
    #expect(onDisk.contains("Sopralluogo in reparto stampaggio."))
    vaultController.close()
}

@MainActor
@Test func placesASecondBlockAfterTheFirstRatherThanOnTopOfIt() async throws {
    let vault = try DayVault()
    try vault.write(dailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    let first = TaskParser.parse(line: "- [ ] Primo", sourcePath: "x.md", lineIndex: 0)!
    let second = TaskParser.parse(line: "- [ ] Secondo", sourcePath: "x.md", lineIndex: 1)!
    _ = dayController.addBlock(from: first)
    let block = try #require(dayController.addBlock(from: second))

    // Two blocks at the same time say nothing about what the day looks like.
    #expect(block.startMinutes == 9 * 60 + TimeBlock.defaultDuration)
    #expect(dayController.blocks.count == 2)
    vaultController.close()
}

@MainActor
@Test func publishingWritesTheEventAndMarksTheBlock() async throws {
    let vault = try DayVault()
    try vault.write(dailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    let task = TaskParser.parse(line: "- [ ] Calcolo", sourcePath: "x.md", lineIndex: 0)!
    let block = try #require(dayController.addBlock(from: task))

    #expect(dayController.publish(block, toCalendarTitled: "Pergamenum"))
    #expect(store.createdEvents.count == 1)
    #expect(store.createdEvents[0].title == "Calcolo")
    #expect(store.createdEvents[0].calendarTitle == "Pergamenum")

    let onDisk = try String(contentsOf: vault.root.appending(path: "Calendar/20260811.md"), encoding: .utf8)
    #expect(onDisk.contains("[published]"))
    vaultController.close()
}

@MainActor
@Test func doesNotMarkABlockPublishedWhenTheCalendarRefuses() async throws {
    let vault = try DayVault()
    try vault.write(dailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    let task = TaskParser.parse(line: "- [ ] Calcolo", sourcePath: "x.md", lineIndex: 0)!
    let block = try #require(dayController.addBlock(from: task))

    store.failure = .noWritableCalendar
    #expect(!dayController.publish(block))

    // Telling the user their day is on their calendar when it is not is the one
    // outcome this must never produce.
    let onDisk = try String(contentsOf: vault.root.appending(path: "Calendar/20260811.md"), encoding: .utf8)
    #expect(!onDisk.contains("[published]"))
    #expect(dayController.problems.contains { $0.contains("pubblicazione") })
    vaultController.close()
}

@MainActor
@Test func doesNotPublishTheSameBlockTwice() async throws {
    let vault = try DayVault()
    try vault.write(dailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    let task = TaskParser.parse(line: "- [ ] Calcolo", sourcePath: "x.md", lineIndex: 0)!
    let block = try #require(dayController.addBlock(from: task))
    #expect(dayController.publish(block))

    let republished = try #require(dayController.blocks.first)
    #expect(!dayController.publish(republished))
    #expect(store.createdEvents.count == 1)
    vaultController.close()
}

@MainActor
@Test func removingABlockTakesItOutOfTheNote() async throws {
    let vault = try DayVault()
    try vault.write(dailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    let task = TaskParser.parse(line: "- [ ] Da togliere", sourcePath: "x.md", lineIndex: 0)!
    let block = try #require(dayController.addBlock(from: task))
    dayController.remove(block)

    let onDisk = try String(contentsOf: vault.root.appending(path: "Calendar/20260811.md"), encoding: .utf8)
    #expect(!onDisk.contains("Da togliere"))
    #expect(dayController.blocks.isEmpty)
    vaultController.close()
}

@MainActor
@Test func readsBlocksAlreadyInTheNote() async throws {
    let vault = try DayVault()
    try vault.write(dailyNote + "\n\n## Timeline\n\n- 14:00-15:00 Riunione [published]\n",
                    to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    #expect(dayController.blocks.count == 1)
    #expect(dayController.blocks[0].title == "Riunione")
    #expect(dayController.blocks[0].isPublished)
    vaultController.close()
}

@MainActor
@Test func completingAReminderGoesThroughToTheStore() async throws {
    let vault = try DayVault()
    try vault.write(dailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    store.storedReminders = [
        CalendarReminder(id: "r1", title: "Richiamare", due: day, isCompleted: false, listTitle: "Lavoro"),
    ]
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    let reminder = try #require(dayController.reminders.first)
    #expect(dayController.toggle(reminder))
    // SPEC §8.2: completion is two-way, so it has to reach Reminders, not just the UI.
    #expect(store.completedCalls.count == 1)
    #expect(store.completedCalls[0].completed)
    #expect(dayController.reminders.first?.isCompleted == true)
    vaultController.close()
}

@MainActor
@Test func reportsAReminderTheStoreRefuses() async throws {
    let vault = try DayVault()
    try vault.write(dailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    store.storedReminders = [
        CalendarReminder(id: "r1", title: "Sparito", due: day, isCompleted: false, listTitle: "Lavoro"),
    ]
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)
    let reminder = try #require(dayController.reminders.first)

    store.failure = .reminderNotFound
    #expect(!dayController.toggle(reminder))
    #expect(dayController.problems.contains { $0.contains("promemoria") })
    vaultController.close()
}

@MainActor
@Test func showsOnlyTheRemindersDueOnTheDayShown() async throws {
    let vault = try DayVault()
    try vault.write(dailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    store.storedReminders = [
        CalendarReminder(id: "oggi", title: "Oggi", due: day, isCompleted: false, listTitle: "L"),
        CalendarReminder(id: "domani", title: "Domani",
                         due: CalendarDate(iso: "2026-08-12"), isCompleted: false, listTitle: "L"),
    ]
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)
    #expect(dayController.reminders.map(\.title) == ["Oggi"])
    vaultController.close()
}

@MainActor
@Test func creatingAnEventPutsItOnTheDayShown() async throws {
    let vault = try DayVault()
    try vault.write(dailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    #expect(dayController.createEvent(title: "Riunione", startMinutes: 15 * 60, durationMinutes: 60))
    #expect(store.createdEvents.count == 1)
    #expect(store.createdEvents[0].title == "Riunione")
    vaultController.close()
}

@MainActor
@Test func creatingAReminderGivesItTheDayShownAsItsDueDate() async throws {
    let vault = try DayVault()
    try vault.write(dailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    #expect(dayController.createReminder(title: "Richiamare Rossi"))
    #expect(store.storedReminders.first?.due == day)
    // It has to appear in the day at once, not after the next refresh.
    #expect(dayController.reminders.map(\.title) == ["Richiamare Rossi"])
    vaultController.close()
}

@MainActor
@Test func publishingEveryBlockReportsHowManyWent() async throws {
    let vault = try DayVault()
    try vault.write(dailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    for (index, name) in ["Uno", "Due", "Tre"].enumerated() {
        let task = TaskParser.parse(line: "- [ ] \(name)", sourcePath: "x.md", lineIndex: index)!
        _ = dayController.addBlock(from: task)
    }
    #expect(dayController.publishAllBlocks() == 3)
    #expect(store.createdEvents.count == 3)
    // A second run has nothing left to do rather than duplicating the three events.
    #expect(dayController.publishAllBlocks() == 0)
    #expect(store.createdEvents.count == 3)
    vaultController.close()
}

@MainActor
@Test func aBlockUsesTheTaskHourAndTheDurationFromSettings() async throws {
    let vault = try DayVault()
    try vault.write(dailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)
    vaultController.updateSettings { $0.blockMinutes = 45 }

    // A task due at 15:00 blocked out at nine in the morning is a plan for a different
    // day than the one written down.
    let task = TaskParser.parse(
        line: "- [ ] Collaudo !2026-08-11 15:00", sourcePath: "x.md", lineIndex: 0
    )!
    let block = try #require(dayController.addBlock(from: task))
    #expect(block.startMinutes == 15 * 60)
    #expect(block.durationMinutes == 45)

    let onDisk = try String(
        contentsOf: vault.root.appending(path: "Calendar/20260811.md"), encoding: .utf8
    )
    #expect(onDisk.contains("- 15:00-15:45 Collaudo"))
    vaultController.close()
}

@MainActor
@Test func aBlockIsRemovedFromTheNoteItLivesIn() async throws {
    let vault = try DayVault()
    try vault.write(dailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    let task = TaskParser.parse(line: "- [ ] Sopralluogo", sourcePath: "x.md", lineIndex: 0)!
    let block = try #require(dayController.addBlock(from: task))
    dayController.remove(block)

    #expect(dayController.blocks.isEmpty)
    let onDisk = try String(
        contentsOf: vault.root.appending(path: "Calendar/20260811.md"), encoding: .utf8
    )
    #expect(!onDisk.contains("Sopralluogo pressa"))
    #expect(!onDisk.contains("- 09:00-"))
    // The section stays, empty: the note keeps its shape between one plan and the next.
    #expect(onDisk.contains("## Timeline"))
    vaultController.close()
}
