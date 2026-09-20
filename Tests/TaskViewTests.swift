import Foundation
import Testing
@testable import Pergamenum

// The tasks that need a real vault on disk: the views over it, the rewrites written back to it,
// and the day view's filters. Split out of TaskTests.swift (PG-148, ADR-0051), which had passed
// 500 lines; the pure parsing and rewriting stayed there.

// The same day TaskTests.swift uses; a file-private constant per file, like every other suite here.
private let today = CalendarDate(iso: "2026-08-11")!

// MARK: - Task views and rewriting on disk

private let fiveViewsNote = """
---
date: 2026-08-11
tags:
  - type-note
---

- [ ] Senza data
- [ ] Oggi >2026-08-11
- [ ] In ritardo !2026-08-05
- [ ] Fra tre giorni >2026-08-14
- [ ] Fra un mese >2026-09-20
- [ ] Di progetto #project-pergamenum
- [x] Gia fatto @done(2026-08-10)
- [ ] Collegato a [[Curva di trasmissibilità]]
"""

@MainActor
@Test func sortsTasksIntoTheFiveViews() async throws {
    let vault = try TemporaryVault()
    try vault.write(fiveViewsNote, to: "Note.md")

    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    let day = CalendarDate(iso: "2026-08-11")!

    // Inbox: no date, no project.
    #expect(controller.index.tasks(for: .inbox, on: day).map(\.text) == ["Senza data", "Collegato a"])
    // Today includes the overdue one: a task that slipped is what the day view exists
    // to surface (SPEC §7.3 rules out moving it silently).
    #expect(Set(controller.index.tasks(for: .today, on: day).map(\.text)) == ["Oggi", "In ritardo"])
    // Upcoming is the next seven days, so the one a month out is excluded.
    #expect(controller.index.tasks(for: .upcoming, on: day).map(\.text) == ["Fra tre giorni"])
    #expect(controller.index.tasks(for: .byProject, on: day).map(\.text) == ["Di progetto"])
    // Every view is open tasks only; the completed one appears in none of them.
    #expect(controller.index.tasks(for: .all, on: day).count == 7)
    controller.close()
}

@MainActor
@Test func findsTheTasksLinkingToANote() async throws {
    let vault = try TemporaryVault()
    try vault.write(fiveViewsNote, to: "Note.md")

    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    // SPEC §7.2: the wikilink is the link, navigable in both directions.
    #expect(controller.index.tasks(linkingTo: "Curva di trasmissibilità").count == 1)
    #expect(controller.index.tasks(linkingTo: "curva di trasmissibilità").count == 1)
    #expect(controller.index.tasks(linkingTo: "Inesistente").isEmpty)
    controller.close()
}

@MainActor
@Test func completingATaskRewritesItsSourceNote() async throws {
    let vault = try TemporaryVault()
    try vault.write(fiveViewsNote, to: "Note.md")

    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    let task = try #require(controller.index.allTasks.first { $0.text == "Oggi" })

    #expect(await controller.toggle(task))

    let onDisk = try String(contentsOf: vault.root.appending(path: "Note.md"), encoding: .utf8)
    #expect(onDisk.contains("- [x] Oggi >2026-08-11 @done("))
    // Everything else in the note is untouched.
    #expect(onDisk.contains("- [ ] Senza data"))
    #expect(onDisk.contains("date: 2026-08-11"))
    controller.close()
}

@MainActor
@Test func reschedulingWritesTheNewDate() async throws {
    let vault = try TemporaryVault()
    try vault.write(fiveViewsNote, to: "Note.md")

    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    let task = try #require(controller.index.allTasks.first { $0.text == "Oggi" })

    #expect(await controller.apply(.schedule(CalendarDate(iso: "2026-08-20")!), to: task))
    let onDisk = try String(contentsOf: vault.root.appending(path: "Note.md"), encoding: .utf8)
    #expect(onDisk.contains("- [ ] Oggi >2026-08-20"))
    #expect(!onDisk.contains(">2026-08-11\n"))
    controller.close()
}

@MainActor
@Test func settingADueDateFromTheContextMenuWritesIt() async throws {
    let vault = try TemporaryVault()
    try vault.write(fiveViewsNote, to: "Note.md")

    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    let task = try #require(controller.index.allTasks.first { $0.text == "Oggi" })

    #expect(await controller.apply(.due(CalendarDate(iso: "2026-08-25")!), to: task))
    var onDisk = try String(contentsOf: vault.root.appending(path: "Note.md"), encoding: .utf8)
    #expect(onDisk.contains("!2026-08-25"))

    let updated = try #require(controller.index.allTasks.first { $0.text == "Oggi" })
    #expect(await controller.apply(.due(nil), to: updated))
    onDisk = try String(contentsOf: vault.root.appending(path: "Note.md"), encoding: .utf8)
    #expect(!onDisk.contains("!2026-08-25"))
    controller.close()
}

@MainActor
@Test func refusesToRewriteATaskThatMovedOnDisk() async throws {
    let vault = try TemporaryVault()
    try vault.write(fiveViewsNote, to: "Note.md")

    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    var task = try #require(controller.index.allTasks.first { $0.text == "Oggi" })

    // Simulate a stale index entry: the line number is right, the content is not.
    task.rawLine = "- [ ] Qualcosa di completamente diverso"
    #expect(await !controller.apply(.state(.done), to: task))

    let onDisk = try String(contentsOf: vault.root.appending(path: "Note.md"), encoding: .utf8)
    #expect(onDisk == fiveViewsNote)
    controller.close()
}

@MainActor
@Test func quickCaptureAppendsToTheInbox() async throws {
    let vault = try TemporaryVault()
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)

    #expect(await controller.captureTask("Richiamare Rossi"))
    #expect(await controller.captureTask("Ordinare i supporti"))

    let onDisk = try String(contentsOf: vault.root.appending(path: "00 Inbox/Capture.md"), encoding: .utf8)
    #expect(onDisk.contains("- [ ] Richiamare Rossi"))
    #expect(onDisk.contains("- [ ] Ordinare i supporti"))
    // The capture note itself is conformant: type-note plus status-inbox (tag.md 5.1).
    #expect(onDisk.contains("- type-note"))
    #expect(onDisk.contains("- status-inbox"))

    let day = CalendarDate(iso: "2026-08-11")!
    #expect(controller.index.tasks(for: .inbox, on: day).count == 2)
    controller.close()
}

@MainActor
@Test func quickCaptureIgnoresEmptyInput() async throws {
    let vault = try TemporaryVault()
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    #expect(await !controller.captureTask("   "))
    controller.close()
}

// MARK: The day view's filters

@MainActor
@Test func theDueFilterListsWhatFallsDueNextAndTheMonthMarksIt() async throws {
    let vault = try TemporaryVault()
    try vault.write("""
    ---
    date: 2026-08-11
    tags:
      - type-note
    ---

    - [ ] Vicina !2026-08-12 18:00
    - [ ] Lontana !2026-11-30
    - [x] Fatta !2026-08-13 @done(2026-08-11)
    - [ ] Senza scadenza
    """, to: "Scadenze.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)

    let day = CalendarDate(iso: "2026-08-11")!
    let due = controller.index.dueTasks(from: day)
    // Within thirty days, soonest first, and only what is still open.
    #expect(due.map(\.text) == ["Vicina"])
    #expect(controller.index.dueTasks(from: day, within: 200).map(\.text) == ["Vicina", "Lontana"])

    // The month grid marks the same days, and never a completed one.
    #expect(controller.index.dueDays.contains(CalendarDate(iso: "2026-08-12")!))
    #expect(!controller.index.dueDays.contains(CalendarDate(iso: "2026-08-13")!))
    controller.close()
}

@MainActor
@Test func theCompletedFilterKeepsFinishedTasksInTheDay() async throws {
    let vault = try TemporaryVault()
    try vault.write("""
    ---
    date: 2026-08-11
    tags:
      - type-note
    ---

    - [ ] Aperta >2026-08-11
    - [x] Chiusa >2026-08-11 @done(2026-08-11)
    """, to: "Giornata.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)

    let day = CalendarDate(iso: "2026-08-11")!
    #expect(controller.index.tasks(for: .today, on: day).map(\.text) == ["Aperta"])
    #expect(controller.index.tasks(for: .today, on: day, includingCompleted: true).map(\.text)
        == ["Aperta", "Chiusa"])
    controller.close()
}
