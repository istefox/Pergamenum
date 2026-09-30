import Foundation
import Testing
@testable import Pergamenum

// «Chiudi tab» (Cmd+W) on a tab with unsaved edits (#708). The menu used to close the focused tab
// outright, so the edits were gone with no question; only the tab's close button asked. The
// dialog itself is SwiftUI and checked by hand; what is pinned here is that the command no longer
// closes a dirty tab and hands it to the column instead, and that a clean tab still closes at once.

private let note = """
---
date: 2026-09-30
tags:
  - type-note
---

Testo originale.
"""

@MainActor
private func setUp(_ vault: borrowing TemporaryVault) async throws -> (CommandActions, VaultController) {
    try vault.write(note, to: "Uno.md")
    try vault.write(note, to: "Due.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNote(at: "Uno.md")
    controller.openNoteInNewTab(at: "Due.md")
    let calendar = EventKitStore()
    let capture = CaptureController()
    let actions = CommandActions(
        navigation: Navigation(),
        vault: controller,
        day: DayController(store: calendar, vault: controller),
        calendar: calendar,
        capturePanel: CapturePanel(
            controller: capture,
            session: { controller.session },
            theme: { ThemeEngine().current },
            shortcutCaption: { nil }
        ),
        history: NavigationHistory()
    )
    return (actions, controller)
}

@MainActor
@Test func closeTabOnADirtyTabAsksInsteadOfClosing() async throws {
    let vault = try TemporaryVault()
    let (actions, controller) = try await setUp(vault)
    controller.updateOpenNoteText(note + "Non salvato.\n")
    let dirty = try #require(controller.focusedTab)
    actions.navigation.pane = .workspace

    actions.run(.closeTab)

    // The tab and its unsaved text are still there: nothing closed before the question.
    #expect(controller.columns[0].tabs.count == 2)
    #expect(controller.focusedTab?.id == dirty.id)
    #expect(controller.focusedTab?.note.hasUnsavedChanges == true)
    // The request names that tab and brings the Note pane forward, where the column can ask.
    #expect(actions.navigation.pendingCloseTabID == dirty.id)
    #expect(actions.navigation.pane == .notes)
    // Consumed once, so a view update cannot ask twice.
    #expect(actions.navigation.consumeCloseTabRequest() == dirty.id)
    #expect(actions.navigation.consumeCloseTabRequest() == nil)
    controller.close()
}

@MainActor
@Test func closeTabOnACleanTabClosesItAtOnce() async throws {
    let vault = try TemporaryVault()
    let (actions, controller) = try await setUp(vault)
    let clean = try #require(controller.focusedTab)

    actions.run(.closeTab)

    #expect(controller.columns[0].tabs.count == 1)
    #expect(!controller.columns[0].tabs.contains { $0.id == clean.id })
    #expect(actions.navigation.pendingCloseTabID == nil)
    controller.close()
}
