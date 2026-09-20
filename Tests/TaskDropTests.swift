import Foundation
import Testing
@testable import Pergamenum

// The second write a gesture makes (ADR-0013 §D5): a task dragged onto a day, or onto an hour.

// MARK: - Il carico che la riga trascinata porta

@Test func theDraggedPayloadRoundTrips() throws {
    let payload = TaskDragPayload(path: "Note/Lavoro.md", lineIndex: 12)

    let parsed = try #require(TaskDragPayload(text: payload.text))

    #expect(parsed.path == "Note/Lavoro.md")
    #expect(parsed.lineIndex == 12)
}

/// Anything that is not the pair is refused rather than guessed at: a payload from somewhere
/// else in the app - a note title dragged out of the list, a file from the Finder - must find
/// no day willing to take it.
@Test func aPayloadThatIsNotTheTwoPartsIsRefused() {
    #expect(TaskDragPayload(text: "Note/Lavoro.md") == nil)
    #expect(TaskDragPayload(text: "Note/Lavoro.md\u{1}non-un-numero") == nil)
    #expect(TaskDragPayload(text: "\u{1}4") == nil)
    #expect(TaskDragPayload(text: "Note/Lavoro.md\u{1}-1") == nil)
}

/// Only a scheduled task moves. An event belongs to EventKit, a block to the daily note, and a
/// deadline is on the day because of its `!` marker while the drag rewrites `>`.
@Test func onlyAScheduledTaskCarriesAPayload() {
    let day = CalendarDate(iso: "2026-08-20")!
    func entry(_ kind: WeekEntryKind, sourcePath: String?, lineIndex: Int?) -> WeekEntry {
        WeekEntry(
            id: "\(kind)-\(sourcePath ?? "-")", kind: kind, title: "Qualcosa",
            timeText: nil, minutes: nil, sourcePath: sourcePath, lineIndex: lineIndex
        )
    }

    #expect(entry(.task, sourcePath: "Note/Lavoro.md", lineIndex: 3).dragPayload != nil)
    #expect(entry(.deadline, sourcePath: "Note/Lavoro.md", lineIndex: 3).dragPayload == nil)
    #expect(entry(.event, sourcePath: nil, lineIndex: nil).dragPayload == nil)
    #expect(entry(.block, sourcePath: "Calendar/\(day.compactForm).md", lineIndex: 2).dragPayload == nil)
}

// MARK: - La scrittura

private let dropTargetNote = """
---
date: 2026-08-17
tags:
  - type-note
  - topic-gomma
---

## Lavoro

- [ ] Calcolo trasmissibilità >2026-08-17
- [ ] Collaudo pressa >2026-08-17 09:00

"""

@MainActor
private func session(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(dropTargetNote, to: "Lavoro.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

@MainActor
private func task(_ session: VaultSession, containing text: String) throws -> TaskItem {
    try #require(session.index.allTasks.first { $0.text.contains(text) })
}

@MainActor
@Test func aDropOnADayRewritesTheDateAndLeavesTheHourOut() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    let moved = try task(session, containing: "Collaudo")
    let thursday = try #require(CalendarDate(iso: "2026-08-20"))

    let outcome = await session.moveTask(moved, to: thursday)

    #expect(outcome.didWrite)
    #expect(outcome.problem == nil)
    let text = try session.read("Lavoro.md").text
    #expect(text.contains("- [ ] Collaudo pressa >2026-08-20"))
    // The hour went with the day it belonged to: a drop on a column said Thursday, not 09:00.
    #expect(!text.contains("2026-08-20 09:00"))
    // Armed for this write and disarmed after it, as the board's drop is.
    #expect(session.journal == nil)
}

@MainActor
@Test func aDropOnAnHourWritesTheHourBesideTheDay() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    let moved = try task(session, containing: "Calcolo")
    let thursday = try #require(CalendarDate(iso: "2026-08-20"))

    let outcome = await session.moveTask(moved, to: thursday, at: TaskTime(hour: 15, minute: 0))

    #expect(outcome.didWrite)
    #expect(try session.read("Lavoro.md").text.contains("- [ ] Calcolo trasmissibilità >2026-08-20 15:00"))
}

@MainActor
@Test func aTaskDropIsUndoneThroughTheJournal() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    let before = try session.read("Lavoro.md").text
    let moved = try task(session, containing: "Collaudo")
    let outcome = await session.moveTask(moved, to: try #require(CalendarDate(iso: "2026-08-20")))

    let undone = await session.undoJournalledWrites([try #require(outcome.journalID)])

    #expect(undone.failures.isEmpty)
    #expect(try session.read("Lavoro.md").text == before)
}

/// A drop on the day the task already says is not a write at all: the line would come back
/// identical, and a journal entry for it would be an undo that undoes nothing.
@MainActor
@Test func aDropOnTheDayItAlreadyHasWritesNothing() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    let moved = try task(session, containing: "Calcolo")

    let outcome = await session.moveTask(moved, to: try #require(CalendarDate(iso: "2026-08-17")))

    #expect(!outcome.didWrite)
    #expect(outcome.problem == nil)
}

/// The line moved under the gesture: refused by name rather than rewritten by line number,
/// which is what stops a stale row from editing whatever now sits there.
@MainActor
@Test func aLineThatMovedIsRefusedRatherThanRewritten() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    var moved = try task(session, containing: "Collaudo")
    moved.lineIndex += 3

    let outcome = await session.moveTask(moved, to: try #require(CalendarDate(iso: "2026-08-20")))

    #expect(!outcome.didWrite)
    #expect(outcome.problem?.contains("non è più dove risultava") == true)
    #expect(try session.read("Lavoro.md").text == dropTargetNote)
}

/// The differential guard is here and quiet, and the test says which of the two it is: a `>`
/// rewritten on a body line introduces no name, frontmatter, tag or related violation, so a
/// note that was already non-conformant is still moved.
@MainActor
@Test func aNoteAlreadyNonConformantStillTakesTheDrop() async throws {
    let vault = try TemporaryVault()
    try vault.write("- [ ] Senza frontmatter >2026-08-17\n", to: "Sciolto.md")
    let session = try await session(vault)
    let moved = try #require(session.index.allTasks.first { $0.sourcePath == "Sciolto.md" })

    let outcome = await session.moveTask(moved, to: try #require(CalendarDate(iso: "2026-08-20")))

    #expect(outcome.didWrite)
    #expect(outcome.introduced.isEmpty)
    #expect(try session.read("Sciolto.md").text.contains(">2026-08-20"))
}

// MARK: - Drop onto a category row (ADR-0047 §D5, R-03's other assignment gesture)

@MainActor
private func controller(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    try vault.write(dropTargetNote, to: "Lavoro.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    return controller
}

@MainActor
@Test func aDropOnACategoryRowWritesTheSameTagTask3sWriterProduces() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    let dropped = try #require(controller.index.allTasks.first { $0.text.contains("Collaudo") })

    let didWrite = await controller.dropTask(
        sourcePath: dropped.sourcePath, lineIndex: dropped.lineIndex, onCategory: "vibrofer"
    )

    #expect(didWrite)
    let text = try controller.session?.read("Lavoro.md").text
    #expect(text?.contains("#project-vibrofer") == true)
}

/// A row drawn from a scan the index has since moved on from - the same refusal
/// `dropTask(sourcePath:lineIndex:on:at:)` gives for a day drop, exercised here for the
/// category door.
@MainActor
@Test func aCategoryDropWhosePayloadNoLongerResolvesToATaskIsRefused() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)

    let didWrite = await controller.dropTask(sourcePath: "Lavoro.md", lineIndex: 99, onCategory: "vibrofer")

    #expect(!didWrite)
    #expect(controller.problems.contains { $0.contains("non è più dove risultava") })
}
