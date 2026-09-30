import Foundation
import Testing
@testable import Pergamenum

// Gap-fillers for plan pg-326 (ADR-0073): R-13 (Cmd+S has no precondition), R-07 (a
// conflicted tab is discarded by «Non salvare» like any other), R-08 (the re-reads after the
// question and after the saves), R-04 (the diary phase still runs after «Non salvare»).

@MainActor
private final class GapProbe {
    var replies: [Bool] = []
    var revealed: [NoteTab.ID?] = []
    let hold = Gate()

    func coordinator(
        _ controller: VaultController, diary: DiaryController?,
        answer: @escaping @MainActor (QuitReview) -> QuitReview.Answer,
        saveAll: (@MainActor (QuitReview) async -> QuitSaveReport)? = nil
    ) -> QuitCoordinator {
        QuitCoordinator(
            vault: { controller }, diary: { diary },
            commitEditing: {},
            ask: answer,
            reply: { [unowned self] in replies.append($0) },
            reveal: { [unowned self] in revealed.append($0) },
            // Every timer waits: the caps must not decide these tests.
            sleep: { [unowned self] _ in await hold.wait() },
            saveAll: saveAll
        )
    }
}

// MARK: R-13

@MainActor
@Test func cmdSWritesADirtyFocusedTabEvenWithAPendingBanner() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let id = try openDirty("Nexion.md", adding: "\nCmd+S vince.\n", inColumn: 0, of: controller)
    controller.updateTabs(showing: "Nexion.md") { $0.note.externalChangePending = .text("da disco") }

    await controller.saveOpenNote()

    #expect(quitOnDisk(root, "Nexion.md")?.contains("Cmd+S vince.") == true)
    #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == false)
    controller.close()
}

// MARK: R-07

@MainActor
@Test func nonSalvareDiscardsAConflictedTabLikeAnyOther() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nScartata.\n", inColumn: 0, of: controller)
    controller.updateTabs(showing: "Nexion.md") { $0.note.externalChangePending = .deleted }
    let before = quitOnDisk(root, "Nexion.md")
    let probe = GapProbe()
    let quit = probe.coordinator(controller, diary: nil) { _ in .discard }

    #expect(quit.shouldTerminate() == .now)

    #expect(quitOnDisk(root, "Nexion.md") == before)
    #expect(probe.replies.isEmpty)
    controller.close()
}

// MARK: R-08

@MainActor
@Test func aSaveThatMakesTheSecondColumnConflictedCancelsTheQuit() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let first = try openDirty("Nexion.md", adding: "\nSinistra.\n", inColumn: 0, of: controller)
    let second = try openDirty("Nexion.md", adding: "\nDestra.\n", inColumn: 1, of: controller)
    let probe = GapProbe()
    let quit = probe.coordinator(controller, diary: nil) { _ in .save }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [false])
    #expect(probe.revealed == [second])
    #expect(quitOnDisk(root, "Nexion.md")?.contains("Sinistra.") == true)
    #expect(quitOnDisk(root, "Nexion.md")?.contains("Destra.") == false)
    #expect(controller.tab(withID: first)?.note.hasUnsavedChanges == false)
    probe.hold.open()
    controller.close()
}

@MainActor
@Test func typingDuringTheSaveCancelsTheQuitInsteadOfDroppingIt() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    let id = try openDirty("Nexion.md", adding: "\nSalvata.\n", inColumn: 0, of: controller)
    let probe = GapProbe()
    let quit = probe.coordinator(
        controller, diary: nil,
        answer: { _ in .save },
        saveAll: { review in
            let report = await controller.saveForQuit(review)
            controller.updateTabs(showing: "Nexion.md") { $0.note.text += "Scritta durante il salvataggio.\n" }
            return report
        }
    )

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [false])
    #expect(probe.revealed == [id])
    #expect(controller.tab(withID: id)?.note.text.contains("Scritta durante il salvataggio.") == true)
    probe.hold.open()
    controller.close()
}

@MainActor
@Test func aNewlyDirtyTabAfterSalvaTuttoIsNeverLostToTheDiaryPhase() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nA.\n", inColumn: 0, of: controller)
    let probe = GapProbe()
    let quit = probe.coordinator(
        controller, diary: nil,
        answer: { _ in .save },
        saveAll: { review in
            let report = await controller.saveForQuit(review)
            controller.openNoteInNewTab(at: "Dopo.md")
            controller.updateOpenNoteText((controller.openNote?.text ?? "") + "Nuova.\n")
            return report
        }
    )

    _ = quit.shouldTerminate()
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [false])
    probe.hold.open()
    controller.close()
}

// MARK: R-04

@MainActor
@Test func nonSalvareStillRunsTheDiaryPhaseAndRepliesOnce() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let diary = DiaryController(vault: controller)
    diary.show(testDay)
    diary.prose += "Diario dopo Non salvare.\n"
    _ = try openDirty("Nexion.md", adding: "\nScartata.\n", inColumn: 0, of: controller)
    let before = quitOnDisk(root, "Nexion.md")
    let probe = GapProbe()
    let quit = probe.coordinator(controller, diary: diary) { _ in .discard }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [true])
    #expect(diaryOnDisk(root)?.contains("Diario dopo Non salvare.") == true)
    #expect(quitOnDisk(root, "Nexion.md") == before)
    probe.hold.open()
    controller.close()
}
