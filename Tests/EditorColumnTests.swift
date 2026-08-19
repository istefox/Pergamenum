import Foundation
import Testing
@testable import Pergamenum

// The split editor (ADR-0012 D4): two columns, each with its own tabs and its own note in
// front, and one of them holding the focus that everything else follows.

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
private func controller(
    _ vault: borrowing TemporaryVault,
    openTabs: OpenTabsStore = .volatile()
) async throws -> VaultController {
    try vault.write(first, to: "Nexion.md")
    try vault.write(second, to: "Progetti/Sospensione.md")
    let controller = VaultController(recents: .volatile(), openTabs: openTabs)
    await controller.open(vault.root)
    return controller
}

// MARK: Splitting

@MainActor
@Test func splittingPutsTheOpenNoteOnTheRightAndFocusesIt() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")

    controller.splitEditor()

    #expect(controller.columns.count == 2)
    #expect(controller.focusedColumnIndex == 1)
    #expect(controller.openNote?.relativePath == "Nexion.md")
    // In a tab of its own and stable: it was split *to* be kept beside something.
    #expect(controller.focusedTab?.isPreview == false)
    #expect(controller.columns[0].tabs.count == 1)
    controller.close()
}

@MainActor
@Test func splittingTwiceDoesNotMakeAThirdColumn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    controller.splitEditor()

    controller.splitEditor()

    #expect(controller.columns.count == 2)
    controller.close()
}

@MainActor
@Test func splittingWithNothingOpenGivesAnEmptySecondColumn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)

    controller.splitEditor()

    #expect(controller.columns.count == 2)
    #expect(controller.openNote == nil)
    controller.close()
}

// MARK: Each column keeps its own

@MainActor
@Test func aTabOpenedInOneColumnDoesNotAppearInTheOther() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    controller.splitEditor()

    controller.openNote(at: "Progetti/Sospensione.md")

    #expect(controller.columns[0].tabs.map(\.note.relativePath) == ["Nexion.md"])
    #expect(controller.columns[1].tabs.map(\.note.relativePath).contains("Progetti/Sospensione.md"))
    #expect(controller.openNote?.relativePath == "Progetti/Sospensione.md")
    controller.close()
}

@MainActor
@Test func aNoteOpenInTheOtherColumnStillOpensInThisOne() async throws {
    // The mirror image of the fix made this morning, and the reason it needs a test of its
    // own: within a column, clicking a note that is already open goes to its tab. Across
    // columns it must not, or splitting the editor to compare two notes - the whole point of
    // splitting - would keep bouncing the focus back to the other side.
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    controller.splitEditor()
    controller.openNote(at: "Progetti/Sospensione.md")

    controller.openNote(at: "Nexion.md")

    #expect(controller.focusedColumnIndex == 1)
    #expect(controller.columns[1].tabs.map(\.note.relativePath).contains("Nexion.md"))
    controller.close()
}

@MainActor
@Test func foldsAndReadingModeBelongToTheColumnTheyWereSetIn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    controller.toggleFold(1)
    controller.isReadingMode = true

    controller.splitEditor()

    // The right-hand copy starts clean: it is the same note, not the same tab.
    #expect(controller.foldedEntries.isEmpty)
    #expect(controller.isReadingMode == false)

    controller.focusColumn(0)
    #expect(controller.foldedEntries == [1])
    #expect(controller.isReadingMode)
    controller.close()
}

// MARK: Focus and closing

@MainActor
@Test func focusingAColumnThatIsNotThereChangesNothing() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")

    controller.focusColumn(4)

    #expect(controller.focusedColumnIndex == 0)
    #expect(controller.openNote?.relativePath == "Nexion.md")
    controller.close()
}

@MainActor
@Test func closingAColumnHandsTheFocusToTheOneLeft() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    controller.splitEditor()
    controller.openNote(at: "Progetti/Sospensione.md")

    controller.closeColumn(1)

    #expect(controller.columns.count == 1)
    #expect(controller.focusedColumnIndex == 0)
    #expect(controller.openNote?.relativePath == "Nexion.md")
    controller.close()
}

@MainActor
@Test func theLastColumnCannotBeClosed() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")

    controller.closeColumn(0)

    #expect(controller.columns.count == 1)
    #expect(controller.openNote?.relativePath == "Nexion.md")
    controller.close()
}

// MARK: The split survives a relaunch

@MainActor
@Test func bothColumnsComeBackWithTheFocusWhereItWas() async throws {
    let vault = try TemporaryVault()
    let store = OpenTabsStore.volatile()

    let before = try await controller(vault, openTabs: store)
    before.openNote(at: "Nexion.md")
    before.splitEditor()
    before.openNote(at: "Progetti/Sospensione.md")
    before.focusColumn(0)
    before.close()

    let after = try await controller(vault, openTabs: store)

    #expect(after.columns.count == 2)
    #expect(after.columns[0].tabs.map(\.note.relativePath) == ["Nexion.md"])
    #expect(after.columns[1].tabs.map(\.note.relativePath).contains("Progetti/Sospensione.md"))
    #expect(after.focusedColumnIndex == 0)
    after.close()
}

@MainActor
@Test func aDeskThatWasNotSplitDoesNotComeBackSplit() async throws {
    let vault = try TemporaryVault()
    let store = OpenTabsStore.volatile()

    let before = try await controller(vault, openTabs: store)
    before.openNote(at: "Nexion.md")
    before.close()

    let after = try await controller(vault, openTabs: store)

    #expect(after.columns.count == 1)
    after.close()
}

@MainActor
@Test func aSessionWrittenBeforeTheSplitReadsAsEmpty() throws {
    // The stored shape changed when columns arrived, and the old blob no longer decodes. It
    // has to read back as nothing rather than throw at launch: this costs one arrangement,
    // and the notes are on disk either way.
    let vault = try TemporaryVault()
    let defaults = try #require(UserDefaults(suiteName: "pergamenum.tests.\(UUID())"))
    let old = #"{"entries":[{"path":"Nexion.md","isPreview":false}],"activePath":"Nexion.md"}"#
    defaults.set(Data(old.utf8), forKey: OpenTabsStore.key(for: vault.root))

    let session = OpenTabsStore(defaults: defaults).session(for: vault.root)

    #expect(session.columns.isEmpty)
    #expect(session.focusedColumn == 0)
}

@MainActor
@Test func typingInASplitColumnStopsItsTabFromBeingRecycled() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    controller.splitEditor()
    // Back in the left column, on a preview tab, and write in it.
    controller.focusColumn(0)
    controller.openNote(at: "Progetti/Sospensione.md")
    #expect(controller.focusedTab?.isPreview == true)
    controller.updateOpenNoteText("Scritto a sinistra.\n")

    // The next note opened in this column goes beside it, not over it.
    controller.openNote(at: "Nexion.md")

    #expect(controller.columns[0].tabs.count == 2)
    #expect(controller.columns[0].tabs.contains { $0.note.relativePath == "Progetti/Sospensione.md" })
    controller.close()
}

// MARK: The focus contract (ADR-0012 D4)

@MainActor
@Test func aNoteOpensInTheColumnThatHasTheFocus() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    controller.splitEditor()
    #expect(controller.focusedColumnIndex == 1)

    // The focus moves back to the left, and that is the only thing that decides where the
    // next note lands. On screen this is the click in the text; here it is the one line the
    // click ends up calling.
    controller.focusColumn(0)
    controller.openNote(at: "Progetti/Sospensione.md")

    #expect(controller.columns[0].tabs.count == 1)
    #expect(controller.columns[0].active?.note.relativePath == "Progetti/Sospensione.md")
    #expect(controller.columns[1].tabs.count == 1)
    #expect(controller.columns[1].active?.note.relativePath == "Nexion.md")
    controller.close()
}

@MainActor
@Test func aTabOfTheOtherColumnCannotBeBroughtToTheFront() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    controller.splitEditor()
    let mine = try #require(controller.columns[1].activeID)
    controller.focusColumn(0)
    controller.openNote(at: "Progetti/Sospensione.md")
    let hers = try #require(controller.columns[0].activeID)

    // The id belongs to the right hand column; the focused one is the left. Ignored rather
    // than reached across: every door on a tab answers for the focused column only.
    controller.focusTab(mine)

    #expect(controller.focusedColumnIndex == 0)
    #expect(controller.columns[0].activeID == hers)
    controller.close()
}
