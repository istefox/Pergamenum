import Foundation
import Testing
@testable import Pergamenum

// PG-336, ADR-0089 §D1, plan Task 5 (R-09), amended by PG-392 / ADR-0091 §D5 (R-06): the quit
// passes a board and a diary day to the review. The vault switch passes the board and never the
// diary, and «Chiudi la colonna» passes neither, so a conflicted diary - present and conflicted
// here - never reaches the switch's or the column close's question, words or answer, and a
// conflicted board reaches the switch's only.
//
// G4 (2026-10-08): the first test below asserted that the switch never names a board, and the
// third detached the board so the switch would ask nothing. ADR-0091 reverses the first and
// makes the second premise moot; both are rewritten to assert the new contract, none disabled.

@MainActor
@Test func theVaultSwitchQuestionNamesTheNotesAndTheBoardNeverTheDiary() async throws {
    // G4: this test asserted that the switch never names a board. ADR-0091 §D5 (R-06) reverses
    // that: the board is asked about, the diary is not.
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
    #expect(review.board == board.quitConflict)
    #expect(review.board != nil)
    #expect(review.diary == nil)
    #expect(review.entries.map(\.tabID) == [id])
    // The words are the vault switch's, for the notes and the board.
    let notesAlone = QuitReview(columns: controller.columns).copy(for: .vaultSwitch)
    let copy = review.copy(for: .vaultSwitch)
    #expect(copy != notesAlone)
    let text = copy.message + "\n" + copy.informative
    #expect(text.contains("Bacheca"))
    #expect(!text.contains("diario"))
    #expect(text.contains("prima di aprire un'altra cartella note?"))
    #expect(controller.root?.vaultKey == rootA.vaultKey)
    // Both conflicts are still waiting, untouched by the question.
    if case .conflicted = board.saveState {} else { Issue.record("board left the conflict") }
    if case .conflicted = diary.saveState {} else { Issue.record("diary left the conflict") }
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
@Test func aConflictedBoardAndDiaryAloneAskNothingAtAColumnClose() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    controller.openNote(at: "Nexion.md")
    controller.addColumn()
    _ = try quitConflictedBoard(a, in: controller)
    _ = try await quitConflictedDiary(in: controller, root: rootA)
    var asked = 0

    // A clean column closes without a question: a conflicted board is not this door's business.
    let closed = await controller.closeColumn(1) { _ in
        asked += 1
        return .cancel
    }
    #expect(closed)
    #expect(asked == 0)
    controller.close()
}

@MainActor
@Test func aConflictedDiaryAloneAsksNothingAtAVaultSwitch() async throws {
    // G4: the third test used to detach the board so the switch asked nothing. The board now
    // asks (ADR-0091 §D5), so the half that stays true is the diary's (R-09): a vault with a
    // conflicted diary only and no board.
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    _ = try await quitConflictedDiary(in: controller, root: rootA)
    #expect(controller.openBoard.quitConflict == nil)
    var asked = 0

    let switched = await controller.switchVault(to: rootB) { _ in
        asked += 1
        return .cancel
    }

    #expect(asked == 0)
    #expect(switched)
    controller.close()
}
