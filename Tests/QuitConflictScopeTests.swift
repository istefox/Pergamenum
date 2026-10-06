import Foundation
import Testing
@testable import Pergamenum

// PG-336, ADR-0089 §D1, plan Task 5 (R-09): only the quit passes a board and a diary day to the
// review. The vault switch and «Chiudi la colonna» build their review from the editor columns
// alone, so a conflicted board or diary - both present and conflicted here - never reaches
// their question, its words or its answer.

@MainActor
@Test func theVaultSwitchQuestionNamesTheNotesAloneNeverABoardOrADiary() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    let id = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    let (board, _) = try quitConflictedBoard(a, in: controller)
    let diary = try await quitConflictedDiary(in: controller, root: rootA)
    #expect(controller.openBoard === board)
    var asked: [QuitReview] = []

    let switched = await controller.switchVault(to: rootB) { review in
        asked.append(review)
        return .cancel
    }

    #expect(!switched)
    let review = try #require(asked.first)
    #expect(asked.count == 1)
    #expect(review.board == nil)
    #expect(review.diary == nil)
    #expect(review.entries.map(\.tabID) == [id])
    // The words are the vault switch's, for the notes alone.
    let notesAlone = QuitReview(columns: controller.columns).copy(for: .vaultSwitch)
    let copy = review.copy(for: .vaultSwitch)
    #expect(copy == notesAlone)
    let text = copy.message + "\n" + copy.informative
    #expect(!text.contains("board"))
    #expect(!text.contains("Bacheca"))
    #expect(!text.contains("diario"))
    #expect(text.contains("prima di aprire un'altra cartella note?"))
    #expect(controller.root?.vaultKey == rootA.vaultKey)
    // Both conflicts are still waiting, untouched by the question.
    if case .conflicted = board.saveState {} else { Issue.record("board left the conflict") }
    if case .conflicted = diary.saveState {} else { Issue.record("diary left the conflict") }
    board.detach()
    controller.close()
}

@MainActor
@Test func theColumnCloseQuestionNamesTheColumnsNotesAloneNeverABoardOrADiary() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let id = try openDirty("Nexion.md", adding: "\nSinistra.\n", inColumn: 0, of: controller)
    controller.addColumn()
    #expect(controller.columns.count == 2)
    let (board, _) = try quitConflictedBoard(vault, in: controller)
    let diary = try await quitConflictedDiary(in: controller, root: root)
    #expect(controller.openBoard === board)
    var asked: [QuitReview] = []

    let closed = await controller.closeColumn(0) { review in
        asked.append(review)
        return .cancel
    }

    #expect(!closed)
    let review = try #require(asked.first)
    #expect(asked.count == 1)
    #expect(review.board == nil)
    #expect(review.diary == nil)
    #expect(review.entries.map(\.tabID) == [id])
    let notesAlone = QuitReview(columns: [controller.columns[0]]).copy(for: .columnClose)
    let copy = review.copy(for: .columnClose)
    #expect(copy == notesAlone)
    let text = copy.message + "\n" + copy.informative
    #expect(!text.contains("board"))
    #expect(!text.contains("Bacheca"))
    #expect(!text.contains("diario"))
    #expect(text.contains("prima di chiudere la colonna?"))
    #expect(controller.columns.count == 2)
    if case .conflicted = board.saveState {} else { Issue.record("board left the conflict") }
    if case .conflicted = diary.saveState {} else { Issue.record("diary left the conflict") }
    board.detach()
    controller.close()
}

@MainActor
@Test func aConflictedBoardAndDiaryAloneAskNothingAtAVaultSwitchOrColumnClose() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    controller.openNote(at: "Nexion.md")
    controller.addColumn()
    let (board, _) = try quitConflictedBoard(a, in: controller)
    _ = try await quitConflictedDiary(in: controller, root: rootA)
    var asked = 0

    // A clean column closes without a question: a conflicted board is not this door's business.
    let closed = await controller.closeColumn(1) { _ in
        asked += 1
        return .cancel
    }
    #expect(closed)
    #expect(asked == 0)

    // Neither does the vault switch ask.
    board.detach()
    let switched = await controller.switchVault(to: rootB) { _ in
        asked += 1
        return .cancel
    }
    #expect(asked == 0)
    #expect(switched)
    controller.close()
}
