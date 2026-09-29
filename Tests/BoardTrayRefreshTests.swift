import Foundation
import Testing
@testable import Pergamenum

// ADR-0072 §D4/§D5, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 2 - R-04.
//
// BoardTray keyed its «Task assegnati» refresh on `taskGeneration`, which an editor save and an
// external edit never move: a task assigned to the board that way stayed out of the tray until
// the next rescan. Its key now follows the index generation, and so does LinkedTasksPanel's memo,
// so a task added either way reaches both on the index change that takes it in.

private func refreshNote(_ body: String) -> String {
    "---\ndate: 2026-09-29\ntags:\n  - type-note\n---\n\n\(body)\n"
}

@MainActor
@Suite(.serialized) struct BoardTrayRefreshTests {
    private func opened(_ vault: borrowing TemporaryVault) async throws -> VaultController {
        try vault.write(refreshNote("Nessun task."), to: "Note/N.md")
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        return controller
    }

    @Test func anEditorSaveAssigningATaskChangesTheTrayKey() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        controller.openNote(at: "Note/N.md")
        let before = BoardTray.refreshKey(for: controller, board: "Board.canvas")

        controller.updateOpenNoteText(refreshNote("- [ ] X ^[[Board.canvas]]"))
        await controller.saveOpenNote()

        #expect(BoardTray.refreshKey(for: controller, board: "Board.canvas") != before)
        #expect(controller.index.tasks(assignedToWorkspace: "Board.canvas").map(\.text).contains { $0.contains("X") })
        controller.close()
    }

    @Test func anExternalEditAssigningATaskChangesTheTrayKey() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        let before = BoardTray.refreshKey(for: controller, board: "Board.canvas")

        try vault.write(refreshNote("- [ ] X ^[[Board.canvas]]"), to: "Note/N.md")
        await controller.reconcile(["Note/N.md"])

        #expect(BoardTray.refreshKey(for: controller, board: "Board.canvas") != before)
        #expect(controller.index.tasks(assignedToWorkspace: "Board.canvas").map(\.text).contains { $0.contains("X") })
        controller.close()
    }

    @Test func anEditorSaveLinkingATaskMovesTheGenerationThePanelKeysOn() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        controller.openNote(at: "Note/N.md")
        let before = controller.indexGeneration

        controller.updateOpenNoteText(refreshNote("- [ ] Chiamare per [[T]]"))
        await controller.saveOpenNote()

        #expect(controller.indexGeneration > before)
        #expect(controller.index.tasks(linkingTo: "T").map(\.sourcePath) == ["Note/N.md"])
        controller.close()
    }
}
