import Foundation
import Testing
@testable import Pergamenum

// PG-392, ADR-0091 §D1/§D3/§D7, plan Task 3 (R-05): the quit reaches a conflicted Workspace
// board whose pane is not on screen. PG-336 (ADR-0089 §D7) lost that board with the view that
// held its controller; the controller now lives with the vault, so the question names it, the
// answers behave as for a board on screen, and a cancel shows it. `leavePane()` stands for the
// pane left; `ConflictProbe` and `quitConflictedBoard` live in `QuitTestSupport.swift`.

private func bytes(_ root: URL, _ path: String) -> Data? {
    try? Data(contentsOf: root.appending(path: path))
}

@MainActor
@Test func aQuitWithTheBoardPaneLeftNamesTheConflictedBoard() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    let (board, path) = try quitConflictedBoard(vault, in: controller)
    board.enterPane()
    board.leavePane()
    let probe = ConflictProbe()
    let quit = probe.coordinator(controller, diary: nil) { _ in .cancel }

    #expect(quit.shouldTerminate() == .cancel)

    #expect(probe.asked.count == 1)
    #expect(probe.asked.first?.board != nil)
    #expect(probe.asked.first?.board == controller.openBoard.quitConflict)
    #expect(probe.asked.first?.board?.path == path)
    board.detach()
    controller.close()
}

@MainActor
@Test func salvaWithTheBoardPaneLeftCancelsAndRevealsTheBoard() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let (board, path) = try quitConflictedBoard(vault, in: controller)
    board.enterPane()
    board.leavePane()
    let before = bytes(root, path)
    let probe = ConflictProbe()
    let quit = probe.coordinator(controller, diary: nil) { _ in .save }

    // «Salva» is answered asynchronously, as for a board on screen: the cancel arrives as the
    // reply `false`.
    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [false])
    #expect(probe.shown == [.board])
    #expect(controller.problems.contains { $0.contains(boardProblem) })
    #expect(bytes(root, path) == before)
    probe.openAllGates()
    await drain()
    #expect(probe.replies == [false])
    board.detach()
    controller.close()
}

@MainActor
@Test func salvaTuttoWithANoteAndTheBoardPaneLeftSavesTheNoteAndRevealsTheBoard() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nSalvata da Salva tutto.\n", inColumn: 0, of: controller)
    let (board, path) = try quitConflictedBoard(vault, in: controller)
    board.enterPane()
    board.leavePane()
    let before = bytes(root, path)
    let probe = ConflictProbe()
    let quit = probe.coordinator(controller, diary: nil) { _ in .save }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [false])
    #expect(quitOnDisk(root, "Nexion.md")?.contains("Salvata da Salva tutto.") == true)
    #expect(probe.shown == [.board])
    #expect(bytes(root, path) == before)
    probe.openAllGates()
    await drain()
    #expect(probe.replies.count == 1)
    board.detach()
    controller.close()
}

@MainActor
@Test func nonSalvareWithTheBoardPaneLeftLetsTheQuitGoAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let (board, path) = try quitConflictedBoard(vault, in: controller)
    board.enterPane()
    board.leavePane()
    let before = bytes(root, path)
    let probe = ConflictProbe()
    let quit = probe.coordinator(controller, diary: nil) { _ in .discard }

    #expect(quit.shouldTerminate() == .now)

    #expect(probe.asked.count == 1)
    #expect(probe.asked.first?.board?.path == path)
    #expect(probe.replies.isEmpty)
    #expect(probe.shown.isEmpty)
    #expect(bytes(root, path) == before)
    board.detach()
    controller.close()
}
