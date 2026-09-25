import Foundation
import Testing
@testable import Pergamenum

// PG-211 / #415, `docs/adr/0056-every-tab-that-shows-the-note.md`. Three
// verbs read tab state through `openNote` (a facade over the *focused* tab only) or through the
// focused-column-only `tabs` computed property: `reconcile`, `movedNote`, `trashedNote`. A tab
// showing the same path in a background tab or in the other column (ADR-0012 §D4 allows two)
// never got the memo - no reload for a clean buffer, no ADR-0001 §D3.4 conflict banner for a
// dirty one, and the next save silently overwrote whatever changed on disk.
//
// All six Verifica cases from the plan; every write to disk that must be seen as *external*
// goes through `TemporaryVault.write`, never through `controller`/`session`, so it never lands
// in `selfWrittenHashes` (`VaultSession+Watching.swift:28`) and always reaches
// `updateTabs(showing:_:)` as a real `ExternalChange`.

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-09-23\ntags:\n  - type-note\n---\n\n\(body)\n"
}

@MainActor
private func controller(
    _ vault: borrowing TemporaryVault,
    store: OpenTabsStore = .volatile()
) async throws -> VaultController {
    try vault.write(note("A."), to: "A.md")
    try vault.write(note("B."), to: "B.md")
    let controller = VaultController(recents: .volatile(), openTabs: store)
    await controller.open(vault.root)
    return controller
}

// MARK: 1. A dirty tab in a NON-focused column is asked, never overwritten - RED before the fix

@MainActor
@Test func reconcileMarksAnExternalChangePendingOnADirtyTabInTheOtherColumn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "A.md")
    controller.splitEditor()
    // The pre-fix code reads only `openNote`, i.e. the *focused* tab - which right now is the
    // stable copy of A.md that `splitEditor` just put in column 2. Dirtying column 1's A.md and
    // then refocusing column 2 is exactly the shape the old single-column read could not see.
    controller.focusColumn(0)
    controller.updateOpenNoteText(note("A, non salvato."))
    let dirtyTab = try #require(controller.focusedTab)
    #expect(dirtyTab.note.hasUnsavedChanges)
    controller.focusColumn(1)
    #expect(controller.focusedColumnIndex == 1, "il fuoco resta sulla colonna 2 durante il reconcile")

    try vault.write(note("A, cambiato da un altro scrittore."), to: "A.md")
    await controller.reconcile(["A.md"])

    let backgroundTab = try #require(controller.columns[0].tabs.first)
    #expect(backgroundTab.note.externalChangePending == .text(note("A, cambiato da un altro scrittore.")))
    #expect(backgroundTab.note.text == note("A, non salvato."), "il testo non salvato non viene toccato")
    controller.close()
}

// MARK: 2. A clean tab in a NON-focused column adopts the new text - RED before the fix

@MainActor
@Test func reconcileReloadsACleanTabInTheOtherColumn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "A.md")
    controller.splitEditor()
    // Column 2 now holds a clean stable tab on A.md; refocus column 1, so column 2's tab -
    // clean, same path - is the one that must still be reached.
    controller.focusColumn(0)
    #expect(controller.focusedColumnIndex == 0)

    let newText = note("A, cambiato da un altro scrittore.")
    try vault.write(newText, to: "A.md")
    await controller.reconcile(["A.md"])

    let backgroundTab = try #require(controller.columns[1].tabs.first)
    #expect(!backgroundTab.note.hasUnsavedChanges)
    #expect(backgroundTab.note.text == newText)
    #expect(backgroundTab.note.savedText == newText)
    #expect(backgroundTab.note.externalChangePending == nil)
    controller.close()
}

// MARK: 3. A dirty tab in the SAME column but not the active one - RED before the fix

@MainActor
@Test func reconcileMarksAnExternalChangePendingOnADirtyBackgroundTabInTheSameColumn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "A.md")
    let backgroundID = try #require(controller.focusedTab?.id)
    controller.openNoteInNewTab(at: "B.md")
    #expect(controller.focusedTab?.note.relativePath == "B.md", "B è la tab attiva, A resta in secondo piano")

    // Dirtying a tab that is not the active one is not a gesture the app exposes - typing
    // always lands on the active tab - so this goes straight through the door `updateTab`
    // already offers to any tab of the focused column, exactly as a future feature (or a
    // caret restored to a background tab) would.
    controller.updateTab(backgroundID) { $0.note.text = note("A, non salvato in secondo piano.") }
    let backgroundBefore = try #require(controller.tabs.first { $0.id == backgroundID })
    #expect(backgroundBefore.note.hasUnsavedChanges)

    let newText = note("A, cambiato da un altro scrittore.")
    try vault.write(newText, to: "A.md")
    await controller.reconcile(["A.md"])

    let backgroundAfter = try #require(controller.tabs.first { $0.id == backgroundID })
    #expect(backgroundAfter.note.externalChangePending == .text(newText))
    #expect(backgroundAfter.note.text == note("A, non salvato in secondo piano."))
    controller.close()
}

// MARK: 4. Regression guard - the focused tab keeps its existing behaviour

@MainActor
@Test func reconcileStillMarksAnExternalChangePendingOnTheFocusedDirtyTab() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "A.md")
    controller.updateOpenNoteText(note("A, non salvato."))
    #expect(controller.openNote?.hasUnsavedChanges == true)

    let newText = note("A, cambiato da un altro scrittore.")
    try vault.write(newText, to: "A.md")
    await controller.reconcile(["A.md"])

    #expect(controller.openNote?.externalChangePending == .text(newText))
    #expect(controller.openNote?.text == note("A, non salvato."))
    controller.close()
}

@MainActor
@Test func reconcileStillReloadsTheFocusedCleanTab() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "A.md")
    #expect(controller.openNote?.hasUnsavedChanges == false)

    let newText = note("A, cambiato da un altro scrittore.")
    try vault.write(newText, to: "A.md")
    await controller.reconcile(["A.md"])

    #expect(controller.openNote?.text == newText)
    #expect(controller.openNote?.savedText == newText)
    #expect(controller.openNote?.externalChangePending == nil)
    controller.close()
}

// MARK: 5. `movedNote`/`trashedNote` reach a tab in the second column - RED before the fix

@MainActor
@Test func movedNoteFollowsATabInTheSecondColumn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "A.md")
    controller.splitEditor()
    // Refocus column 1, exactly like `NoteTabGestureTests.renamingANoteFollowsItInTheTabThatShowsIt`
    // does within one column: the note it follows to is an already-existing file, the same trick
    // that test uses, since `movedNote` only updates tabs and never touches disk itself.
    controller.focusColumn(0)

    controller.movedNote(from: "A.md", to: "B.md")

    #expect(controller.columns[1].tabs.first?.note.relativePath == "B.md")
    controller.close()
}

@MainActor
@Test func trashedNoteClosesATabInTheSecondColumn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "A.md")
    controller.splitEditor()
    controller.focusColumn(0)
    #expect(controller.columns[0].tabs.contains { $0.note.relativePath == "A.md" })
    #expect(controller.columns[1].tabs.contains { $0.note.relativePath == "A.md" })

    controller.trashedNote(at: "A.md")

    #expect(!controller.columns[0].tabs.contains { $0.note.relativePath == "A.md" })
    #expect(!controller.columns[1].tabs.contains { $0.note.relativePath == "A.md" })
    controller.close()
}

// MARK: 6. `closeTab` on a non-active tab now persists the session

@MainActor
@Test func closingANonActiveTabRemembersTheSession() async throws {
    let vault = try TemporaryVault()
    let store = OpenTabsStore.volatile()
    let controller = try await controller(vault, store: store)
    controller.openNoteInNewTab(at: "A.md")
    controller.openNoteInNewTab(at: "B.md")
    #expect(controller.focusedTab?.note.relativePath == "B.md", "B è attiva, A è in secondo piano")
    let backgroundID = try #require(controller.tabs.first { $0.note.relativePath == "A.md" }?.id)

    controller.closeTab(backgroundID)

    // In-memory state already dropped A.md before the fix; what was missing was persisting
    // that the session survived a relaunch with A.md still in it.
    #expect(controller.tabs.map(\.note.relativePath) == ["B.md"])
    let persisted = store.session(for: vault.root)
    #expect(persisted.columns.first?.entries.map(\.path) == ["B.md"])
    controller.close()
}

// MARK: 7. `canOperateOnFolder` asks every column, not only the focused tab (ADR-0056 §D7.1)

@MainActor
@Test func trashFolderRefusesWhileANoteUnderItIsDirtyInTheOtherColumn() async throws {
    let vault = try TemporaryVault()
    try vault.write(note("Fuori."), to: "Fuori.md")
    try vault.write(note("A."), to: "Cartella/A.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    // Column 0 shows an unrelated note throughout, so focusing it back genuinely leaves the
    // dirty tab behind in column 1 - `splitEditor()` alone would have put the same note in
    // both columns, which cannot distinguish "asks every column" from "asks the focused one".
    controller.openNote(at: "Fuori.md")
    controller.splitEditor()
    controller.openNote(at: "Cartella/A.md")
    controller.updateOpenNoteText(note("Modifica non salvata."))
    try #require(controller.openNote?.hasUnsavedChanges == true)
    // The dirty tab is in the second, non-focused column - `trashFolder` used to ask only
    // `openNote`, the focused tab, and see nothing wrong with the folder below it.
    controller.focusColumn(0)
    try #require(controller.focusedTab?.note.relativePath == "Fuori.md")

    let trashed = controller.trashFolder(at: "Cartella")

    #expect(!trashed)
    #expect(controller.problems.contains(VaultController.unsavedNoteInFolderRefusal))
    #expect(
        controller.columns[1].tabs.contains { $0.note.relativePath == "Cartella/A.md" && $0.note.hasUnsavedChanges },
        "la tab sporca nella colonna 2 deve restare aperta con le modifiche intatte"
    )
    #expect(
        FileManager.default.fileExists(
            atPath: vault.root.appending(path: "Cartella/A.md").path(percentEncoded: false)
        )
    )
    controller.close()
}
