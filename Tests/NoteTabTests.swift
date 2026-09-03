import Foundation
import Testing
@testable import Pergamenum

// The first slice of M10 (ADR-0012 D2): more than one note open, each with its own buffer
// and its own folds, behind a facade that still answers to `openNote`.
//
// **Every test here opens at least two tabs**, which is the point rather than thoroughness.
// With one tab the facade is indistinguishable from the property it replaced, so a suite that
// opens one note would pass against a version that resolves against the wrong tab entirely.

private let first = """
---
date: 2026-08-19
tags:
  - type-note
---

## Premessa

Testo.

## Conclusioni

Fine.
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

// MARK: Two buffers at once

@MainActor
@Test func aSecondTabKeepsTheFirstNotesUnsavedText() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    controller.updateOpenNoteText("Testo non salvato.\n")

    controller.openNoteInNewTab(at: "Progetti/Sospensione.md")

    #expect(controller.columns[0].tabs.count == 2)
    #expect(controller.openNote?.relativePath == "Progetti/Sospensione.md")
    // The point of a tab: the first note's unsaved work is still there, untouched, while
    // another note is the one on screen.
    let parked = try #require(controller.columns[0].tabs.first)
    #expect(parked.note.text == "Testo non salvato.\n")
    #expect(parked.note.hasUnsavedChanges)
    controller.close()
}

@MainActor
@Test func focusDecidesWhichNoteTheFacadeAnswersWith() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    let firstTab = try #require(controller.focusedTab?.id)
    controller.openNoteInNewTab(at: "Progetti/Sospensione.md")

    controller.focusTab(firstTab)

    #expect(controller.openNote?.relativePath == "Nexion.md")
    #expect(controller.isOpenNoteVisible)
    controller.close()
}

// MARK: Folds belong to the tab, not to the window

@MainActor
@Test func foldsSetInOneTabAreNotSeenInTheOther() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    let firstTab = try #require(controller.focusedTab?.id)
    controller.toggleFold(1)
    controller.currentOutlineEntry = 1

    controller.openNoteInNewTab(at: "Progetti/Sospensione.md")

    // The second tab starts clean, and asking the facade now asks *it*.
    #expect(controller.foldedEntries.isEmpty)
    #expect(controller.currentOutlineEntry == nil)

    controller.focusTab(firstTab)
    #expect(controller.foldedEntries == [1])
    #expect(controller.currentOutlineEntry == 1)
    controller.close()
}

@MainActor
@Test func showingAnotherNoteInTheSameTabClearsWhatDescribedTheOldOne() async throws {
    // What `VaultBrowser`'s deleted `onChange` used to do, moved to where a second tab
    // cannot break it: the folds are positions in an index, so they mean nothing once the
    // text under them is a different note.
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    let tab = try #require(controller.focusedTab?.id)
    controller.toggleFold(1)

    controller.openNote(at: "Progetti/Sospensione.md")

    #expect(controller.columns[0].tabs.count == 1)
    #expect(controller.focusedTab?.id == tab)
    #expect(controller.foldedEntries.isEmpty)
    controller.close()
}

// MARK: Closing

@MainActor
@Test func closingTheFocusedTabFallsBackToTheOneBeforeIt() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    controller.openNoteInNewTab(at: "Progetti/Sospensione.md")
    let second = try #require(controller.focusedTab?.id)

    controller.closeTab(second)

    #expect(controller.columns[0].tabs.count == 1)
    #expect(controller.openNote?.relativePath == "Nexion.md")
    controller.close()
}

@MainActor
@Test func closingATabThatIsNotFocusedLeavesTheFocusAlone() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    let firstTab = try #require(controller.focusedTab?.id)
    controller.openNoteInNewTab(at: "Progetti/Sospensione.md")

    controller.closeTab(firstTab)

    #expect(controller.columns[0].tabs.count == 1)
    #expect(controller.openNote?.relativePath == "Progetti/Sospensione.md")
    controller.close()
}

@MainActor
@Test func closingTheLastTabLeavesNothingOpen() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    controller.openNoteInNewTab(at: "Progetti/Sospensione.md")

    for tab in controller.columns[0].tabs { controller.closeTab(tab.id) }

    #expect(controller.columns[0].tabs.isEmpty)
    #expect(controller.openNote == nil)
    #expect(controller.isOpenNoteVisible == false)
    // The facade with nothing open answers the nothing-is-open value rather than trapping.
    #expect(controller.foldedEntries.isEmpty)
    controller.close()
}

@MainActor
@Test func closingTheVaultClosesEveryTab() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    controller.openNoteInNewTab(at: "Progetti/Sospensione.md")

    controller.close()

    #expect(controller.columns.count == 1)
    #expect(controller.columns[0].tabs.isEmpty)
    #expect(controller.openNote == nil)
}

// MARK: The writes still land where they should

@MainActor
@Test func savingWritesTheFocusedTabAndNotTheOther() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    controller.updateOpenNoteText(first + "\n\nAggiunta a Nexion.\n")
    controller.openNoteInNewTab(at: "Progetti/Sospensione.md")
    controller.updateOpenNoteText(second + "\n\nAggiunta alla Sospensione.\n")

    controller.saveOpenNote()

    let written = try String(contentsOf: vault.root.appending(path: "Progetti/Sospensione.md"), encoding: .utf8)
    #expect(written.contains("Aggiunta alla Sospensione."))
    let untouched = try String(contentsOf: vault.root.appending(path: "Nexion.md"), encoding: .utf8)
    #expect(!untouched.contains("Aggiunta a Nexion."))
    // And the other tab still holds its unsaved work rather than having lost it to the save.
    #expect(controller.columns[0].tabs.first?.note.hasUnsavedChanges == true)
    controller.close()
}
