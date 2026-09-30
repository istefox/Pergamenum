import Foundation
import Testing
@testable import Pergamenum

// ADR-0073 §D5, plan Task 2: «Salva tutto» saves every dirty, non-conflicted tab, re-reads
// before each write, never writes past a conflict, and goes on after a failure.

@MainActor
@Test func saveForQuitWritesThreeDirtyTabsAcrossTwoColumns() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let a = try openDirty("Nexion.md", adding: "\nUno.\n", inColumn: 0, of: controller)
    let b = try openDirty("Progetti/Pressa.md", adding: "\nDue.\n", inColumn: 0, of: controller)
    let c = try openDirty("Progetti/Sospensione.md", adding: "\nTre.\n", inColumn: 1, of: controller)
    // `a` is now a background tab of column 0.
    let review = QuitReview(columns: controller.columns)

    let report = await controller.saveForQuit(review)

    #expect(report == QuitSaveReport(saved: [a, b, c]))
    #expect(quitOnDisk(root, "Nexion.md")?.contains("Uno.") == true)
    #expect(quitOnDisk(root, "Progetti/Pressa.md")?.contains("Due.") == true)
    #expect(quitOnDisk(root, "Progetti/Sospensione.md")?.contains("Tre.") == true)
    #expect(QuitReview(columns: controller.columns).isEmpty)
    controller.close()
}

@MainActor
@Test func saveForQuitSkipsAConflictedTabAndReportsIt() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let conflicted = try openDirty("Nexion.md", adding: "\nMia versione.\n", inColumn: 0, of: controller)
    let other = try openDirty("Progetti/Pressa.md", adding: "\nSalvabile.\n", inColumn: 0, of: controller)
    controller.updateTabs(showing: "Nexion.md") { $0.note.externalChangePending = .text("da disco") }
    let before = quitOnDisk(root, "Nexion.md")

    let report = await controller.saveForQuit(QuitReview(columns: controller.columns))

    #expect(report.saved == [other])
    #expect(report.conflicted == [conflicted])
    #expect(report.failed.isEmpty)
    #expect(quitOnDisk(root, "Nexion.md") == before)
    #expect(controller.tab(withID: conflicted)?.note.hasUnsavedChanges == true)
    controller.close()
}

@MainActor
@Test func theSameNoteDirtyInBothColumnsWritesTheFirstAndReportsTheSecond() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let first = try openDirty("Nexion.md", adding: "\nSinistra.\n", inColumn: 0, of: controller)
    let second = try openDirty("Nexion.md", adding: "\nDestra.\n", inColumn: 1, of: controller)

    let report = await controller.saveForQuit(QuitReview(columns: controller.columns))

    #expect(report.saved == [first])
    #expect(report.conflicted == [second])
    let written = try #require(quitOnDisk(root, "Nexion.md"))
    #expect(written.contains("Sinistra."))
    #expect(!written.contains("Destra."))
    #expect(controller.tab(withID: second)?.note.text.contains("Destra.") == true)
    controller.close()
}

@MainActor
@Test func aFailureMidBatchIsReportedAndTheTabsAfterItAreStillWritten() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let before = try openDirty("Nexion.md", adding: "\nPrima.\n", inColumn: 0, of: controller)
    let failing = try openDirty("Progetti/Pressa.md", adding: "\nFallirà.\n", inColumn: 0, of: controller)
    let after = try openDirty("Dopo.md", adding: "\nDopo il fallimento.\n", inColumn: 1, of: controller)

    let report = try await withReadOnlyFolder(root, "Progetti") {
        await controller.saveForQuit(QuitReview(columns: controller.columns))
    }

    #expect(report.saved == [before, after])
    #expect(report.failed == [failing])
    #expect(quitOnDisk(root, "Dopo.md")?.contains("Dopo il fallimento.") == true)
    #expect(controller.tab(withID: failing)?.note.hasUnsavedChanges == true)
    controller.close()
}
