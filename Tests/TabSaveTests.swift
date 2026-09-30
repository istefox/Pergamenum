import Foundation
import Testing
@testable import Pergamenum

// ADR-0073 §D4, plan Task 2: one save door by tab id, reaching any column, that says what
// happened - and the tab-close dialog's «Salva» closing only when the save landed.

@MainActor
@Test func saveTabWritesABackgroundTabOfTheOtherColumnWithoutMovingTheFocus() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "", inColumn: 0, of: controller)
    let target = try openDirty("Progetti/Sospensione.md", adding: "\nAggiunta a destra.\n", inColumn: 1, of: controller)
    // A second tab in front of it, so the target is a background tab of column 1.
    controller.openNoteInNewTab(at: "Progetti/Pressa.md")
    let front = try #require(controller.columns[1].activeID)
    controller.focusColumn(0)
    let leftActive = controller.columns[0].activeID

    let outcome = await controller.saveTab(target)

    #expect(outcome == .saved)
    #expect(quitOnDisk(root, "Progetti/Sospensione.md")?.contains("Aggiunta a destra.") == true)
    #expect(controller.focusedColumnIndex == 0)
    #expect(controller.columns[0].activeID == leftActive)
    #expect(controller.columns[1].activeID == front)
    // The writer catches up: its saved text is what it wrote, and its text is kept.
    let saved = try #require(controller.tab(withID: target))
    #expect(saved.note.text.contains("Aggiunta a destra."))
    #expect(saved.note.savedText == saved.note.text)
    #expect(!saved.note.hasUnsavedChanges)
    controller.close()
}

@MainActor
@Test func saveTabAnswersCleanForACleanTabAndForAnUnknownID() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    controller.openNote(at: "Nexion.md")
    let clean = try #require(controller.focusedTab?.id)

    #expect(await controller.saveTab(clean) == .clean)
    #expect(await controller.saveTab(UUID()) == .clean)
    controller.close()
}

@MainActor
@Test func saveTabReportsAFailureAndLeavesTheTabDirty() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let id = try openDirty("Progetti/Sospensione.md", adding: "\nNon arriverà.\n", inColumn: 0, of: controller)

    let outcome = try await withReadOnlyFolder(root, "Progetti") { await controller.saveTab(id) }

    guard case .failed(let message) = outcome else {
        Issue.record("expected .failed, got \(outcome)")
        controller.close()
        return
    }
    #expect(message.contains("Progetti/Sospensione.md"))
    #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == true)
    #expect(controller.problems.contains { $0.contains("Progetti/Sospensione.md") })
    #expect(quitOnDisk(root, "Progetti/Sospensione.md")?.contains("Non arriverà.") == false)
    controller.close()
}

@MainActor
@Test func saveAndCloseTabClosesOnSavedAndOnClean() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let dirty = try openDirty("Nexion.md", adding: "\nChiusa salvando.\n", inColumn: 0, of: controller)
    controller.openNoteInNewTab(at: "Progetti/Pressa.md")
    let clean = try #require(controller.focusedTab?.id)

    #expect(await controller.saveAndCloseTab(dirty) == .saved)
    #expect(await controller.saveAndCloseTab(clean) == .clean)

    #expect(controller.tab(withID: dirty) == nil)
    #expect(controller.tab(withID: clean) == nil)
    #expect(quitOnDisk(root, "Nexion.md")?.contains("Chiusa salvando.") == true)
    controller.close()
}

@MainActor
@Test func saveAndCloseTabLeavesTheTabOpenAndDirtyOnAFailedSave() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let id = try openDirty("Progetti/Pressa.md", adding: "\nDa non perdere.\n", inColumn: 0, of: controller)

    let outcome = try await withReadOnlyFolder(root, "Progetti") { await controller.saveAndCloseTab(id) }

    #expect(outcome != .saved && outcome != .clean)
    let kept = try #require(controller.tab(withID: id))
    #expect(kept.note.hasUnsavedChanges)
    #expect(kept.note.text.contains("Da non perdere."))
    controller.close()
}

@MainActor
@Test func revealTabFocusesTheOtherColumnAndTheTab() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "", inColumn: 0, of: controller)
    let hidden = try openDirty("Progetti/Sospensione.md", adding: "x", inColumn: 1, of: controller)
    controller.openNoteInNewTab(at: "Progetti/Pressa.md")
    controller.focusColumn(0)

    controller.revealTab(hidden)

    #expect(controller.focusedColumnIndex == 1)
    #expect(controller.columns[1].activeID == hidden)
    #expect(controller.focusedTab?.id == hidden)
    controller.close()
}
