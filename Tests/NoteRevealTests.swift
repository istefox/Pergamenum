import Foundation
import Testing
@testable import Pergamenum

// The editor takes the keyboard when a note is shown to the person on purpose (note-workflow
// R-04, R-05): an event note opened from the timeline, and «Apri» on the Workspace sheet's
// confirmation. One request, in `closeRequest`'s shape: asked for on `VaultController`, taken
// once by the column that owns it. Cmd+Shift+D asks for nothing (R-04 names the event note only,
// plan gate G5).
//
// Hosted `CommandActions`, built the way `CommandActionNavigationTests` builds them.

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

private let thursday = CalendarDate(iso: "2026-08-20")!

// MARK: - The request itself

@MainActor
@Test func aRequestIsTakenOnceByTheFocusedColumnAndNeverByAnother() async throws {
    let vault = try TemporaryVault()
    let actions = await makeActions(vault: vault.root)
    let controller = actions.vault
    let focused = controller.focusedColumnIndex

    controller.requestEditorFocus()

    // The other column asking first does not use it up.
    #expect(controller.takeEditorFocusRequest(forColumn: focused + 1) == false) // (note-workflow R-04)
    #expect(controller.takeEditorFocusRequest(forColumn: focused) == true) // (note-workflow R-04)
    #expect(controller.takeEditorFocusRequest(forColumn: focused) == false) // (note-workflow R-04)
    controller.close()
}

@MainActor
@Test func nothingRequestedMeansNothingToTake() async throws {
    let vault = try TemporaryVault()
    let actions = await makeActions(vault: vault.root)

    #expect(actions.vault.takeEditorFocusRequest(forColumn: actions.vault.focusedColumnIndex) == false)
    actions.vault.close()
}

@MainActor
@Test func eachRequestChangesTheCounterTheColumnsWatch() async throws {
    // `EditorColumnView` answers `.onChange(of: vault.editorFocusRequest)` (the plan's Task 6): a
    // request that left the counter alone would wake no column.
    let vault = try TemporaryVault()
    let actions = await makeActions(vault: vault.root)
    let controller = actions.vault
    let before = controller.editorFocusRequest

    controller.requestEditorFocus()
    let first = controller.editorFocusRequest
    _ = controller.takeEditorFocusRequest(forColumn: controller.focusedColumnIndex)
    controller.requestEditorFocus()

    #expect(first != before) // (note-workflow R-04)
    #expect(controller.editorFocusRequest != first) // (note-workflow R-04)
    controller.close()
}

// MARK: - The event note (R-04)

@MainActor
@Test func anEventNoteFromTheTodayPaneOpensInTheNotePaneAndRequestsTheCaretOnce() async throws {
    let vault = try TemporaryVault()
    let actions = await makeActions(vault: vault.root)
    actions.navigation.pane = .today

    let path = await actions.openEventNote(
        for: "Riunione tecnica", on: thursday, start: nil, end: nil, attendees: []
    )

    #expect(path != nil)
    // Session 2's delivery, relied on.
    #expect(actions.navigation.pane == .notes) // (note-workflow R-04)
    let focused = actions.vault.focusedColumnIndex
    #expect(actions.vault.takeEditorFocusRequest(forColumn: focused + 1) == false) // (note-workflow R-04)
    #expect(actions.vault.takeEditorFocusRequest(forColumn: focused) == true) // (note-workflow R-04)
    #expect(actions.vault.takeEditorFocusRequest(forColumn: focused) == false) // (note-workflow R-04)
    actions.vault.close()
}

@MainActor
@Test func aFailedEventNoteRequestsNoCaretAndSwitchesNothing() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    // The daily folder exists but cannot be written into, and holds no note for this event, so
    // the note cannot be created.
    try vault.write("---\ndate: 2020-01-01\ntags:\n  - type-note\n---\n", to: "Calendar/20200101.md")
    let actions = await makeActions(vault: root)
    actions.navigation.pane = .today

    let path = try await withReadOnlyFolder(root, "Calendar") {
        await actions.openEventNote(
            for: "Riunione tecnica", on: thursday, start: nil, end: nil, attendees: []
        )
    }

    #expect(path == nil)
    #expect(actions.navigation.pane == .today) // (note-workflow R-04)
    let focused = actions.vault.focusedColumnIndex
    #expect(actions.vault.takeEditorFocusRequest(forColumn: focused) == false) // (note-workflow R-04)
    actions.vault.close()
}

// MARK: - «Apri» (R-05)

@MainActor
@Test func showInNotePaneOpensTheNoteInANewTabOfTheFocusedColumnAndAsksForTheCaret() async throws {
    let vault = try TemporaryVault()
    try vault.write(quitNote("Prova."), to: "Prova.md")
    try vault.write(quitNote("Altra."), to: "Altra.md")
    let actions = await makeActions(vault: vault.root)
    actions.navigation.pane = .workspace
    actions.vault.openNote(at: "Prova.md")
    let column = actions.vault.focusedColumnIndex
    let tabsBefore = actions.vault.columns[column].tabs.count

    actions.showInNotePane("Altra.md")

    #expect(actions.navigation.pane == .notes) // (note-workflow R-05)
    #expect(actions.vault.columns[column].tabs.count == tabsBefore + 1) // (note-workflow R-05)
    #expect(actions.vault.columns[column].active?.note.relativePath == "Altra.md") // (note-workflow R-05)
    #expect(actions.vault.focusedColumnIndex == column) // (note-workflow R-05)
    // One request pending, for the column the tab is in.
    #expect(actions.vault.takeEditorFocusRequest(forColumn: column) == true) // (note-workflow R-05)
    #expect(actions.vault.takeEditorFocusRequest(forColumn: column) == false) // (note-workflow R-05)
    actions.vault.close()
}

// MARK: - Cmd+Shift+D asks for no caret (gate G5)

@MainActor
@Test func todayNoteFromAnotherPaneRequestsNoCaret() async throws {
    // R-04 asks for the caret on the event note only; giving Cmd+Shift+D the same request is
    // one line and a decision (gate G5), so today it must not happen.
    let vault = try TemporaryVault()
    let actions = await makeActions(vault: vault.root)
    actions.navigation.pane = .tasks

    await actions.openTodayNote()

    #expect(actions.navigation.pane == .notes)
    let focused = actions.vault.focusedColumnIndex
    #expect(actions.vault.takeEditorFocusRequest(forColumn: focused) == false) // (note-workflow R-04)
    actions.vault.close()
}
