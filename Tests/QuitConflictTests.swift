import Foundation
import Testing
@testable import Pergamenum

// PG-336, ADR-0089 D2/D4/D5/D6, plan Task 2: a conflicted board and a conflicted diary day in
// the quit question, driven through `QuitCoordinator` with a fake `ask`, a recording `reply`
// and a `sleep` that either returns at once or waits on a gate, over a real vault on disk.

// `ConflictProbe`, `drain()`, `boardProblem` and `diaryProblem` live in `QuitTestSupport.swift`;
// R-08's last check is in `QuitConflictLastCheckTests.swift`, the §D2 derivations in
// `QuitConflictDerivationTests.swift`.

private func bytes(_ root: URL, _ path: String) -> Data? {
    try? Data(contentsOf: root.appending(path: path))
}

/// Every path under `root`, hidden files included, sorted.
private func listing(_ root: URL) -> [String] {
    let base = root.standardizedFileURL.path(percentEncoded: false)
    let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [])
    var found: [String] = []
    while let url = walker?.nextObject() as? URL {
        found.append(String(url.standardizedFileURL.path(percentEncoded: false).dropFirst(base.count)))
    }
    return found.sorted()
}

private let diaryPath = "Diario/20260811.md"

// MARK: R-01, R-02: the question is asked

@MainActor
@Test func aLoneConflictedBoardIsAskedAboutAndCancelRevealsTheBoard() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let (board, path) = try quitConflictedBoard(vault, in: controller)
    let before = bytes(root, path)
    let probe = ConflictProbe()
    let quit = probe.coordinator(controller, diary: nil) { _ in .cancel }

    #expect(quit.shouldTerminate() == .cancel)

    #expect(probe.asked.count == 1)
    #expect(probe.asked.first?.board?.path == path)
    #expect(probe.asked.first?.entries.isEmpty == true)
    #expect(probe.sleptWhenAsked == [])
    #expect(probe.shown == [.board])
    #expect(probe.replies.isEmpty)
    #expect(bytes(root, path) == before)
    board.detach()
    controller.close()
}

@MainActor
@Test func aLoneConflictedDiaryDayIsAskedAboutAndCancelRevealsTheDiary() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let diary = try await quitConflictedDiary(in: controller, root: root)
    let before = bytes(root, diaryPath)
    let probe = ConflictProbe()
    let quit = probe.coordinator(controller, diary: diary) { _ in .cancel }

    #expect(quit.shouldTerminate() == .cancel)

    #expect(probe.asked.count == 1)
    #expect(probe.asked.first?.diary?.day == testDay)
    #expect(probe.asked.first?.entries.isEmpty == true)
    #expect(probe.sleptWhenAsked == [])
    #expect(probe.shown == [.diary])
    #expect(bytes(root, diaryPath) == before)
    controller.close()
}

// MARK: R-03: nothing conflicted, nothing asked

@MainActor
@Test func anUnsavedButNotConflictedBoardIsWrittenBySettleWithoutAQuestion() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let store = CanvasStore(root: root)
    let path = try store.createBoard(named: "Bacheca", in: "")
    let board = WorkspaceController()
    board.attach(to: store, vault: controller)
    board.open(board: path)
    let id = board.addStickyNote("appunto", at: .zero)
    let before = bytes(root, path)
    let probe = ConflictProbe()
    let quit = probe.coordinator(controller, diary: nil) { _ in .cancel }

    #expect(quit.shouldTerminate() == .now)

    #expect(probe.asked.isEmpty)
    #expect(probe.replies.isEmpty)
    #expect(probe.shown.isEmpty)
    #expect(board.saveState == .saved)
    #expect(bytes(root, path) != before)
    let onDisk = try store.load(board: path)
    #expect(onDisk.node(id: id) != nil)
    board.detach()
    controller.close()
}

// MARK: R-05: where a cancel goes (G1)

@MainActor
@Test func cancelWithABoardADirtyNoteAndADiaryRevealsTheBoardOnly() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nNon salvata.\n", inColumn: 0, of: controller)
    let (board, _) = try quitConflictedBoard(vault, in: controller)
    let diary = try await quitConflictedDiary(in: controller, root: root)
    let probe = ConflictProbe()
    let quit = probe.coordinator(controller, diary: diary) { _ in .cancel }

    #expect(quit.shouldTerminate() == .cancel)

    #expect(probe.asked.first?.board != nil)
    #expect(probe.asked.first?.diary != nil)
    #expect(probe.asked.first?.entries.count == 1)
    #expect(probe.shown == [.board])
    board.detach()
    controller.close()
}

@MainActor
@Test func cancelWithADirtyNoteAndADiaryRevealsTheNoteLikeToday() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nNon salvata.\n", inColumn: 0, of: controller)
    let diary = try await quitConflictedDiary(in: controller, root: root)
    let probe = ConflictProbe()
    let quit = probe.coordinator(controller, diary: diary) { _ in .cancel }

    #expect(quit.shouldTerminate() == .cancel)

    #expect(probe.asked.first?.diary?.day == testDay)
    #expect(probe.shown == [.note(nil)])
    controller.close()
}

// MARK: R-06: «Salva» and «Salva tutto» never write either item

@MainActor
@Test func salvaOnALoneConflictedBoardWritesNothingCancelsAndRecordsTheLine() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let (board, path) = try quitConflictedBoard(vault, in: controller)
    let before = bytes(root, path)
    let probe = ConflictProbe()
    let quit = probe.coordinator(controller, diary: nil) { _ in .save }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [false])
    #expect(bytes(root, path) == before)
    #expect(controller.problems.contains { $0.contains(boardProblem) })
    #expect(!controller.problems.contains { $0.contains("note non salvate") })
    #expect(probe.shown == [.board])
    probe.openAllGates()
    await drain()
    #expect(probe.replies == [false])
    board.detach()
    controller.close()
}

@MainActor
@Test func salvaTuttoSavesTheNoteButNeverTheConflictedDiary() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nSalvata da Salva tutto.\n", inColumn: 0, of: controller)
    let diary = try await quitConflictedDiary(in: controller, root: root)
    let diaryBefore = bytes(root, diaryPath)
    let probe = ConflictProbe()
    let quit = probe.coordinator(controller, diary: diary) { _ in .save }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [false])
    #expect(quitOnDisk(root, "Nexion.md")?.contains("Salvata da Salva tutto.") == true)
    #expect(bytes(root, diaryPath) == diaryBefore)
    #expect(controller.problems.contains { $0.contains(diaryProblem) })
    #expect(!controller.problems.contains { $0.contains("note non salvate") })
    #expect(probe.shown == [.diary])
    // R-11: no timer during the question; the caps are the unchanged two.
    #expect(probe.sleptWhenAsked == [])
    // The order follows main-actor task scheduling: if it flips, it is queue order, not a regression.
    #expect(probe.slept == [QuitCoordinator.diaryCap, QuitReview.noteSaveCap])
    probe.openAllGates()
    await drain()
    #expect(probe.replies.count == 1)
    controller.close()
}

// MARK: R-07: «Non salvare» is a plain discard

@MainActor
@Test func nonSalvareLetsAConflictedBoardDiaryAndNoteGoByteIdenticalAndCreatesNoFile() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nPersa.\n", inColumn: 0, of: controller)
    let (board, path) = try quitConflictedBoard(vault, in: controller)
    let diary = try await quitConflictedDiary(in: controller, root: root)
    let boardBefore = bytes(root, path)
    let diaryBefore = bytes(root, diaryPath)
    let noteBefore = bytes(root, "Nexion.md")
    let tree = listing(root)
    let probe = ConflictProbe()
    let quit = probe.coordinator(controller, diary: diary) { _ in .discard }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.asked.first?.board?.path == path)
    #expect(probe.asked.first?.diary?.day == testDay)
    #expect(probe.replies == [true])
    #expect(bytes(root, path) == boardBefore)
    #expect(bytes(root, diaryPath) == diaryBefore)
    #expect(bytes(root, "Nexion.md") == noteBefore)
    #expect(listing(root) == tree)
    #expect(probe.shown.isEmpty)
    board.detach()
    controller.close()
}

@MainActor
@Test func nonSalvareOnALoneConflictedBoardGoesNowAndLeavesTheFileAlone() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let (board, path) = try quitConflictedBoard(vault, in: controller)
    let before = bytes(root, path)
    let tree = listing(root)
    let probe = ConflictProbe()
    let quit = probe.coordinator(controller, diary: nil) { _ in .discard }

    #expect(quit.shouldTerminate() == .now)

    #expect(probe.asked.count == 1)
    #expect(probe.asked.first?.board?.path == path)
    #expect(probe.replies.isEmpty)
    #expect(probe.shown.isEmpty)
    #expect(bytes(root, path) == before)
    #expect(listing(root) == tree)
    board.detach()
    controller.close()
}
