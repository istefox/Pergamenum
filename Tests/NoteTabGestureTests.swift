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
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
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

// MARK: The arrangement survives a relaunch (ADR-0012 D10)

@MainActor
@Test func theOpenTabsComeBackWithTheirOrderAndTheirFocus() async throws {
    let vault = try TemporaryVault()
    // One store across two controllers is what a relaunch is: the same Mac, the same vault,
    // a different process.
    let store = OpenTabsStore.volatile()
    try vault.write(first, to: "Nexion.md")
    try vault.write(second, to: "Progetti/Sospensione.md")

    let before = VaultController(recents: .volatile(), openTabs: store)
    await before.open(vault.root)
    before.openNoteInNewTab(at: "Nexion.md")
    before.openNoteInNewTab(at: "Progetti/Sospensione.md")
    let firstTab = try #require(before.tabs.first?.id)
    before.focusTab(firstTab)
    before.close()

    let after = VaultController(recents: .volatile(), openTabs: store)
    await after.open(vault.root)

    #expect(after.tabs.map(\.note.relativePath) == ["Nexion.md", "Progetti/Sospensione.md"])
    #expect(after.openNote?.relativePath == "Nexion.md")
    after.close()
}

@MainActor
@Test func aNoteDeletedBetweenTwoLaunchesIsSkipped() async throws {
    let vault = try TemporaryVault()
    let store = OpenTabsStore.volatile()
    try vault.write(first, to: "Nexion.md")
    try vault.write(second, to: "Progetti/Sospensione.md")

    let before = VaultController(recents: .volatile(), openTabs: store)
    await before.open(vault.root)
    before.openNoteInNewTab(at: "Nexion.md")
    before.openNoteInNewTab(at: "Progetti/Sospensione.md")
    before.close()
    try FileManager.default.removeItem(at: vault.root.appending(path: "Nexion.md"))

    let after = VaultController(recents: .volatile(), openTabs: store)
    await after.open(vault.root)

    // Skipped, not reported: a note deleted between two launches is not a failure, and a
    // dialog about it at every start would be.
    #expect(after.tabs.map(\.note.relativePath) == ["Progetti/Sospensione.md"])
    after.close()
}

@MainActor
@Test func aPreviewTabIsStillAPreviewAfterARelaunch() async throws {
    let vault = try TemporaryVault()
    let store = OpenTabsStore.volatile()
    try vault.write(first, to: "Nexion.md")

    let before = VaultController(recents: .volatile(), openTabs: store)
    await before.open(vault.root)
    before.openNote(at: "Nexion.md")
    #expect(before.focusedTab?.isPreview == true)
    before.close()

    let after = VaultController(recents: .volatile(), openTabs: store)
    await after.open(vault.root)

    #expect(after.focusedTab?.isPreview == true)
    after.close()
}

@MainActor
@Test func twoVaultsRememberTheirOwnTabs() async throws {
    let one = try TemporaryVault()
    let other = try TemporaryVault()
    let store = OpenTabsStore.volatile()
    try one.write(first, to: "Nexion.md")
    try other.write(second, to: "Altra.md")

    let controller = VaultController(recents: .volatile(), openTabs: store)
    await controller.open(one.root)
    controller.openNoteInNewTab(at: "Nexion.md")
    controller.close()
    await controller.open(other.root)
    controller.openNoteInNewTab(at: "Altra.md")
    controller.close()

    await controller.open(one.root)
    #expect(controller.tabs.map(\.note.relativePath) == ["Nexion.md"])
    controller.close()
}

@MainActor
@Test func aNewNoteOpensInATabOfItsOwn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    #expect(controller.focusedTab?.isPreview == true)

    _ = try controller.createNote(title: "Curva di trasmissibilità", date: .today)

    #expect(controller.tabs.count == 2)
    #expect(controller.focusedTab?.isPreview == false)
    #expect(controller.openNote?.title == "Curva di trasmissibilità")
    // And the note that was in the preview is still there rather than replaced.
    #expect(controller.tabs.first?.note.relativePath == "Nexion.md")
    controller.close()
}

// MARK: The recent notes (ADR-0012, slice 4)

@MainActor
@Test func opensAreRememberedNewestFirstWithNoRepeats() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)

    controller.openNote(at: "Nexion.md")
    controller.openNoteInNewTab(at: "Progetti/Sospensione.md")
    controller.openNote(at: "Nexion.md")

    // Going back to a note moves it to the top rather than listing it twice: the quick
    // switcher offers each row as a place to go, and the same place twice is one wasted row.
    #expect(controller.recentNotePaths == ["Nexion.md", "Progetti/Sospensione.md"])
    controller.close()
}

@MainActor
@Test func theRecentListStopsAtTen() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    for number in 1...12 {
        try vault.write("---\ndate: 2026-08-19\ntags:\n  - type-note\n---\n\n\(number).\n",
                        to: "Nota \(number).md")
        controller.openNote(at: "Nota \(number).md")
    }

    #expect(controller.recentNotePaths.count == VaultController.recentNoteLimit)
    #expect(controller.recentNotePaths.first == "Nota 12.md")
    #expect(!controller.recentNotePaths.contains("Nota 1.md"))
    controller.close()
}

@MainActor
@Test func theRecentListFollowsARenameAndDropsATrashedNote() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    controller.openNoteInNewTab(at: "Progetti/Sospensione.md")

    controller.movedNote(from: "Nexion.md", to: "Archivio/Nexion.md")
    #expect(controller.recentNotePaths.contains("Archivio/Nexion.md"))
    #expect(!controller.recentNotePaths.contains("Nexion.md"))

    // A row pointing at a note in the trash opens nothing, which is worse than no row.
    controller.trashedNote(at: "Progetti/Sospensione.md")
    #expect(!controller.recentNotePaths.contains("Progetti/Sospensione.md"))
    controller.close()
}
