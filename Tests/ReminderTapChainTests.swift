import Foundation
import Testing
import UserNotifications
@testable import Pergamenum

// PG-243's hand checks M2, M4 and M5 moved below the banner,
// `docs/plans/pg-243-tap-automated-checks.md`, Task 4 (R-03).
//
// Each chain starts from the payload `ReminderScheduler.requests(for:after:noteIDs:)` itself
// writes, classifies it through `ReminderScheduler.tap(actionIdentifier:userInfo:)` and hands
// the route to `VaultController.handle(_:)` directly. The scheduler's own `deliver` and sink
// are covered by `Tests/ReminderDeliveryTests.swift`; here the sink is the controller.

private let noteWithReminder = """
---
date: 2026-09-25
tags:
  - type-note
---

- [ ] Richiamare @remind(2026-08-15 09:00)
"""

private let beforeReminders = EventKitStore.date(CalendarDate(iso: "2026-08-10")!, hour: 0, minute: 0)!

/// The route a default-action tap on `request` asks for, or a recorded issue.
private func tappedRoute(_ request: UNNotificationRequest) -> PergamenumRoute? {
    let tap = ReminderScheduler.tap(
        actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: request.content.userInfo
    )
    guard case .open(let route) = tap else {
        Issue.record("expected an open tap, got \(tap)")
        return nil
    }
    return route
}

// MARK: C1 (M2) - a tap before the vault opens is held, then replayed onto the note

@MainActor
@Test func aReminderTappedBeforeTheVaultOpensOpensItsNoteOnceTheVaultIsOpen() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteWithReminder, to: "b.md")

    let a = VaultController(recents: .volatile(), openTabs: .volatile())
    await a.open(vault.root)
    let id = try #require(a.session?.mintNoteID(for: "b.md"))
    let tasks = a.index.allTasks.filter { $0.sourcePath == "b.md" }
    let request = try #require(
        ReminderScheduler.requests(for: tasks, after: beforeReminders, noteIDs: ["b.md": id]).first
    )
    a.close()

    let b = VaultController(recents: .volatile(), openTabs: .volatile())
    let route = try #require(tappedRoute(request))

    let outcomeBeforeOpen = await b.handle(route)
    #expect(!outcomeBeforeOpen)
    #expect(b.routeState.pending == route)

    await b.open(vault.root)

    #expect(b.openNote?.relativePath == "b.md")
    b.close()
}

// MARK: C2 (M4) - a payload written before an in-app rename opens the renamed note

@MainActor
@Test func aReminderScheduledBeforeAnInAppRenameOpensTheRenamedNote() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteWithReminder, to: "b.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)

    let id = try #require(controller.session?.mintNoteID(for: "b.md"))
    let tasks = controller.index.allTasks.filter { $0.sourcePath == "b.md" }
    let request = try #require(
        ReminderScheduler.requests(for: tasks, after: beforeReminders, noteIDs: ["b.md": id]).first
    )

    #expect(await controller.renameNote(at: "b.md", to: "B rinominata"))
    await controller.rescan()

    let route = try #require(tappedRoute(request))
    #expect(await controller.handle(route))
    #expect(controller.openNote?.relativePath == "B rinominata.md")
    controller.close()
}

// MARK: C3 (M5) - a board task's reminder reaches the Workspace and opens no note tab

@MainActor
@Test func aBoardTasksReminderReachesTheWorkspaceAndOpensNoNoteTab() async throws {
    let vault = try TemporaryVault()
    // The board file exists on disk, so a board task wrongly routed as a note would find a file
    // to open: without it `openNote == nil` below holds whatever the routing does.
    try vault.write(
        """
        {"nodes":[{"id":"7a1f","type":"text","text":"Prova","x":0,"y":0,"width":200,"height":80}],"edges":[]}
        """,
        to: "Area/Area.canvas"
    )
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)

    var item = try #require(TaskParser.parse(
        line: "- [ ] Prova @remind(2026-08-15 09:00)", sourcePath: "Area/Area.canvas", lineIndex: 0
    ))
    item.nodeID = "7a1f"
    let request = try #require(ReminderScheduler.requests(for: [item], after: beforeReminders).first)

    let route = try #require(tappedRoute(request))
    #expect(await controller.handle(route))
    let pending = controller.consumePendingCanvasRoute()
    #expect(pending?.path == "Area/Area.canvas")
    #expect(pending?.nodeID == "7a1f")
    #expect(controller.openNote == nil)
    #expect(!controller.tabs.contains { $0.note.relativePath == "Area/Area.canvas" })
    controller.close()
}
