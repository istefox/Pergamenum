import Foundation
import Testing
@testable import Pergamenum

// The opens that bring the person to a place (n1-seams R-09, R-10, R-12, R-13): today's note,
// an event's note, the Tags pane on one tag, the Oggi pane on one day. Hosted `CommandActions`,
// built the way `OpenLinkUnresolvedTests` builds them.

@MainActor
private func makeActions(vault root: URL) async -> CommandActions {
    let vault = VaultController(recents: .volatile(), openTabs: .volatile())
    await vault.open(root)
    let calendarStore = EventKitStore()
    let capture = CaptureController()
    return CommandActions(
        navigation: Navigation(),
        vault: vault,
        day: DayController(store: calendarStore, vault: vault),
        calendar: calendarStore,
        capturePanel: CapturePanel(
            controller: capture,
            session: { vault.session },
            theme: { ThemeEngine().current },
            shortcutCaption: { nil }
        ),
        history: NavigationHistory(),
        pasteboard: .volatile()
    )
}

private func onDisk(_ root: URL, _ path: String) throws -> String {
    try String(contentsOf: root.appending(path: path, directoryHint: .notDirectory), encoding: .utf8)
}

// MARK: - Cmd+Shift+D (R-09)

@MainActor
@Test func todayNoteFromAnotherPaneLeavesTheNotePaneWithTheNoteFocused() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let actions = await makeActions(vault: root)
    actions.navigation.pane = .tasks

    await actions.openTodayNote()

    let expected = actions.vault.dailyNotePath(for: .today)
    #expect(actions.navigation.pane == .notes) // (n1-seams R-09)
    #expect(actions.vault.openNote?.relativePath == expected) // (n1-seams R-09)
    actions.vault.close()
}

@MainActor
@Test func todayNoteFromTheTodayPaneStaysThere() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let actions = await makeActions(vault: root)
    actions.navigation.pane = .today

    await actions.openTodayNote()

    #expect(actions.navigation.pane == .today) // (n1-seams R-09)
    #expect(actions.vault.openNote?.relativePath == actions.vault.dailyNotePath(for: .today)) // (n1-seams R-09)
    actions.vault.close()
}

@MainActor
@Test func aMissingDailyNoteIsCreated() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let actions = await makeActions(vault: root)
    actions.navigation.pane = .workspace
    let path = actions.vault.dailyNotePath(for: .today)
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false)))

    await actions.openTodayNote()

    let created = root.appending(path: path).path(percentEncoded: false)
    #expect(FileManager.default.fileExists(atPath: created)) // (n1-seams R-09)
    #expect(actions.navigation.pane == .notes) // (n1-seams R-09)
    actions.vault.close()
}

@MainActor
@Test func aFailingDailyNoteRecordsAProblemAndSwitchesNothing() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    // The daily folder exists but cannot be written into, and holds no note for today.
    try vault.write("---\ndate: 2020-01-01\ntags:\n  - type-note\n---\n", to: "Calendar/20200101.md")
    let actions = await makeActions(vault: root)
    actions.navigation.pane = .tasks

    try await withReadOnlyFolder(root, "Calendar") {
        await actions.openTodayNote()
    }

    #expect(actions.vault.problems.contains { $0.hasPrefix("nota del giorno") }) // (n1-seams R-09)
    #expect(actions.navigation.pane == .tasks) // (n1-seams R-09)
    #expect(actions.vault.openNote == nil) // (n1-seams R-09)
    actions.vault.close()
}

// MARK: - The event note (R-10)

@MainActor
@Test func anEventNoteFromTheTodayPaneLeavesForTheNotePaneWithTheNoteFocused() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let actions = await makeActions(vault: root)
    actions.navigation.pane = .today
    let thursday = CalendarDate(iso: "2026-08-20")!

    let path = await actions.openEventNote(
        for: "Riunione tecnica", on: thursday, start: nil, end: nil, attendees: []
    )

    let created = try #require(path)
    #expect(actions.navigation.pane == .notes) // (n1-seams R-10)
    #expect(actions.vault.openNote?.relativePath == created) // (n1-seams R-10)
    actions.vault.close()
}

@MainActor
@Test func theEventNoteHasTheBytesTask1Pinned() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let actions = await makeActions(vault: root)
    actions.navigation.pane = .today
    let thursday = CalendarDate(iso: "2026-08-20")!

    let path = await actions.openEventNote(
        for: "Riunione tecnica", on: thursday, start: nil, end: nil, attendees: []
    )

    let created = try #require(path)
    let expected = "---\ndate: 2026-08-20\ntags:\n  - type-note\n  - status-inbox\n---\n\n"
        + EventNote.body(eventTitle: "Riunione tecnica", start: nil, end: nil, attendees: [], day: thursday)
    #expect(try onDisk(root, created) == expected) // (n1-seams R-10)
    actions.vault.close()
}

// MARK: - A tag opens the Tags pane (R-12)

@MainActor
@Test func openingATagShowsTheTagsPaneAndHandsOverTheFilterOnce() async throws {
    let vault = try TemporaryVault()
    let actions = await makeActions(vault: vault.root)
    actions.navigation.pane = .notes
    let acme = Pergamenum.Tag("#client-acme")!

    actions.open(tag: acme)

    #expect(actions.navigation.pane == .tags) // (n1-seams R-12)
    #expect(actions.navigation.takeTagFilter() == acme) // (n1-seams R-12)
    #expect(actions.navigation.takeTagFilter() == nil) // (n1-seams R-12)
    actions.vault.close()
}

@MainActor
@Test func aSecondTagReplacesTheFirstAndNothingAccumulates() async throws {
    let vault = try TemporaryVault()
    let actions = await makeActions(vault: vault.root)
    let acme = Pergamenum.Tag("#client-acme")!
    let gomma = Pergamenum.Tag("#topic-gomma")!

    actions.open(tag: acme)
    actions.open(tag: gomma)

    #expect(actions.navigation.takeTagFilter() == gomma) // (n1-seams R-12)
    #expect(actions.navigation.takeTagFilter() == nil) // (n1-seams R-12)
    actions.vault.close()
}

@MainActor
@Test func theTagFilterRequestCarriesAFreshIdForTheSameTagOpenedTwice() async throws {
    // The pane observes the request, not the tag: opening the same tag a second time (after the
    // first was consumed) must still be a change, or the second click would do nothing.
    let vault = try TemporaryVault()
    let actions = await makeActions(vault: vault.root)
    let acme = Pergamenum.Tag("#client-acme")!

    actions.open(tag: acme)
    let first = actions.navigation.tagFilter
    _ = actions.navigation.takeTagFilter()
    actions.open(tag: acme)
    let second = actions.navigation.tagFilter

    #expect(first != nil) // (n1-seams R-12)
    #expect(second != nil) // (n1-seams R-12)
    #expect(first?.id != second?.id) // (n1-seams R-12)
    actions.vault.close()
}

// MARK: - A day opens the Oggi pane (R-13)

@MainActor
@Test func openingADayShowsTheTodayPaneOnThatDay() async throws {
    let vault = try TemporaryVault()
    let actions = await makeActions(vault: vault.root)
    actions.navigation.pane = .notes
    actions.day.show(CalendarDate(iso: "2026-01-01")!)
    let target = CalendarDate(iso: "2026-10-12")!
    let scale = actions.day.scale

    actions.open(day: target)

    #expect(actions.navigation.pane == .today) // (n1-seams R-13)
    #expect(actions.day.day == target) // (n1-seams R-13)
    #expect(actions.day.scale == scale) // (n1-seams R-13)
    actions.vault.close()
}
