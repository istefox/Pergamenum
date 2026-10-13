import Foundation
import Testing
@testable import Pergamenum

// PG-392, ADR-0092 §D5/§D6, plan Task 3 (R-06): the vault switch asks about a conflicted
// Workspace board and names it. «Salva» never writes the board: it cancels and reveals it.
// «Annulla» cancels. Only «Non salvare» proceeds, and it writes nothing to the board's file.
// The board is asked about whether the pane is mounted, left or was never mounted, because the
// controller lives with the vault (§D1). `ConflictProbe`-free: the switch takes its `ask`
// closure directly, and `revealOpenBoard` (§D6) is counted by each test.

private func bytes(_ root: URL, _ path: String) -> Data? {
    try? Data(contentsOf: root.appending(path: path))
}

@MainActor
private func isConflicted(_ board: WorkspaceController) -> Bool {
    if case .conflicted = board.saveState { return true }
    return false
}

private func column(_ tabs: [NoteTab]) -> EditorColumn {
    var column = EditorColumn()
    column.tabs = tabs
    column.activeID = tabs.first?.id
    return column
}

/// G2's frozen strings (2026-10-08), spelled out once.
private let switchMessage =
    "Salvare le modifiche alla board «Bacheca» prima di aprire un'altra cartella note?"
private let switchBoardSentence =
    "La board «Bacheca» è cambiata anche su disco: con «Salva» la cartella note resta aperta per farti "
    + "scegliere quale versione tenere, con «Non salvare» le sue modifiche vanno perse."
private let switchBoardLine =
    "Apertura di un'altra cartella note annullata: la board «Bacheca» ha un conflitto di salvataggio non risolto"
private let columnCloseBoardLine =
    "Chiusura della colonna annullata: la board «Bacheca» ha un conflitto di salvataggio non risolto"
private let detachLossFragment = "aveva un conflitto di salvataggio non risolto"

// MARK: The pure copy

@Test func theSwitchCopyForABoardIsG2sFrozenWordsAndTheQuitsStayByteIdentical() {
    let review = QuitReview(columns: [], board: boardItem())

    let copy = review.copy(for: .vaultSwitch)
    #expect(copy.message == switchMessage)
    #expect(copy.informative.contains(switchBoardSentence))
    #expect(copy.informative.contains("la cartella note resta aperta"))
    #expect(copy.saveLabel == "Salva")
    let board = boardItem()
    #expect(board.leftProblem(for: .vaultSwitch) == switchBoardLine)
    #expect(board.leftProblem(for: .columnClose) == columnCloseBoardLine)
    #expect(board.leftProblem(for: .quit) == board.leftProblem)
    #expect(board.leftProblem == boardProblem)

    // «Salva tutto» for more than one item: the same shape.
    let several = QuitReview(columns: [column([tab("A.md")])], board: boardItem()).copy(for: .vaultSwitch)
    #expect(several.saveLabel == "Salva tutto")
    #expect(several.informative.contains(
        switchBoardSentence.replacingOccurrences(of: "«Salva»", with: "«Salva tutto»")
    ))

    // The quit's own words, pinned literally: every quit string stays byte-identical.
    let quit = review.copy(for: .quit)
    #expect(quit.message == "Salvare le modifiche alla board «Bacheca» prima di uscire?")
    #expect(quit.informative.contains(
        "La board «Bacheca» è cambiata anche su disco: con «Salva» Pergamenum resta aperto per farti "
            + "scegliere quale versione tenere, con «Non salvare» le sue modifiche vanno perse."
    ))
    #expect(review.copy == quit)
}

// MARK: The question, whatever the pane did

private enum PaneState {
    case mounted, left, neverMounted
}

@MainActor
private func expectTheSwitchNamesTheConflictedBoard(_ pane: PaneState) async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    let (board, path) = try quitConflictedBoard(a, in: controller)
    var revealed = 0
    controller.revealOpenBoard = { revealed += 1 }
    switch pane {
    case .mounted: board.enterPane()
    case .left:
        board.enterPane()
        board.leavePane()
    case .neverMounted: break
    }
    let before = bytes(rootA, path)
    let problems = controller.problems.count
    var asked: [QuitReview] = []

    let switched = await controller.switchVault(to: rootB) { review in
        asked.append(review)
        return .cancel
    }

    #expect(!switched)
    #expect(asked.count == 1)
    #expect(asked.first?.board != nil)
    #expect(asked.first?.board == board.quitConflict)
    #expect(asked.first?.diary == nil)
    #expect(controller.root?.vaultKey == rootA.vaultKey)
    #expect(isConflicted(board))
    #expect(controller.problems.count == problems)
    #expect(revealed == 0)
    #expect(bytes(rootA, path) == before)
    board.detach()
    controller.close()
}

@MainActor
@Test func theSwitchNamesAConflictedBoardWithThePaneMounted() async throws {
    try await expectTheSwitchNamesTheConflictedBoard(.mounted)
}

@MainActor
@Test func theSwitchNamesAConflictedBoardWithThePaneLeft() async throws {
    try await expectTheSwitchNamesTheConflictedBoard(.left)
}

@MainActor
@Test func theSwitchNamesAConflictedBoardWhosePaneWasNeverMounted() async throws {
    try await expectTheSwitchNamesTheConflictedBoard(.neverMounted)
}

// MARK: The answers

@MainActor
@Test func salvaCancelsTheSwitchRecordsTheBoardLineAndRevealsIt() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    let (board, path) = try quitConflictedBoard(a, in: controller)
    var revealed = 0
    controller.revealOpenBoard = { revealed += 1 }
    let before = bytes(rootA, path)

    let switched = await controller.switchVault(to: rootB) { _ in .save }

    #expect(!switched)
    #expect(controller.root?.vaultKey == rootA.vaultKey)
    #expect(controller.problems.contains { $0.contains(switchBoardLine) })
    #expect(revealed == 1)
    #expect(isConflicted(board))
    #expect(bytes(rootA, path) == before)
    board.detach()
    controller.close()
}

@MainActor
@Test func salvaTuttoWithANoteAndTheBoardSavesTheNoteAndRevealsTheBoard() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    _ = try openDirty("Nexion.md", adding: "\nSalvata dal cambio.\n", inColumn: 0, of: controller)
    let (board, path) = try quitConflictedBoard(a, in: controller)
    var revealed = 0
    controller.revealOpenBoard = { revealed += 1 }
    let before = bytes(rootA, path)
    let problems = controller.problems.count

    let switched = await controller.switchVault(to: rootB) { _ in .save }

    #expect(!switched)
    #expect(quitOnDisk(rootA, "Nexion.md")?.contains("Salvata dal cambio.") == true)
    #expect(Array(controller.problems.dropFirst(problems)) == [switchBoardLine])
    #expect(!controller.problems.contains { $0.contains("note non salvate") })
    #expect(revealed == 1)
    #expect(bytes(rootA, path) == before)
    board.detach()
    controller.close()
}

@MainActor
@Test func nonSalvareLetsTheSwitchGoAndWritesNothingToTheBoardFile() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    let (board, path) = try quitConflictedBoard(a, in: controller)
    var revealed = 0
    controller.revealOpenBoard = { revealed += 1 }
    let before = bytes(rootA, path)

    let switched = await controller.switchVault(to: rootB) { _ in .discard }

    #expect(switched)
    #expect(controller.root?.vaultKey == rootB.vaultKey)
    #expect(bytes(rootA, path) == before)
    #expect(controller.openBoard === board)
    #expect(board.store?.root.vaultKey == rootB.vaultKey)
    #expect(board.board == "")
    #expect(board.saveState == .saved)
    #expect(revealed == 0)
    // ADR-0092 §Consequences: the discarded edit is reported by `detach()`, in B's list now.
    #expect(controller.problems.contains { $0.contains(detachLossFragment) })
    controller.close()
}

@MainActor
@Test func aBoardChangedDuringTheQuestionCancelsTheSwitch() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    let (board, path) = try quitConflictedBoard(a, in: controller)
    var revealed = 0
    controller.revealOpenBoard = { revealed += 1 }
    let before = bytes(rootA, path)

    let switched = await controller.switchVault(to: rootB) { _ in
        _ = board.addStickyNote("scritta durante la domanda", at: .zero)
        return .discard
    }

    #expect(!switched)
    #expect(controller.root?.vaultKey == rootA.vaultKey)
    #expect(controller.problems.contains { $0.contains(switchBoardLine) })
    #expect(revealed == 1)
    #expect(bytes(rootA, path) == before)
    board.detach()
    controller.close()
}

// MARK: A board that is not conflicted

@MainActor
@Test func aPendingBoardIsWrittenBeforeTheQuestionAndAsksNothing() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    let path = try CanvasStore(root: rootA).createBoard(named: "Piano", in: "")
    let board = controller.openBoard
    board.open(board: path)
    let id = board.addStickyNote("pendente", at: .zero)
    #expect(board.saveState == .pending)
    var asked = 0

    let switched = await controller.switchVault(to: rootB) { _ in
        asked += 1
        return .cancel
    }

    #expect(asked == 0)
    #expect(switched)
    let onDisk = try CanvasStore(root: rootA).load(board: path)
    #expect(onDisk.node(id: id) != nil)
    controller.close()
}

@MainActor
@Test func aPendingBoardRefusedByTheSwitchsSettleIsAsked() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    let path = try CanvasStore(root: rootA).createBoard(named: "Bacheca", in: "")
    let board = controller.openBoard
    board.open(board: path)
    _ = board.addStickyNote("pendente", at: .zero)
    let externalStore = CanvasStore(root: rootA)
    var diverged = try externalStore.load(board: path)
    diverged.nodes.append(CanvasNode(
        id: "external", kind: .text("altro"), x: 400, y: 400, width: 100, height: 60
    ))
    try externalStore.save(diverged, board: path)
    #expect(board.saveState == .pending)
    var asked: [QuitReview] = []

    let switched = await controller.switchVault(to: rootB) { review in
        asked.append(review)
        return .cancel
    }

    #expect(!switched)
    #expect(asked.count == 1)
    #expect(asked.first?.board?.path == path)
    #expect(asked.first?.board?.name == "Bacheca")
    #expect(controller.root?.vaultKey == rootA.vaultKey)
    board.detach()
    controller.close()
}

// MARK: Nothing to ask

@MainActor
@Test func reopeningTheOpenVaultAsksNothingAboutTheBoard() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let (board, path) = try quitConflictedBoard(a, in: controller)
    var asked = 0

    let switched = await controller.switchVault(to: rootA) { _ in
        asked += 1
        return .cancel
    }

    #expect(asked == 0)
    #expect(switched)
    #expect(isConflicted(board))
    #expect(board.board == path)
    board.detach()
    controller.close()
}

@MainActor
@Test func aFirstOpenAsksNothing() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    var asked = 0

    let switched = await controller.switchVault(to: rootA) { _ in
        asked += 1
        return .cancel
    }

    #expect(asked == 0)
    #expect(switched)
    #expect(controller.root?.vaultKey == rootA.vaultKey)
    controller.close()
}
