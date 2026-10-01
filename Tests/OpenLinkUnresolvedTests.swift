import Foundation
import Testing
@testable import Pergamenum

// PG-356: a Cmd+click on a wikilink no note answers to reached `CommandActions.open(link:)`
// and did nothing - no tab, no pane switch, no word - so it read as a click that never
// arrived. An unresolved title now records a problem, like an unresolved board already did.

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

private let trust = """
---
date: 2026-10-01
tags:
  - type-note
---

Trust.
"""

@MainActor
@Test func openingAnUnresolvedNoteLinkRecordsAProblemAndOpensNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(trust, to: "TRUST.md")
    let actions = await makeActions(vault: vault.root)
    actions.navigation.pane = .workspace

    actions.open(link: "TRUST.md")

    #expect(actions.vault.problems.contains("nota non trovata: TRUST.md"))
    #expect(actions.vault.openNote == nil)
    #expect(actions.navigation.pane == .workspace)
}

@MainActor
@Test func openingAResolvedNoteLinkRecordsNoProblem() async throws {
    let vault = try TemporaryVault()
    try vault.write(trust, to: "TRUST.md")
    let actions = await makeActions(vault: vault.root)
    actions.navigation.pane = .workspace

    actions.open(link: "TRUST")

    #expect(actions.vault.problems.isEmpty)
    #expect(actions.vault.openNote?.relativePath == "TRUST.md")
    #expect(actions.navigation.pane == .notes)
}
