import Foundation
import Testing
import UserNotifications
@testable import Pergamenum

// PG-243, `docs/plans/pg-243-reminder-notification-tap.md`, Task 1 and Task 2.
//
// `ReminderScheduler.tap(actionIdentifier:userInfo:)` is a pure function (R-04), tested
// here without ever constructing a `ReminderScheduler`: building one would point the host
// process's real notification delegate at a throwaway object (the plan's Task 3 note).
// `ReminderScheduler.requests(for:after:noteIDs:)` is already covered generally in
// `Tests/CalendarTests.swift`; T2.1 here is specifically about a board-sourced task's route.

private func task(_ line: String, sourcePath: String = "01 Progetti/Nota.md") -> TaskItem {
    TaskParser.parse(line: line, sourcePath: sourcePath, lineIndex: 0)!
}

private let beforeReminders = EventKitStore.date(CalendarDate(iso: "2026-08-10")!, hour: 0, minute: 0)!

// MARK: T1.1 - default action, id-form route

@Test func aDefaultActionWithAnIdRouteOpensTheNoteByID() {
    let tap = ReminderScheduler.tap(
        actionIdentifier: UNNotificationDefaultActionIdentifier,
        userInfo: [ReminderScheduler.routeKey: "pergamenum://note?id=3f2c1b4a-0000-4000-8000-000000000000"]
    )
    #expect(tap == .open(.noteID("3f2c1b4a-0000-4000-8000-000000000000")))
}

// MARK: T1.2 - default action, path-form route

@Test func aDefaultActionWithAPathRouteOpensTheNoteByPath() {
    let tap = ReminderScheduler.tap(
        actionIdentifier: UNNotificationDefaultActionIdentifier,
        userInfo: [ReminderScheduler.routeKey: "pergamenum://note?file=01%20Progetti/Nota.md"]
    )
    #expect(tap == .open(.note(path: "01 Progetti/Nota.md")))
}

// MARK: T1.3 - round trip through the requests the scheduler itself writes

@Test func classifyingARequestBuiltWithAMintedIDRoundTripsToTheIDRoute() throws {
    let requests = ReminderScheduler.requests(
        for: [task("- [ ] Richiamare @remind(2026-08-15 09:00)")],
        after: beforeReminders,
        noteIDs: ["01 Progetti/Nota.md": "3f2c1b4a-0000-4000-8000-000000000000"]
    )
    let request = try #require(requests.first)
    let tap = ReminderScheduler.tap(
        actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: request.content.userInfo
    )
    #expect(tap == .open(.noteID("3f2c1b4a-0000-4000-8000-000000000000")))
}

@Test func classifyingARequestBuiltWithNoMintedIDRoundTripsToThePathRoute() throws {
    let requests = ReminderScheduler.requests(
        for: [task("- [ ] Richiamare @remind(2026-08-15 09:00)")], after: beforeReminders
    )
    let request = try #require(requests.first)
    let tap = ReminderScheduler.tap(
        actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: request.content.userInfo
    )
    #expect(tap == .open(.note(path: "01 Progetti/Nota.md")))
}

// MARK: T1.4 - the test notification's shape, no userInfo at all

@Test func aDefaultActionWithNoUserInfoGivesNoRoute() {
    let tap = ReminderScheduler.tap(actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: [:])
    #expect(tap == .noRoute)
}

// MARK: T1.5 - an empty route value, what `requests` writes when no URL can be built

@Test func aDefaultActionWithAnEmptyRouteValueGivesNoRoute() {
    let tap = ReminderScheduler.tap(
        actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: [ReminderScheduler.routeKey: ""]
    )
    #expect(tap == .noRoute)
}

// MARK: T1.6 - unreadable routes

@Test(arguments: [
    "pergamenum://sconosciuto",
    "non è un url",
    "https://example.test",
])
func aDefaultActionWithAnUnreadableStringRouteGivesUnreadableRoute(_ value: String) {
    let tap = ReminderScheduler.tap(
        actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: [ReminderScheduler.routeKey: value]
    )
    #expect(tap == .unreadableRoute)
}

@Test func aDefaultActionWithANonStringRouteValueGivesUnreadableRoute() {
    let tap = ReminderScheduler.tap(
        actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: [ReminderScheduler.routeKey: 42]
    )
    #expect(tap == .unreadableRoute)
}

// MARK: T1.7 - not the default action

@Test func aDismissedNotificationWithAValidRouteIsNotDefaultAction() {
    let tap = ReminderScheduler.tap(
        actionIdentifier: UNNotificationDismissActionIdentifier,
        userInfo: [ReminderScheduler.routeKey: "pergamenum://note?file=a.md"]
    )
    #expect(tap == .notDefaultAction)
}

@Test func aCustomActionWithAValidRouteIsNotDefaultAction() {
    let tap = ReminderScheduler.tap(
        actionIdentifier: "posticipa",
        userInfo: [ReminderScheduler.routeKey: "pergamenum://note?file=a.md"]
    )
    #expect(tap == .notDefaultAction)
}

// MARK: T1.8 - a `.canvas` sourced note route becomes the board route (backstop for pre-Task-2 notifications)

@Test func aNotePathRouteToACanvasFileBecomesTheBoardRoute() {
    let tap = ReminderScheduler.tap(
        actionIdentifier: UNNotificationDefaultActionIdentifier,
        userInfo: [ReminderScheduler.routeKey: "pergamenum://note?file=Area/Board.canvas"]
    )
    #expect(tap == .open(.canvas(path: "Area/Board.canvas", nodeID: nil)))
}

@Test func theCanvasExtensionCheckIgnoresCase() {
    let tap = ReminderScheduler.tap(
        actionIdentifier: UNNotificationDefaultActionIdentifier,
        userInfo: [ReminderScheduler.routeKey: "pergamenum://note?file=Area/Board.CANVAS"]
    )
    #expect(tap == .open(.canvas(path: "Area/Board.CANVAS", nodeID: nil)))
}

// MARK: T2.1 - a board-sourced reminder carries the board route, id never wins for a board

@Test func aBoardSourcedTaskGetsTheBoardRouteEvenWhenAnIDWasMintedForThatPath() throws {
    var item = task("- [ ] Prova @remind(2026-08-15 09:00)", sourcePath: "Area/Board.canvas")
    item.nodeID = "7a1f"

    let requests = ReminderScheduler.requests(
        for: [item], after: beforeReminders,
        noteIDs: ["Area/Board.canvas": "3f2c1b4a-0000-4000-8000-000000000000"]
    )
    let request = try #require(requests.first)
    let route = try #require(request.content.userInfo[ReminderScheduler.routeKey] as? String)
    #expect(URL(string: route).flatMap(PergamenumRoute.init)
        == .canvas(path: "Area/Board.canvas", nodeID: "7a1f"))
}
