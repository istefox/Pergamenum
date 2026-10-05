import Foundation
import Testing
@testable import Pergamenum

// PG-336, ADR-0089 D4/D6, plan Task 2: the last check before letting go, with a conflicted board
// or diary day that changes, or becomes conflicted, after the question. Split from
// `QuitConflictTests.swift`; `ConflictProbe` and `drain()` live in `QuitTestSupport.swift`.

private func bytes(_ root: URL, _ path: String) -> Data? {
    try? Data(contentsOf: root.appending(path: path))
}

private let diaryPath = "Diario/20260811.md"

// MARK: R-08: the last check

@MainActor
@Test func aBoardChangedAfterTheQuestionIsUncoveredAndCancels() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let (board, path) = try quitConflictedBoard(vault, in: controller)
    let before = bytes(root, path)
    let probe = ConflictProbe()
    let quit = probe.coordinator(controller, diary: nil) { _ in
        _ = board.addStickyNote("scritta durante la domanda", at: .zero)
        return .discard
    }

    #expect(quit.shouldTerminate() == .cancel)

    #expect(probe.shown == [.board])
    #expect(probe.replies.isEmpty)
    #expect(bytes(root, path) == before)
    board.detach()
    controller.close()
}

@MainActor
@Test func aCoveredBoardLeftByAnUncoveredRevealRecordsItsLine() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let (board, path) = try quitConflictedBoard(vault, in: controller)
    let before = bytes(root, path)
    let probe = ConflictProbe()
    // The board is in the question and «Non salvare» covers it; a note typed during the question
    // is uncovered, so the cancel reveals the Note pane and leaves the board's pane.
    let quit = probe.coordinator(controller, diary: nil) { _ in
        _ = try? openDirty("Nexion.md", adding: "\nDurante la domanda.\n", inColumn: 0, of: controller)
        return .discard
    }

    #expect(quit.shouldTerminate() == .cancel)

    #expect(probe.shown.count == 1)
    #expect(probe.shown.first != .board)
    #expect(probe.replies.isEmpty)
    #expect(controller.problems.contains { $0.contains(boardProblem) })
    #expect(bytes(root, path) == before)
    board.detach()
    controller.close()
}

@MainActor
@Test func aDiaryChangedAfterTheQuestionIsUncoveredAndCancels() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let diary = try await quitConflictedDiary(in: controller, root: root)
    let before = bytes(root, diaryPath)
    let probe = ConflictProbe()
    let quit = probe.coordinator(controller, diary: diary) { _ in
        diary.prose += "Scritta durante la domanda.\n"
        return .discard
    }

    #expect(quit.shouldTerminate() == .cancel)

    #expect(probe.shown == [.diary])
    #expect(probe.replies.isEmpty)
    #expect(bytes(root, diaryPath) == before)
    controller.close()
}

/// Types into the diary and holds its first write at `.willWrite` until `release` runs, which
/// lets another writer create the day file first, so the write is refused (the conflict enters
/// during the quit, never before it).
@MainActor
private func holdDiaryWrite(
    _ diary: DiaryController, root: URL
) -> (held: () -> Bool, release: () throws -> Void) {
    let gate = Gate()
    var held = false
    diary.testOnlyWriteHook = { phase in
        if case .willWrite = phase, !held {
            held = true
            await gate.wait()
        }
    }
    diary.prose += "Frase mia.\n"
    return ({ held }, {
        let url = root.appending(path: diaryPath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\nAltro processo.\n".utf8).write(to: url)
        gate.open()
    })
}

@MainActor
@Test func aDiaryThatBecomesConflictedDuringTheDiaryPhaseCancelsAndRevealsTheDiary() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nPersa.\n", inColumn: 0, of: controller)
    let diary = DiaryController(vault: controller)
    diary.show(testDay)
    let hold = holdDiaryWrite(diary, root: root)
    let probe = ConflictProbe()
    let quit = probe.coordinator(controller, diary: diary) { _ in .discard }

    #expect(quit.shouldTerminate() == .later)
    #expect(probe.asked.count == 1)
    #expect(probe.asked.first?.diary == nil)
    try await waitUntil { hold.held() }
    try hold.release()
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [false])
    #expect(probe.shown == [.diary])
    #expect(probe.sleptWhenAsked == [])
    probe.openAllGates()
    await drain()
    #expect(probe.replies == [false])
    controller.close()
}

@MainActor
@Test func aDiaryThatBecomesConflictedWhileSalvaTuttoSettlesItCancelsAndRecordsTheLine() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nSalvata.\n", inColumn: 0, of: controller)
    let diary = DiaryController(vault: controller)
    diary.show(testDay)
    let hold = holdDiaryWrite(diary, root: root)
    let probe = ConflictProbe()
    let quit = probe.coordinator(controller, diary: diary) { _ in .save }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { hold.held() }
    try hold.release()
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [false])
    #expect(probe.shown == [.diary])
    #expect(controller.problems.contains { $0.contains(diaryProblem) })
    #expect(quitOnDisk(root, "Nexion.md")?.contains("Salvata.") == true)
    #expect(probe.sleptWhenAsked == [])
    probe.openAllGates()
    await drain()
    #expect(probe.replies.count == 1)
    controller.close()
}
