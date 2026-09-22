import Foundation
import Testing
@testable import Pergamenum

// MARK: `show(_:)` (`WindowPlace.apply`'s `.day` arm calls exactly this, never `moveSpan`)

@MainActor
@Test func showJumpsToTheDayAndReloadsItsBlocks() async throws {
    let vault = try TemporaryVault()
    try vault.write(emptyDailyNote, to: "Calendar/20260811.md")
    try vault.write(emptyDailyNote, to: "Calendar/20260820.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    dayController.show(CalendarDate(iso: "2026-08-20")!)

    #expect(dayController.day == CalendarDate(iso: "2026-08-20"))
    vaultController.close()
}

/// §D3's rule (`WindowPlace.isDrift`) reads exactly this flag, so `show` has to leave it
/// false even right after a drift: a jump is a place gone to, never one scrolled past.
@MainActor
@Test func showClearsTheDriftFlagEvenRightAfterOne() async throws {
    let vault = try TemporaryVault()
    try vault.write(emptyDailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    dayController.moveSpan(by: 1)
    #expect(dayController.lastDayMoveWasDrift)

    dayController.show(CalendarDate(iso: "2026-09-01")!)
    #expect(!dayController.lastDayMoveWasDrift)
    vaultController.close()
}

@MainActor
@Test func turnsATaskIntoABlockAndWritesItIntoTheNote() async throws {
    let vault = try TemporaryVault()
    try vault.write(dayNoteWithProse, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    let task = TaskParser.parse(line: "- [ ] Sopralluogo pressa 4", sourcePath: "x.md", lineIndex: 0)!
    let block = try #require(dayController.addBlock(from: task))
    try await waitUntil { dayController.blocks.map(\.id) == [block.id] }

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
    let vault = try TemporaryVault()
    try vault.write(dayNoteWithProse, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    let first = TaskParser.parse(line: "- [ ] Primo", sourcePath: "x.md", lineIndex: 0)!
    let second = TaskParser.parse(line: "- [ ] Secondo", sourcePath: "x.md", lineIndex: 1)!
    _ = dayController.addBlock(from: first)
    try await waitUntil { dayController.blocks.count == 1 }
    let block = try #require(dayController.addBlock(from: second))

    try await waitUntil { dayController.blocks.count == 2 }

    // Two blocks at the same time say nothing about what the day looks like.
    #expect(block.startMinutes == 9 * 60 + TimeBlock.defaultDuration)
    #expect(dayController.blocks.count == 2)
    vaultController.close()
}

@MainActor
@Test func publishingWritesTheEventAndMarksTheBlock() async throws {
    let vault = try TemporaryVault()
    try vault.write(dayNoteWithProse, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    let task = TaskParser.parse(line: "- [ ] Calcolo", sourcePath: "x.md", lineIndex: 0)!
    let block = try #require(dayController.addBlock(from: task))
    try await waitUntil { dayController.blocks.map(\.id) == [block.id] }

    #expect(dayController.publish(block, toCalendarTitled: "Pergamenum"))
    #expect(store.createdEvents.count == 1)
    #expect(store.createdEvents[0].title == "Calcolo")
    #expect(store.createdEvents[0].calendarTitle == "Pergamenum")

    try await waitUntil {
        dayController.blocks.first { $0.id == block.id }?.isPublished == true
    }
    let onDisk = try String(contentsOf: vault.root.appending(path: "Calendar/20260811.md"), encoding: .utf8)
    #expect(onDisk.contains("[published]"))
    vaultController.close()
}

@MainActor
@Test func doesNotMarkABlockPublishedWhenTheCalendarRefuses() async throws {
    let vault = try TemporaryVault()
    try vault.write(dayNoteWithProse, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    let task = TaskParser.parse(line: "- [ ] Calcolo", sourcePath: "x.md", lineIndex: 0)!
    let block = try #require(dayController.addBlock(from: task))
    try await waitUntil { dayController.blocks.map(\.id) == [block.id] }

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
    let vault = try TemporaryVault()
    try vault.write(dayNoteWithProse, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    let task = TaskParser.parse(line: "- [ ] Calcolo", sourcePath: "x.md", lineIndex: 0)!
    let block = try #require(dayController.addBlock(from: task))
    try await waitUntil { dayController.blocks.map(\.id) == [block.id] }
    #expect(dayController.publish(block))

    try await waitUntil {
        dayController.blocks.first { $0.id == block.id }?.isPublished == true
    }
    let republished = try #require(dayController.blocks.first)
    #expect(!dayController.publish(republished))
    #expect(store.createdEvents.count == 1)
    vaultController.close()
}

@MainActor
@Test func removingABlockTakesItOutOfTheNote() async throws {
    let vault = try TemporaryVault()
    try vault.write(dayNoteWithProse, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    let task = TaskParser.parse(line: "- [ ] Da togliere", sourcePath: "x.md", lineIndex: 0)!
    let block = try #require(dayController.addBlock(from: task))
    try await waitUntil { dayController.blocks.map(\.id) == [block.id] }
    dayController.remove(block)
    try await waitUntil { dayController.blocks.isEmpty }

    let onDisk = try String(contentsOf: vault.root.appending(path: "Calendar/20260811.md"), encoding: .utf8)
    #expect(!onDisk.contains("Da togliere"))
    #expect(dayController.blocks.isEmpty)
    vaultController.close()
}

@MainActor
@Test func readsBlocksAlreadyInTheNote() async throws {
    let vault = try TemporaryVault()
    try vault.write(dayNoteWithProse + "\n\n## Timeline\n\n- 14:00-15:00 Riunione [published]\n",
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
    let vault = try TemporaryVault()
    try vault.write(dayNoteWithProse, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    store.storedReminders = [
        CalendarReminder(id: "r1", title: "Richiamare", due: testDay, isCompleted: false, listTitle: "Lavoro"),
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
    let vault = try TemporaryVault()
    try vault.write(dayNoteWithProse, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    store.storedReminders = [
        CalendarReminder(id: "r1", title: "Sparito", due: testDay, isCompleted: false, listTitle: "Lavoro"),
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
    let vault = try TemporaryVault()
    try vault.write(dayNoteWithProse, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    store.storedReminders = [
        CalendarReminder(id: "oggi", title: "Oggi", due: testDay, isCompleted: false, listTitle: "L"),
        CalendarReminder(id: "domani", title: "Domani",
                         due: CalendarDate(iso: "2026-08-12"), isCompleted: false, listTitle: "L"),
    ]
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)
    #expect(dayController.reminders.map(\.title) == ["Oggi"])
    vaultController.close()
}

@MainActor
@Test func creatingAnEventPutsItOnTheDayShown() async throws {
    let vault = try TemporaryVault()
    try vault.write(dayNoteWithProse, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    #expect(dayController.createEvent(title: "Riunione", startMinutes: 15 * 60, durationMinutes: 60))
    #expect(store.createdEvents.count == 1)
    #expect(store.createdEvents[0].title == "Riunione")
    vaultController.close()
}

@MainActor
@Test func creatingAReminderGivesItTheDayShownAsItsDueDate() async throws {
    let vault = try TemporaryVault()
    try vault.write(dayNoteWithProse, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    #expect(dayController.createReminder(title: "Richiamare Rossi"))
    #expect(store.storedReminders.first?.due == testDay)
    // It has to appear in the day at once, not after the next refresh.
    #expect(dayController.reminders.map(\.title) == ["Richiamare Rossi"])
    vaultController.close()
}

@MainActor
@Test func publishingEveryBlockReportsHowManyWent() async throws {
    let vault = try TemporaryVault()
    try vault.write(dayNoteWithProse, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    for (index, name) in ["Uno", "Due", "Tre"].enumerated() {
        let task = TaskParser.parse(line: "- [ ] \(name)", sourcePath: "x.md", lineIndex: index)!
        _ = dayController.addBlock(from: task)
        try await waitUntil { dayController.blocks.count == index + 1 }
    }
    #expect(dayController.publishAllBlocks() == 3)
    #expect(store.createdEvents.count == 3)
    try await waitUntil {
        dayController.blocks.count == 3 && dayController.blocks.allSatisfy(\.isPublished)
    }
    // A second run has nothing left to do rather than duplicating the three events.
    #expect(dayController.publishAllBlocks() == 0)
    #expect(store.createdEvents.count == 3)
    vaultController.close()
}

@MainActor
@Test func aBlockUsesTheTaskHourAndTheDurationFromSettings() async throws {
    let vault = try TemporaryVault()
    try vault.write(dayNoteWithProse, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)
    vaultController.updateSettings { $0.blockMinutes = 45 }

    // A task due at 15:00 blocked out at nine in the morning is a plan for a different
    // day than the one written down.
    let task = TaskParser.parse(
        line: "- [ ] Collaudo !2026-08-11 15:00", sourcePath: "x.md", lineIndex: 0
    )!
    let block = try #require(dayController.addBlock(from: task))
    try await waitUntil { dayController.blocks.map(\.id) == [block.id] }
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
    let vault = try TemporaryVault()
    try vault.write(dayNoteWithProse, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    let task = TaskParser.parse(line: "- [ ] Sopralluogo", sourcePath: "x.md", lineIndex: 0)!
    let block = try #require(dayController.addBlock(from: task))
    try await waitUntil { dayController.blocks.map(\.id) == [block.id] }
    dayController.remove(block)
    try await waitUntil { dayController.blocks.isEmpty }

    #expect(dayController.blocks.isEmpty)
    let onDisk = try String(
        contentsOf: vault.root.appending(path: "Calendar/20260811.md"), encoding: .utf8
    )
    #expect(!onDisk.contains("Sopralluogo pressa"))
    #expect(!onDisk.contains("- 09:00-"))
    // The section goes with the last block. An empty `## Timeline` is a heading the
    // user never wrote, left behind by a plan that no longer exists.
    #expect(!onDisk.contains("## Timeline"))
    #expect(onDisk == dayNoteWithProse + "\n")
    // The note says something of its own, so the editor showing it stays open.
    #expect(vaultController.openNote != nil)
    vaultController.close()
}

/// A block is written to the file and never to the editor: the day view does not open a
/// note because someone blocked out half an hour, so there is no pane to be left behind
/// when the block goes.
@MainActor
@Test func blockingOutADayNeverOpensTheNoteInTheEditor() async throws {
    let vault = try TemporaryVault()
    try vault.write(emptyDailyNote, to: "Calendar/20260811.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(
        vault: vault, store: store, openingTheDailyNote: false
    )

    let task = TaskParser.parse(line: "- [ ] Sopralluogo", sourcePath: "x.md", lineIndex: 0)!
    let block = try #require(dayController.addBlock(from: task))
    try await waitUntil { dayController.blocks.map(\.id) == [block.id] }
    #expect(vaultController.openNote == nil, "il blocco ha aperto la nota nell'editor")
    #expect(dayController.blocks.map(\.id) == [block.id])

    let written = try String(
        contentsOf: vault.root.appending(path: "Calendar/20260811.md"), encoding: .utf8
    )
    #expect(written.contains("- 09:00-09:30 Sopralluogo"), "il blocco non è finito nel file")

    dayController.remove(block)
    try await waitUntil { dayController.blocks.isEmpty }
    #expect(dayController.blocks.isEmpty)
    #expect(vaultController.openNote == nil)
    let afterwards = try String(
        contentsOf: vault.root.appending(path: "Calendar/20260811.md"), encoding: .utf8
    )
    #expect(afterwards == emptyDailyNote, "la nota non è tornata com'era")
    vaultController.close()
}

/// A day with no note at all: blocking it out writes one, and taking the block away does
/// not leave the app writing files for a day nobody asked about.
@MainActor
@Test func aDayWithoutANoteGetsOneOnlyWhenSomethingIsWrittenToIt() async throws {
    let vault = try TemporaryVault()
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(
        vault: vault, store: store, openingTheDailyNote: false
    )
    let path = vault.root.appending(path: "Calendar/20260811.md")

    dayController.remove(TimeBlock(
        day: testDay, startMinutes: 540, durationMinutes: 30,
        title: "Mai esistito", sourceTaskID: nil, isPublished: false
    ))
    #expect(!FileManager.default.fileExists(atPath: path.path(percentEncoded: false)),
            "una cancellazione a vuoto ha creato la nota del giorno")

    let task = TaskParser.parse(line: "- [ ] Sopralluogo", sourcePath: "x.md", lineIndex: 0)!
    #expect(dayController.addBlock(from: task) != nil)
    try await waitUntil { dayController.blocks.count == 1 }
    #expect(FileManager.default.fileExists(atPath: path.path(percentEncoded: false)))
    #expect(vaultController.openNote == nil, "la nota creata è stata anche aperta")
    vaultController.close()
}

/// The task the block came from is none of this: it lives in its own note and a block's
/// delete has no business touching it.
@MainActor
@Test func removingABlockLeavesTheTaskItCameFromAlone() async throws {
    let vault = try TemporaryVault()
    try vault.write(emptyDailyNote, to: "Calendar/20260811.md")
    let source = """
    ---
    date: 2026-08-11
    tags:
      - type-note
    ---

    - [ ] Sopralluogo >2026-08-11
    """
    try vault.write(source, to: "Attivita.md")
    let store = StubCalendarStore()
    let (dayController, vaultController) = try await makeController(vault: vault, store: store)

    let task = TaskParser.parse(line: "- [ ] Sopralluogo >2026-08-11", sourcePath: "Attivita.md", lineIndex: 6)!
    let block = try #require(dayController.addBlock(from: task))
    try await waitUntil { dayController.blocks.map(\.id) == [block.id] }
    dayController.remove(block)
    try await waitUntil { dayController.blocks.isEmpty }

    let onDisk = try String(contentsOf: vault.root.appending(path: "Attivita.md"), encoding: .utf8)
    #expect(onDisk == source, "la nota del task è cambiata")
    vaultController.close()
}
