import Foundation
import Testing
@testable import Pergamenum

// ADR-0072 §D11's first two follow-ups, burn-down plan docs/plans/burn-down-2026-09-29-pg-315.md.
//
// PG-324: TodayView reread its blocks and columns on `taskGeneration`, which an editor save and an
// external edit never move, so the day stayed stale the way BoardTray did before ADR-0072 §D5.
// PG-325: an editor view block re-ran its query on `scanGeneration` (ADR-0033 §D7), so a fence
// listing a note did not re-run when that note was saved. Both keys now follow the index
// generation; these pin that the two ways the index changes without a scan move them.

private func followUpNote(_ body: String) -> String {
    "---\ndate: 2026-09-29\ntags:\n  - type-note\n---\n\n\(body)\n"
}

@MainActor
@Suite(.serialized) struct IndexGenerationFollowUpTests {
    private func opened(_ vault: borrowing TemporaryVault) async throws -> VaultController {
        try vault.write(followUpNote("Niente."), to: "Note/N.md")
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        return controller
    }

    @Test func anEditorSaveMovesTheDayReloadKey() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        controller.openNote(at: "Note/N.md")
        let before = TodayView.reloadKey(for: controller)

        controller.updateOpenNoteText(followUpNote("- [ ] X >2026-09-30"))
        await controller.saveOpenNote()

        #expect(TodayView.reloadKey(for: controller) != before)
        #expect(controller.index.allTasks.contains { $0.text.contains("X") })
        controller.close()
    }

    @Test func anExternalEditMovesTheDayReloadKey() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        let before = TodayView.reloadKey(for: controller)

        try vault.write(followUpNote("- [ ] X >2026-09-30"), to: "Note/N.md")
        await controller.reconcile(["Note/N.md"])

        #expect(TodayView.reloadKey(for: controller) != before)
        #expect(controller.index.allTasks.contains { $0.text.contains("X") })
        controller.close()
    }

    @Test func anEditorSaveChangesADrawnFenceTaskID() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        controller.openNote(at: "Note/N.md")
        let before = EditorColumnView.viewQueryGeneration(for: controller)

        controller.updateOpenNoteText(followUpNote("Salvata."))
        await controller.saveOpenNote()

        let after = EditorColumnView.viewQueryGeneration(for: controller)
        #expect(after != before)
        // The id `.task(id:)` re-runs the query on, for an unchanged fence and no refresh.
        #expect(
            RenderedViewBlock.taskID(source: "render: table", generation: after, reloads: 0)
                != RenderedViewBlock.taskID(source: "render: table", generation: before, reloads: 0)
        )
        controller.close()
    }

    // Discriminates against the old keys: an editor save moves the index generation while neither
    // `taskGeneration` (PG-324) nor `scanGeneration` (PG-325) moves, so a key still reading one of
    // them would leave these two equal and fail here.
    @Test func anEditorSaveMovesNeitherOldKeyButBothNewOnes() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        controller.openNote(at: "Note/N.md")
        let task0 = controller.taskGeneration
        let scan0 = controller.scanGeneration
        let day0 = TodayView.reloadKey(for: controller)
        let query0 = EditorColumnView.viewQueryGeneration(for: controller)

        controller.updateOpenNoteText(followUpNote("- [ ] Y >2026-09-30"))
        await controller.saveOpenNote()

        #expect(controller.taskGeneration == task0)
        #expect(controller.scanGeneration == scan0)
        #expect(TodayView.reloadKey(for: controller) != day0)
        #expect(EditorColumnView.viewQueryGeneration(for: controller) != query0)
        controller.close()
    }

    @Test func anExternalEditMovesTheViewQueryGeneration() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        let before = EditorColumnView.viewQueryGeneration(for: controller)

        try vault.write(followUpNote("Cambiata fuori."), to: "Note/N.md")
        await controller.reconcile(["Note/N.md"])

        #expect(EditorColumnView.viewQueryGeneration(for: controller) != before)
        controller.close()
    }

    // PG-328: a `![[N]]` in another note was redrawn on `scanGeneration`, so saving N in the app
    // left the embed showing N's old text. Discriminating the same way as above: the save moves
    // the transclusion generation while `scanGeneration` stays put.
    @Test func anEditorSaveMovesTheTransclusionGenerationButNotTheScan() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        controller.openNote(at: "Note/N.md")
        let scan0 = controller.scanGeneration
        let before = EditorColumnView.transclusionGeneration(for: controller)

        controller.updateOpenNoteText(followUpNote("Salvata."))
        await controller.saveOpenNote()

        #expect(controller.scanGeneration == scan0)
        #expect(EditorColumnView.transclusionGeneration(for: controller) != before)
        controller.close()
    }

    @Test func anExternalEditMovesTheTransclusionGeneration() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        let before = EditorColumnView.transclusionGeneration(for: controller)

        try vault.write(followUpNote("Cambiata fuori."), to: "Note/N.md")
        await controller.reconcile(["Note/N.md"])

        #expect(EditorColumnView.transclusionGeneration(for: controller) != before)
        controller.close()
    }
}
