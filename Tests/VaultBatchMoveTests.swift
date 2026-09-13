import Foundation
import Testing
@testable import Pergamenum

// ADR-0041 §D8 (Task 7): a batch move computes one plan instead of one plan per item.
// Plan: docs/superpowers/plans/2026-09-12-vault-layer-consistency-and-security-cha.md, Task 7.
//
// Before this task, `VaultSession.moveItems` loops over its items and calls `moveNote` /
// `moveBoard` / `moveFolder` per item; each of those runs its own repoint pass over every
// board in the vault, and each moved starred note triggers its own `starred.json` rewrite.
// A batch of five moved notes, all starred, today produces **five** board-repoint walks and
// **five** `starred.json` writes (`perf-VaultSession+Move.swift-2a6`,
// `perf-VaultSession+Starred.swift-4d9`). After the coder's work: one walk, one repoint pass
// for the whole batch, one `starred.json` write.
//
// **Tester declares** (`Sources/Vault/VaultSession+Starred.swift`,
// `Sources/Vault/FolderFileOperations.swift`):
//
//     extension VaultSession {
//         func moveStars(_ pairs: [(old: String, new: String)])
//     }
//     extension FolderFileOperations {
//         func repointBoardsPlan(moves: [(from: String, to: String)])
//             -> (changes: [VaultFileChange], failures: [String])
//     }
//
// Both are given a *stub* body that reuses the existing single-pair primitives once per
// entry - correct output, but not batched, so the counters below are red against it. The
// coder replaces the stub bodies; the declared signatures do not change.
//
// **Two test-only counters were added alongside the stubs, and the coder's real
// implementation must keep incrementing them** or the call-count tests below cannot ever go
// green:
//   - `FolderFileOperations.onBoardsWalk: () -> Void` - called once per pass over
//     `canvas.allBoards()`.
//   - `VaultSession.testOnlyStarredSaveCount` - incremented once per `starredStore.save`.
// Both are per-instance (a fresh `FolderFileOperations`/`VaultSession` per test), so nothing
// here can race with another test file's concurrent execution the way a global/static
// counter would.
//
// **Scoping note, stated rather than silently worked around:** `VaultSession.moveNote`
// (`VaultSession+Files.swift`) repoints boards through `NoteFileOperations`'s own, separate,
// `private` copy of a repoint pass - not `FolderFileOperations.repointBoardsPlan`. That copy
// is outside this task's declared Budget (`Sources/Vault/VaultSession+Move.swift`,
// `Sources/Vault/VaultSession+Starred.swift`, `Sources/Vault/FolderFileOperations.swift`) and
// outside the two signatures the brief asked the tester to declare, so the walk-count claim
// below is exercised directly against `FolderFileOperations.repointBoardsPlan(moves:)` (the
// declared unit) rather than through `session.moveItems` with `.note` items, which would
// silently need a third, undeclared file instrumented to mean anything. The starred-write
// count, by contrast, *is* exercised end-to-end through `session.moveItems` with `.note`
// items, because starring is entirely a `VaultSession`-level concern that never delegates
// into `NoteFileOperations`.

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-09-12\ntags:\n  - type-note\n---\n\n\(body)\n"
}

/// A `.canvas` with one file-node per path in `paths`, `id`s numbered so a board with several
/// nodes has stable, distinguishable ids to check node-by-node.
private func board(nodes paths: [String]) -> String {
    let nodes = paths.enumerated().map { index, path in
        """
        {"id":"n\(index)","type":"file","file":"\(path)","x":0,"y":0,"width":260,"height":180}
        """
    }.joined(separator: ",")
    return #"{"nodes":[\#(nodes)],"edges":[]}"#
}

@MainActor
private func session(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

// MARK: - `FolderFileOperations.repointBoardsPlan(moves:)`: one walk, not one per pair (R-05)

@Test func repointBoardsPlanWalksOnceRegardlessOfHowManyMovesAreInTheBatch() throws {
    let vault = try TemporaryVault()
    try vault.write(board(nodes: ["A/one.md"]), to: "Board.canvas")
    var operations = FolderFileOperations(store: NoteStore(root: vault.root))
    var walkCount = 0
    operations.onBoardsWalk = { walkCount += 1 }

    // Five moves, mirroring "five notes into one folder" - none of these five paths is
    // actually referenced by the fixture board above, which is the point: the walk-count
    // claim holds regardless of how many of the moves turn out to touch a board.
    let moves: [(from: String, to: String)] = (1...5).map { ("A/x\($0).md", "B/x\($0).md") }

    _ = operations.repointBoardsPlan(moves: moves)

    // RED against the stub above: it calls the single-pair `repointBoardsPlan(from:to:)`
    // once per entry, so `walkCount` is 5 here today - the number the ADR's §D8 records as
    // the pre-task count for this exact shape of fixture. It must become 1 once the coder
    // replaces the loop with one pass over `canvas.allBoards()`.
    #expect(walkCount == 1, "un batch di 5 spostamenti deve percorrere il vault una sola volta, non cinque")
}

@Test func repointBoardsPlanOfAnEmptyBatchWalksNotAtAllAndChangesNothing() throws {
    let vault = try TemporaryVault()
    try vault.write(board(nodes: ["A/one.md"]), to: "Board.canvas")
    var operations = FolderFileOperations(store: NoteStore(root: vault.root))
    var walkCount = 0
    operations.onBoardsWalk = { walkCount += 1 }

    let result = operations.repointBoardsPlan(moves: [])

    #expect(result.changes.isEmpty)
    #expect(result.failures.isEmpty)
    #expect(walkCount == 0, "un batch vuoto non ha nulla da ripercorrere")
}

@Test func repointBoardsPlanOfASingleMoveMatchesTheSinglePairForm() throws {
    let vault = try TemporaryVault()
    try vault.write(board(nodes: ["A/one.md"]), to: "Board.canvas")
    let operations = FolderFileOperations(store: NoteStore(root: vault.root))

    let batched = operations.repointBoardsPlan(moves: [(from: "A/one.md", to: "B/one.md")])
    let singlePair = operations.repointBoardsPlan(from: "A/one.md", to: "B/one.md")

    #expect(batched.changes == singlePair.changes)
    #expect(batched.failures == singlePair.failures)
}

// MARK: - Two notes on the same board: one merged rewrite, not two lossy ones (R-05)

@Test func twoMovesTouchingTheSameBoardProduceOneChangeWithBothNodesRepointed() throws {
    let vault = try TemporaryVault()
    try vault.write(board(nodes: ["A/one.md", "A/two.md", "A/untouched.md"]), to: "Shared.canvas")
    let operations = FolderFileOperations(store: NoteStore(root: vault.root))

    let result = operations.repointBoardsPlan(moves: [
        (from: "A/one.md", to: "B/one.md"),
        (from: "A/two.md", to: "B/two.md"),
    ])

    // RED against the stub: it computes each move's change from the board's original,
    // unwritten bytes and returns one `VaultFileChange` per move, so this array has two
    // entries for the same board path - a caller applying them in order would keep only the
    // second, losing the first move's repoint (exactly the drift ADR-0041 names).
    #expect(result.changes.count == 1, "le due modifiche allo stesso file devono unirsi in una sola")
    let after = try #require(result.changes.first).after
    #expect(after.contains("B/one.md"), "il primo nodo spostato deve comparire nel merge")
    #expect(after.contains("B/two.md"), "il secondo nodo spostato deve comparire nel merge")
    #expect(after.contains("A/untouched.md"), "il nodo non spostato non deve sparire")
}

// MARK: - `VaultSession.moveStars(_:)`: one save for the whole batch (R-05)

@MainActor
@Test func moveStarsSavesOnceForABatchOfThreePairs() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A/one.md")
    try vault.write(note(), to: "A/two.md")
    try vault.write(note(), to: "A/three.md")
    let session = try await session(vault)
    session.toggleStar("A/one.md")
    session.toggleStar("A/two.md")
    session.toggleStar("A/three.md")
    session.testOnlyStarredSaveCount = 0

    session.moveStars([
        (old: "A/one.md", new: "B/one.md"),
        (old: "A/two.md", new: "B/two.md"),
        (old: "A/three.md", new: "B/three.md"),
    ])

    #expect(session.isStarred("B/one.md") && session.isStarred("B/two.md") && session.isStarred("B/three.md"))
    #expect(!session.isStarred("A/one.md") && !session.isStarred("A/two.md") && !session.isStarred("A/three.md"))
    #expect(StarredStore(root: vault.root).load() == ["B/one.md", "B/two.md", "B/three.md"])
    // RED against the stub: it calls `moveStar(from:to:)` once per pair, so this is 3 today,
    // not 1 - exactly `perf-VaultSession+Starred.swift-4d9`.
    #expect(session.testOnlyStarredSaveCount == 1, "un batch di tre stelle spostate deve salvare una sola volta")
}

@MainActor
@Test func moveStarsOfAnEmptyBatchSavesNotAtAll() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A/one.md")
    let session = try await session(vault)
    session.toggleStar("A/one.md")
    session.testOnlyStarredSaveCount = 0

    session.moveStars([])

    #expect(session.isStarred("A/one.md"), "un batch vuoto non deve toccare le stelle esistenti")
    #expect(session.testOnlyStarredSaveCount == 0)
}

@MainActor
@Test func moveStarsOfASinglePairMatchesMoveStar() async throws {
    let vaultA = try TemporaryVault()
    try vaultA.write(note(), to: "A/one.md")
    let sessionA = try await session(vaultA)
    sessionA.toggleStar("A/one.md")

    let vaultB = try TemporaryVault()
    try vaultB.write(note(), to: "A/one.md")
    let sessionB = try await session(vaultB)
    sessionB.toggleStar("A/one.md")

    sessionA.moveStar(from: "A/one.md", to: "B/one.md")
    sessionB.moveStars([(old: "A/one.md", new: "B/one.md")])

    #expect(sessionA.isStarred("B/one.md") == sessionB.isStarred("B/one.md"))
    #expect(StarredStore(root: vaultA.root).load() == StarredStore(root: vaultB.root).load())
}

// MARK: - A batch of five, three starred: the file holds exactly the three new paths (R-05)

@MainActor
@Test func aBatchOfFiveNotesThreeStarredLeavesStarredJSONWithExactlyTheThreeNewPaths() async throws {
    let vault = try TemporaryVault()
    for index in 1...5 {
        try vault.write(note(), to: "A/n\(index).md")
    }
    let session = try await session(vault)
    session.toggleStar("A/n1.md")
    session.toggleStar("A/n3.md")
    session.toggleStar("A/n5.md")
    session.testOnlyStarredSaveCount = 0

    let outcome = session.moveItems(
        (1...5).map { VaultItemRef(path: "A/n\($0).md", kind: .note) }, into: "B"
    )

    #expect(outcome.moves.count == 5)
    let stored = StarredStore(root: vault.root).load()
    #expect(stored == ["B/n1.md", "B/n3.md", "B/n5.md"])
    #expect(!stored.contains("A/n1.md") && !stored.contains("A/n3.md") && !stored.contains("A/n5.md"))
    // RED against today's `moveItems`: it moves each note through `moveNote`, which calls
    // `moveStar` directly (not the new `moveStars`), so this is 3 today - one save per
    // starred note in the batch, not one for the whole batch.
    #expect(
        session.testOnlyStarredSaveCount == 1,
        "un batch di cinque note, tre delle quali preferite, deve scrivere starred.json una sola volta"
    )
}

// MARK: - R-06: the failing item sits in the middle of a batch of three

@MainActor
@Test func aFailureInTheMiddleOfAThreeItemBatchLeavesTheOtherTwoMovedAndNamesOnlyTheMiddleOne() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A/first.md")
    try vault.write(note(), to: "A/third.md")
    // Never written: reaches `NoteFileOperations.move` (the plan only checks the
    // *destination* is free, not that the source exists) and throws `.missing` there - the
    // same TOCTOU shape `VaultMoveTests.swift`'s `A/ghost.canvas` already exercises, placed
    // here in the middle of three rather than second of two.
    let session = try await session(vault)

    let outcome = session.moveItems(
        [
            VaultItemRef(path: "A/first.md", kind: .note),
            VaultItemRef(path: "A/ghost.md", kind: .note),
            VaultItemRef(path: "A/third.md", kind: .note),
        ],
        into: "B"
    )

    #expect(outcome.refusals.isEmpty, "il piano deve passare: il fallimento arriva solo in esecuzione")
    #expect(session.exists("B/first.md") && !session.exists("A/first.md"), "il primo elemento deve essersi spostato")
    #expect(session.exists("B/third.md") && !session.exists("A/third.md"), "il terzo elemento deve essersi spostato")
    #expect(!session.exists("B/ghost.md") && !session.exists("A/ghost.md"), "il secondo non è mai esistito, e non deve comparire da nessuna parte")
    #expect(
        outcome.moves.map(\.item.path) == ["A/first.md", "A/third.md"],
        "moves deve descrivere solo ciò che è davvero sul disco - non l'elemento fallito in mezzo"
    )
    #expect(
        outcome.movedNotes.map(\.old).sorted() == ["A/first.md", "A/third.md"],
        "il primo e il terzo devono comparire come spostati, non solo uno dei due"
    )
    #expect(
        outcome.failures.contains { $0.contains("A/ghost.md") },
        "il fallimento deve nominare l'elemento in mezzo, non il primo o il terzo"
    )
    // The point of R-06: no rollback. The first item stays exactly where the batch put it,
    // even though a later item in the same batch failed.
    #expect(session.exists("B/first.md"), "nessun rollback: il primo elemento resta dove il batch lo ha messo")
}
