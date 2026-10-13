import Foundation
import Testing
@testable import Pergamenum

// PG-392, ADR-0091 - (coverage). Business logic the diff touches that the requirement tests do
// not reach: the staying clause of the board and diary sentences on every occasion, the
// derivation of `openBoardPath`, what `detach()` writes and what it never does, and how a
// cancelled vault switch records and reveals when the board is not the only thing left. Each
// asserts what the plan, the ADR or an existing caller already states, nothing more.

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

// MARK: The staying clause, on every occasion

@Test func theBoardSentenceCarriesTheStayingClauseOfEachOccasion() {
    let review = QuitReview(columns: [], board: boardItem())
    let tail = "per farti scegliere quale versione tenere, con «Non salvare» le sue modifiche vanno perse."

    // The quit's clause is the old `staying` byte for byte; the other two are lower-case so they
    // read mid-sentence after «con «Salva»».
    let quit = review.copy(for: .quit).informative
    #expect(quit.contains(
        "La board «Bacheca» è cambiata anche su disco: con «Salva» Pergamenum resta aperto \(tail)"
    ))
    let switching = review.copy(for: .vaultSwitch).informative
    #expect(switching.contains("con «Salva» la cartella note resta aperta \(tail)"))
    #expect(!switching.contains("con «Salva» La cartella note"))
    let closing = review.copy(for: .columnClose).informative
    #expect(closing.contains(
        "La board «Bacheca» è cambiata anche su disco: con «Salva» la colonna resta aperta \(tail)"
    ))
    #expect(!closing.contains("con «Salva» La colonna"))
}

@Test func theDiarySentenceCarriesTheStayingClauseOfEachOccasion() {
    let review = QuitReview(columns: [], diary: diaryItem())
    let tail = "per farti scegliere quale versione tenere, con «Non salvare» le sue modifiche vanno perse."
    let head = "Il diario del giorno 11/08/2026 è cambiato anche su disco: con «Salva»"

    #expect(review.copy(for: .quit).informative.contains("\(head) Pergamenum resta aperto \(tail)"))
    #expect(review.copy(for: .vaultSwitch).informative.contains("\(head) la cartella note resta aperta \(tail)"))
    #expect(review.copy(for: .columnClose).informative.contains("\(head) la colonna resta aperta \(tail)"))
}

@Test func theNotesKeepTheirCapitalisedStayingSentenceOnEveryOccasion() {
    // Items without a board or a diary are byte-identical to before ADR-0091 (§D5): the notes'
    // sentences open with the capitalised `staying`, not the clause.
    var conflicted = tab("Nexion.md")
    conflicted.note.externalChangePending = .text("da fuori")
    let review = QuitReview(columns: [column([conflicted])])

    let quit = review.copy(for: .quit).informative
    #expect(quit.contains("«Nexion» è cambiata anche su disco: Pergamenum resta aperto per"))
    let switching = review.copy(for: .vaultSwitch).informative
    #expect(switching.contains("«Nexion» è cambiata anche su disco: La cartella note resta aperta per"))
    let closing = review.copy(for: .columnClose).informative
    #expect(closing.contains("«Nexion» è cambiata anche su disco: La colonna resta aperta per"))
}

@Test func theBoardsCancelLineNamesItsOccasionAndTheSameBoard() {
    // A nested board is named by its file name, whichever occasion speaks.
    let board = boardItem(path: "Progetti/Piano 2.0.canvas")

    #expect(
        board.leftProblem(for: .quit)
            == "Uscita annullata: la board «Piano 2.0» ha un conflitto di salvataggio non risolto"
    )
    #expect(
        board.leftProblem(for: .vaultSwitch)
            == "Apertura di un'altra cartella note annullata: "
            + "la board «Piano 2.0» ha un conflitto di salvataggio non risolto"
    )
    #expect(
        board.leftProblem(for: .columnClose)
            == "Chiusura della colonna annullata: la board «Piano 2.0» ha un conflitto di salvataggio non risolto"
    )
    // Three occasions, three different lines; the quit's alone is the bare `leftProblem`.
    #expect(Set([QuitReview.Occasion.quit, .vaultSwitch, .columnClose].map { board.leftProblem(for: $0) }).count == 3)
    #expect(board.leftProblem(for: .quit) == board.leftProblem)
}

// MARK: openBoardPath is derived from the owned board

@MainActor
@Test func openBoardPathFollowsTheBoardThroughOpenLeaveReleaseAndClose() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let board = controller.openBoard
    #expect(controller.openBoardPath == nil)

    let path = try CanvasStore(root: rootA).createBoard(named: "Piano", in: "Progetti")
    board.open(board: path)
    board.enterPane()
    // The vault-relative path of the board, folder included - the identity `board` itself uses.
    #expect(controller.openBoardPath == path)
    #expect(controller.openBoardPath == board.board)

    // A leave that keeps the board keeps its path; a leave that releases it reads nil, no stale copy.
    _ = board.addStickyNote("pendente", at: .zero)
    try await withReadOnlyFolder(rootA, "Progetti") {
        board.leavePane()
        #expect(board.saveState == .pending)
        #expect(controller.openBoardPath == path)
    }
    board.enterPane()
    board.leavePane()
    #expect(board.saveState == .saved)
    #expect(controller.openBoardPath == nil)

    board.open(board: path)
    #expect(controller.openBoardPath == path)
    controller.close()
    #expect(controller.openBoardPath == nil)
}

// MARK: detach, what it writes and what it never does

@MainActor
@Test func detachWritesAPendingBoardAndRecordsNoLoss() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let path = try CanvasStore(root: rootA).createBoard(named: "Piano", in: "")
    let board = controller.openBoard
    board.open(board: path)
    let id = board.addStickyNote("pendente", at: .zero)
    #expect(board.saveState == .pending)
    let before = controller.problems.count

    board.detach()

    let onDisk = try CanvasStore(root: rootA).load(board: path)
    #expect(onDisk.node(id: id) != nil)
    #expect(controller.problems.count == before)
    #expect(board.board == "")
    #expect(board.saveState == .saved)
    #expect(board.store == nil)
    controller.close()
}

@MainActor
@Test func detachNeverWritesOverTheOtherWritersFileAndSaysSoOnce() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let (board, path) = try quitConflictedBoard(a, in: controller)
    let theirs = bytes(rootA, path)
    let before = controller.problems.count

    board.detach()
    board.detach()

    #expect(bytes(rootA, path) == theirs)
    let added = Array(controller.problems.dropFirst(before))
    #expect(added.count == 1)
    #expect(added.first?.contains("«\(path)» aveva un conflitto di salvataggio non risolto") == true)
    controller.close()
}

@MainActor
@Test func detachOnABoardNeverBoundToAStoreRecordsAndChangesNothing() {
    // The guard at the top of `detach()`: nothing attached, so nothing to leave.
    let board = WorkspaceController()
    board.detach()
    board.detach()

    #expect(board.store == nil)
    #expect(board.board == "")
    #expect(board.saveState == .saved)
}

// MARK: A cancelled switch with more than the board left

@MainActor
@Test func aSwitchCancelledWithNoRevealHookStillCancelsAndRecordsTheBoardLine() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    let (board, path) = try quitConflictedBoard(a, in: controller)
    // `revealOpenBoard` is nil unless the app wires it (its one production writer).
    #expect(controller.revealOpenBoard == nil)
    let before = bytes(rootA, path)

    let switched = await controller.switchVault(to: rootB) { _ in .save }

    #expect(!switched)
    #expect(controller.root?.vaultKey == rootA.vaultKey)
    #expect(controller.problems.contains(board.quitConflict?.leftProblem(for: .vaultSwitch) ?? "<none>"))
    #expect(bytes(rootA, path) == before)
    board.detach()
    controller.close()
}

@MainActor
@Test func aConflictedNoteAndTheConflictedBoardRecordBothLinesAndRevealTheBoard() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    let id = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    controller.updateTab(id) { $0.note.externalChangePending = .text(quitNote("Da fuori.")) }
    let (board, path) = try quitConflictedBoard(a, in: controller)
    var revealed = 0
    controller.revealOpenBoard = { revealed += 1 }
    let before = bytes(rootA, path)
    let problems = controller.problems.count

    let switched = await controller.switchVault(to: rootB) { _ in .save }

    #expect(!switched)
    // One line per kind of item left, the notes' first, then the board's; the first item of
    // ADR-0089 §D6's order is revealed, and that is the board.
    let added = Array(controller.problems.dropFirst(problems))
    #expect(added.count == 2)
    #expect(added.first?.contains("note non salvate: «Nexion.md»") == true)
    #expect(added.last == board.quitConflict?.leftProblem(for: .vaultSwitch))
    #expect(revealed == 1)
    #expect(bytes(rootA, path) == before)
    #expect(quitOnDisk(rootA, "Nexion.md") == quitNote("Nexion."))
    board.detach()
    controller.close()
}

@MainActor
@Test func aConflictedNoteAloneCancelsTheSwitchWithoutRevealingTheBoard() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    let id = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    controller.updateTab(id) { $0.note.externalChangePending = .text(quitNote("Da fuori.")) }
    var revealed = 0
    controller.revealOpenBoard = { revealed += 1 }
    let problems = controller.problems.count

    let switched = await controller.switchVault(to: rootB) { _ in .save }

    #expect(!switched)
    #expect(controller.root?.vaultKey == rootA.vaultKey)
    #expect(revealed == 0)
    let added = Array(controller.problems.dropFirst(problems))
    #expect(added.count == 1)
    #expect(added.first?.contains("note non salvate: «Nexion.md»") == true)
    #expect(controller.focusedTab?.id == id)
    controller.close()
}
