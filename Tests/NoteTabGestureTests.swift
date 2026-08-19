import Foundation
import Testing
@testable import Pergamenum

// What a tab does when it is asked to, rather than what it holds: the keys, the preview rule,
// and the file operations that have to reach a tab nobody is looking at.
//
// Split from `NoteTabTests` when that file passed the 400 lines SwiftLint warns at. Same two
// notes, same harness, and the same rule about opening at least two tabs: with one, every one
// of these passes against a version that resolves against the wrong tab.

private let first = """
---
date: 2026-08-19
tags:
  - type-note
---

## Premessa

Testo.
"""

private let second = """
---
date: 2026-08-19
tags:
  - type-note
---

## Dati

Altro testo.
"""

@MainActor
private func controller(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    try vault.write(first, to: "Nexion.md")
    try vault.write(second, to: "Progetti/Sospensione.md")
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)
    return controller
}

// MARK: The gestures (ADR-0012 D5)

@MainActor
@Test func reopeningBringsBackTheMostRecentlyClosedTab() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    controller.openNoteInNewTab(at: "Progetti/Sospensione.md")
    let second = try #require(controller.focusedTab?.id)
    controller.closeTab(second)

    controller.reopenClosedTab()

    #expect(controller.columns[0].tabs.count == 2)
    #expect(controller.openNote?.relativePath == "Progetti/Sospensione.md")
    // The stack empties as it is used, so a second Cmd+Shift+T does not reopen the same
    // note again.
    #expect(controller.closedTabPaths.isEmpty)
    controller.close()
}

@MainActor
@Test func aTabIsChosenByItsPositionAndNineMeansTheLast() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    try vault.write("---\ndate: 2026-08-19\ntags:\n  - type-note\n---\n\nTerza.\n", to: "Terza.md")
    await controller.rescan()
    controller.openNote(at: "Nexion.md")
    controller.openNoteInNewTab(at: "Progetti/Sospensione.md")
    controller.openNoteInNewTab(at: "Terza.md")

    controller.selectTab(1)
    #expect(controller.openNote?.relativePath == "Nexion.md")

    controller.selectTab(9)
    #expect(controller.openNote?.relativePath == "Terza.md")

    // A number past the end changes nothing rather than clearing the selection.
    controller.selectTab(7)
    #expect(controller.openNote?.relativePath == "Terza.md")
    controller.close()
}

@MainActor
@Test func cmdTSendsTheNextChosenNoteToATabOfItsOwn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")

    controller.beginNewTab()
    #expect(controller.isShowingQuickSwitcher)
    controller.openChosenNote(at: "Progetti/Sospensione.md")

    #expect(controller.columns[0].tabs.count == 2)
    // And the promise is spent: the next note chosen from the switcher opens in place,
    // which is what clicking one in the list has always done.
    controller.openChosenNote(at: "Nexion.md")
    #expect(controller.columns[0].tabs.count == 2)
    #expect(controller.openNote?.relativePath == "Nexion.md")
    controller.close()
}

// MARK: Preview tabs

@MainActor
@Test func browsingTheListReusesOneTabInsteadOfOpeningMany() async throws {
    // The reason preview tabs exist: before them a single click replaced whatever was in
    // front of you, and with tabs that would mean losing a stable tab to a stray click.
    let vault = try TemporaryVault()
    let controller = try await controller(vault)

    controller.openNote(at: "Nexion.md")
    controller.openNote(at: "Progetti/Sospensione.md")
    controller.openNote(at: "Nexion.md")

    #expect(controller.columns[0].tabs.count == 1)
    #expect(controller.focusedTab?.isPreview == true)
    #expect(controller.openNote?.relativePath == "Nexion.md")
    controller.close()
}

@MainActor
@Test func aStableTabIsNotTouchedByTheNextClick() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    let stable = try #require(controller.focusedTab?.id)
    controller.makeStable(stable)

    controller.openNote(at: "Progetti/Sospensione.md")

    #expect(controller.columns[0].tabs.count == 2)
    #expect(controller.columns[0].tabs.first?.id == stable)
    #expect(controller.columns[0].tabs.first?.note.relativePath == "Nexion.md")
    #expect(controller.focusedTab?.isPreview == true)
    controller.close()
}

@MainActor
@Test func typingInAPreviewTabMakesItStay() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    #expect(controller.focusedTab?.isPreview == true)

    controller.updateOpenNoteText("Scritto qualcosa.\n")

    #expect(controller.focusedTab?.isPreview == false)
    // And the proof that it stayed: the next click opens beside it rather than over it.
    controller.openNote(at: "Progetti/Sospensione.md")
    #expect(controller.columns[0].tabs.count == 2)
    controller.close()
}

@MainActor
@Test func openingInANewTabNeverMakesAPreview() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)

    controller.openNoteInNewTab(at: "Nexion.md")

    #expect(controller.focusedTab?.isPreview == false)
    controller.close()
}

// MARK: A note is not opened twice

@MainActor
@Test func clickingANoteAlreadyOpenGoesToItsTab() async throws {
    // Seen on screen on 2026-08-19: the note was open in a stable tab, and the click loaded
    // it into the preview tab as well, so the same note sat in two tabs at once.
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNoteInNewTab(at: "Nexion.md")
    let stable = try #require(controller.focusedTab?.id)
    controller.openNoteInNewTab(at: "Progetti/Sospensione.md")

    controller.openNote(at: "Nexion.md")

    #expect(controller.columns[0].tabs.count == 2)
    #expect(controller.focusedTab?.id == stable)
    controller.close()
}

@MainActor
@Test func goingBackToAnOpenNoteKeepsItsUnsavedText() async throws {
    // The reason the check above is not merely tidiness: re-reading the note to show it
    // again would overwrite a buffer nobody had saved.
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNoteInNewTab(at: "Nexion.md")
    controller.updateOpenNoteText("Lavoro non salvato.\n")
    controller.openNoteInNewTab(at: "Progetti/Sospensione.md")

    controller.openNote(at: "Nexion.md")

    #expect(controller.openNote?.text == "Lavoro non salvato.\n")
    #expect(controller.openNote?.hasUnsavedChanges == true)
    controller.close()
}

// MARK: Renaming and trashing reach every tab

@MainActor
@Test func renamingANoteFollowsItInTheTabThatShowsIt() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNoteInNewTab(at: "Nexion.md")
    controller.openNoteInNewTab(at: "Progetti/Sospensione.md")

    // Renaming the note in the tab that is *not* focused, which is the case a single open
    // note could never produce.
    controller.movedNote(from: "Nexion.md", to: "Progetti/Sospensione.md")

    #expect(controller.tabs.first?.note.relativePath == "Progetti/Sospensione.md")
    controller.close()
}

@MainActor
@Test func trashingANoteClosesItsTabAndForgetsIt() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNoteInNewTab(at: "Nexion.md")
    controller.openNoteInNewTab(at: "Progetti/Sospensione.md")
    let doomed = try #require(controller.tabs.first?.id)
    controller.closeTab(doomed)
    controller.reopenClosedTab()

    controller.trashedNote(at: "Nexion.md")

    #expect(controller.tabs.contains { $0.note.relativePath == "Nexion.md" } == false)
    // And Cmd+Shift+T does not offer back a note that is in the trash.
    #expect(controller.closedTabPaths.contains("Nexion.md") == false)
    controller.close()
}
