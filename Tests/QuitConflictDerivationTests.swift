import Foundation
import Testing
@testable import Pergamenum

// PG-336, ADR-0089 D2, plan Task 2: `WorkspaceController.quitConflict` and
// `DiaryController.quitConflict`, the derivations that turn a conflicted board or diary day into
// a quit item. Split from `QuitConflictTests.swift`.

// MARK: The derivations (ADR-0089 §D2)

@MainActor
@Test func aSavedOrPendingBoardIsNoQuitItem() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    let store = CanvasStore(root: vault.root)
    let path = try store.createBoard(named: "Bacheca", in: "")
    let board = WorkspaceController()
    board.attach(to: store, vault: controller)
    #expect(board.quitConflict == nil)

    board.open(board: path)
    #expect(board.saveState == .saved)
    #expect(board.quitConflict == nil)

    _ = board.addStickyNote("nota", at: .zero)
    #expect(board.saveState == .pending)
    #expect(board.quitConflict == nil)
    board.detach()
    controller.close()
}

@MainActor
@Test func aControllerWithNoBoardOpenIsNoQuitItem() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    let board = WorkspaceController()
    board.attach(to: CanvasStore(root: vault.root), vault: controller)

    #expect(board.board == "")
    #expect(board.quitConflict == nil)
    board.detach()
    controller.close()
}

@MainActor
@Test func aConflictedBoardCarriesItsPathAndDocument() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    let (board, path) = try quitConflictedBoard(vault, in: controller)

    #expect(board.quitConflict == QuitReview.Board(path: path, document: board.document))
    #expect(board.quitConflict?.name == "Bacheca")
    board.detach()
    controller.close()
}

@MainActor
@Test func aSavedOrPendingDiaryIsNoQuitItem() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    let diary = DiaryController(vault: controller)
    diary.show(testDay)
    #expect(diary.quitConflict == nil)

    diary.prose += "Frase.\n"
    #expect(diary.saveState != .saved)
    #expect(diary.quitConflict == nil)
    await diary.settle()
    controller.close()
}

@MainActor
@Test func aConflictedDiaryCarriesItsDayProseAndEntries() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    let diary = try await quitConflictedDiary(in: controller, root: vault.root)

    #expect(
        diary.quitConflict
            == QuitReview.DiaryDay(day: diary.day, prose: diary.prose, entries: diary.entries)
    )
    #expect(diary.quitConflict?.day == testDay)
    #expect(diary.quitConflict?.prose.contains("Frase mia.") == true)
    controller.close()
}
