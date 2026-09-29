import Foundation
import Testing
@testable import Pergamenum

// ADR-0072 §D1/§D2, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 2 - R-03.
//
// The index generation moves on every landed index change, by any route: the snapshot's two
// mutating doors each move it, and through `VaultController` an editor save, an external edit
// reaching the watcher's reconcile path, a move, a trash, a rescan and a cache clear each raise
// `indexGeneration` strictly. A buffer edit nobody saved moves nothing, and switching vaults
// never hands a key back out: A, then B, then A again reads strictly increasing.

private func generationNote(_ body: String) -> String {
    "---\ndate: 2026-09-29\ntags:\n  - type-note\n---\n\n\(body)\n"
}

private func generationRecord(_ path: String) -> NoteRecord {
    NoteRecord(
        relativePath: path, title: String(path.dropLast(3)), frontmatter: .empty, linkTargets: [],
        tasks: [], modifiedAt: .distantPast, byteSize: 0, contentHash: "-"
    )
}

@Test func replaceAllAndUpdateEachMoveTheGeneration() {
    var index = IndexSnapshot()
    let start = index.generation

    index.replaceAll(
        with: .init(records: [generationRecord("A.md")], failures: [], boardTaskRecords: []), duration: .zero
    )
    let afterReplace = index.generation
    #expect(afterReplace > start)

    index.update(generationRecord("B.md"), at: "B.md")
    let afterUpdate = index.generation
    #expect(afterUpdate > afterReplace)

    index.update(nil, at: "A.md")
    #expect(index.generation > afterUpdate)
}

@MainActor
@Suite(.serialized) struct IndexGenerationControllerTests {
    private func opened(_ vault: borrowing TemporaryVault) async throws -> VaultController {
        try vault.write(generationNote("A."), to: "A.md")
        try vault.write(generationNote("B."), to: "B.md")
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        return controller
    }

    @Test func anEditorSaveMovesItAndAnUnsavedEditDoesNot() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        controller.openNote(at: "A.md")

        let beforeEdit = controller.indexGeneration
        controller.updateOpenNoteText(generationNote("A, modificata."))
        #expect(controller.indexGeneration == beforeEdit)

        await controller.saveOpenNote()
        #expect(controller.indexGeneration > beforeEdit)
        controller.close()
    }

    @Test func anExternalEditThroughReconcileMovesIt() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        let before = controller.indexGeneration

        try vault.write(generationNote("B, da fuori."), to: "B.md")
        await controller.reconcile(["B.md"])

        #expect(controller.indexGeneration > before)
        controller.close()
    }

    @Test func aMoveMovesIt() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        try FileManager.default.createDirectory(
            at: vault.root.appending(path: "Cartella", directoryHint: .isDirectory), withIntermediateDirectories: true
        )
        let before = controller.indexGeneration

        #expect(await controller.moveNote(at: "A.md", toFolder: "Cartella"))

        #expect(controller.indexGeneration > before)
        controller.close()
    }

    @Test func aTrashMovesIt() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        let before = controller.indexGeneration

        #expect(await controller.trashNote(at: "B.md"))

        #expect(controller.indexGeneration > before)
        controller.close()
    }

    @Test func aRescanAndACacheClearEachMoveIt() async throws {
        let vault = try TemporaryVault()
        let controller = try await opened(vault)
        let beforeRescan = controller.indexGeneration

        await controller.rescan()
        let afterRescan = controller.indexGeneration
        #expect(afterRescan > beforeRescan)

        await controller.clearCache()
        #expect(controller.indexGeneration > afterRescan)
        controller.close()
    }

    @Test func switchingVaultsNeverHandsAGenerationBack() async throws {
        let first = try TemporaryVault()
        let second = try TemporaryVault()
        try first.write(generationNote("A."), to: "A.md")
        try second.write(generationNote("B."), to: "B.md")
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        var seen: [Int] = [controller.indexGeneration]

        await controller.open(first.root)
        seen.append(controller.indexGeneration)
        await controller.open(second.root)
        seen.append(controller.indexGeneration)
        await controller.open(first.root)
        seen.append(controller.indexGeneration)
        controller.close()
        seen.append(controller.indexGeneration)

        #expect(zip(seen, seen.dropFirst()).allSatisfy { $0 < $1 }, "\(seen)")
    }
}
