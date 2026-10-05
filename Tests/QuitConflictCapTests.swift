import Foundation
import Testing
@testable import Pergamenum

// PG-336, ADR-0089 D5: «Salva tutto»'s fail-safe cap (`noteCapElapsed`) with a conflicted board
// or diary day in the review. The bulk save never returns, so the 10 s cap, a gated `sleep`
// opened by the test, ends the notes phase: the cancel names the unfinished save, adds the
// conflict's own line, reveals the first item left and replies once.

/// Everything the coordinator hands to AppKit, recorded; every reveal goes into one ordered log.
/// Every `sleep` waits on its own gate, opened by the test.
@MainActor
private final class CapProbe {
    enum Shown: Equatable {
        case note(NoteTab.ID?), board, diary, scheda(String?)
    }

    var replies: [Bool] = []
    var shown: [Shown] = []
    var slept: [Duration] = []
    private var gates: [Duration: Gate] = [:]

    func gate(for duration: Duration) -> Gate {
        if let gate = gates[duration] { return gate }
        let gate = Gate()
        gates[duration] = gate
        return gate
    }

    func openAllGates() {
        gates.values.forEach { $0.open() }
    }

    func coordinator(
        _ controller: VaultController,
        diary: DiaryController?,
        saveAll: @escaping @MainActor (QuitReview) async -> QuitSaveReport
    ) -> QuitCoordinator {
        QuitCoordinator(
            vault: { controller },
            diary: { diary },
            contenitore: { nil },
            commitEditing: {},
            ask: { _ in .save },
            reply: { [unowned self] in replies.append($0) },
            reveal: { [unowned self] in shown.append(.note($0)) },
            revealContenitore: { [unowned self] in shown.append(.scheda($0)) },
            revealBoard: { [unowned self] in shown.append(.board) },
            revealDiary: { [unowned self] in shown.append(.diary) },
            sleep: { [unowned self] duration in
                slept.append(duration)
                await gate(for: duration).wait()
            },
            saveAll: saveAll
        )
    }
}

// `drain()`, `boardProblem` and `diaryProblem` live in `QuitTestSupport.swift`.
private let unfinished = "Uscita annullata: il salvataggio di «Nexion» non è terminato"

@MainActor
@Test func theNoteSaveCapWithAConflictedBoardNamesTheSaveAndTheBoardAndRevealsTheBoard() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nMai scritta.\n", inColumn: 0, of: controller)
    let (board, path) = try quitConflictedBoard(vault, in: controller)
    let before = try Data(contentsOf: root.appending(path: path))
    let probe = CapProbe()
    let hung = Gate()
    let quit = probe.coordinator(controller, diary: nil) { _ in
        await hung.wait()
        return QuitSaveReport()
    }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { probe.slept.contains(QuitReview.noteSaveCap) }
    #expect(probe.replies.isEmpty)
    probe.gate(for: QuitReview.noteSaveCap).open()
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [false])
    #expect(controller.problems.contains { $0.contains(unfinished) })
    #expect(controller.problems.contains { $0.contains(boardProblem) })
    #expect(probe.shown == [.board])
    #expect(try Data(contentsOf: root.appending(path: path)) == before)
    hung.open()
    probe.openAllGates()
    await drain()
    #expect(probe.replies == [false])
    board.detach()
    controller.close()
}

/// The save writes the note and then never returns: the fresh review holds no note, only the
/// conflicted diary day, so the line falls back to the review's notes and the reveal is the diary.
@MainActor
@Test func theNoteSaveCapWithOnlyAConflictedDiaryLeftNamesTheReviewsNotesAndRevealsTheDiary() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nScritta prima del blocco.\n", inColumn: 0, of: controller)
    let diary = try await quitConflictedDiary(in: controller, root: root)
    let diaryBefore = try Data(contentsOf: root.appending(path: "Diario/20260811.md"))
    let probe = CapProbe()
    let hung = Gate()
    let quit = probe.coordinator(controller, diary: diary) { review in
        _ = await controller.saveForQuit(review)
        await hung.wait()
        return QuitSaveReport()
    }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { probe.slept.contains(QuitReview.noteSaveCap) }
    try await waitUntil { quitOnDisk(root, "Nexion.md")?.contains("Scritta prima del blocco.") == true }
    #expect(probe.replies.isEmpty)
    probe.gate(for: QuitReview.noteSaveCap).open()
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [false])
    #expect(controller.problems.contains { $0.contains(unfinished) })
    #expect(controller.problems.contains { $0.contains(diaryProblem) })
    #expect(!controller.problems.contains { $0.contains("note non salvate") })
    #expect(probe.shown == [.diary])
    #expect(try Data(contentsOf: root.appending(path: "Diario/20260811.md")) == diaryBefore)
    hung.open()
    probe.openAllGates()
    await drain()
    #expect(probe.replies == [false])
    controller.close()
}
