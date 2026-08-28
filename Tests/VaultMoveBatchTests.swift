import Foundation
import Testing
@testable import Pergamenum

// ADR-0026: A row is dragged into a folder, and several rows are chosen first.
// Plan: docs/superpowers/plans/2026-08-27-drag-and-drop-board-files-into-workspace.md,
// Task 1.
//
// `VaultMoveBatch` is the pure decision a drop makes, before any file on disk is
// touched (ADR-0026 §D1, §D6): given the items a drag carries and the folder it lands
// in, `plan` decides which moves happen, which are silently dropped as redundant, and
// whether the whole batch is refused - and `inverse` is the undo half. `exists` is
// injected so every rule below runs against plain values, no temp directory required
// (unlike `BoardFileOperationsTests.swift`/`FolderFileOperationTests.swift`, which do
// need one for Task 2's on-disk `movePlan`/`move`).
//
// RED here: `VaultMoveBatch.plan` always returns `.refused([])` and `.inverse` returns
// its input unchanged (`Sources/Vault/VaultMoveBatch.swift`), so every test below fails
// on its assertion, not on a missing symbol. The five rules `plan` must implement -
// cycle refusal, descendant-drop, already-there-drop, destination collision, and
// within-batch name clash - are the code step of Task 1.

// MARK: - R-05: a single item, and the vault root as a legal destination

@Test func planMovingASingleBoardIntoAFolderYieldsOneMoveFromItsContainingFolder() {
    let item = VaultItemRef(path: "A/x.canvas", kind: .board)

    let result = VaultMoveBatch.plan([item], into: "B", exists: { _ in false })

    #expect(result == .moves([VaultMove(item: item, from: "A", to: "B")]))
}

@Test func planIntoTheVaultRootSpelledEmptyStringIsALegalDestination() {
    let item = VaultItemRef(path: "A/x.canvas", kind: .board)

    let result = VaultMoveBatch.plan([item], into: "", exists: { _ in false })

    #expect(result == .moves([VaultMove(item: item, from: "A", to: "")]))
}

// MARK: - R-06: a folder into itself or a descendant is a cycle, a similarly-named
// sibling is not

@Test func planRefusesAFolderMovedIntoItself() {
    let item = VaultItemRef(path: "a", kind: .folder)

    let result = VaultMoveBatch.plan([item], into: "a", exists: { _ in false })

    guard case .refused = result else {
        Issue.record("expected .refused for a folder dropped on itself, got \(result)")
        return
    }
}

@Test func planRefusesAFolderMovedIntoItsOwnDescendant() {
    let item = VaultItemRef(path: "a", kind: .folder)

    let result = VaultMoveBatch.plan([item], into: "a/sub", exists: { _ in false })

    guard case .refused = result else {
        Issue.record("expected .refused for a folder dropped on its own descendant, got \(result)")
        return
    }
}

@Test func planDoesNotTreatASimilarlyNamedSiblingAsADescendant() {
    // "a-altro" does not have the prefix "a/", so it is not a descendant of "a" - the
    // same prefix rule `FolderFileOperations.repointing` already uses
    // (`"\(folder)/"`, never bare `folder`). Dropping "a" onto "a-altro" is legal.
    let item = VaultItemRef(path: "a", kind: .folder)

    let result = VaultMoveBatch.plan([item], into: "a-altro", exists: { _ in false })

    #expect(result == .moves([VaultMove(item: item, from: "", to: "a-altro")]))
}

// MARK: - ADR-0026 §D6.1: an ancestor and its own descendant in the same batch

@Test func planDropsADescendantSilentlyWhenItsAncestorFolderIsInTheSameBatch() {
    let ancestor = VaultItemRef(path: "a", kind: .folder)
    let descendant = VaultItemRef(path: "a/sub", kind: .folder)

    let result = VaultMoveBatch.plan([ancestor, descendant], into: "B", exists: { _ in false })

    // Not an error, not a cycle: the descendant moves along with its ancestor, so it is
    // dropped from the batch rather than planned (and, in particular, never refused).
    #expect(result == .moves([VaultMove(item: ancestor, from: "", to: "B")]))
}

// MARK: - ADR-0026 §D6.2: an item already directly inside the destination

@Test func planDropsAnItemAlreadyDirectlyInsideTheDestinationWithoutError() {
    let alreadyThere = VaultItemRef(path: "B/x.canvas", kind: .board)
    let elsewhere = VaultItemRef(path: "A/y.canvas", kind: .board)

    let result = VaultMoveBatch.plan([alreadyThere, elsewhere], into: "B", exists: { _ in false })

    #expect(result == .moves([VaultMove(item: elsewhere, from: "A", to: "B")]))
}

@Test func planOutputExcludesAnAlreadyThereItemSoInverseNeverRestoresItsNoOpMove() {
    let alreadyThere = VaultItemRef(path: "B/x.canvas", kind: .board)
    let elsewhere = VaultItemRef(path: "A/y.canvas", kind: .board)

    guard case .moves(let moves) = VaultMoveBatch.plan(
        [alreadyThere, elsewhere], into: "B", exists: { _ in false }
    ) else {
        Issue.record("expected a batch mixing an already-there item with a real mover to plan as .moves")
        return
    }

    let inverse = VaultMoveBatch.inverse(of: moves)
    #expect(!inverse.contains { $0.item == alreadyThere })
}

// MARK: - R-07: collisions, at the destination and within the batch itself

@Test func planRefusesADestinationThatAlreadyHoldsTheNameNamingTheConflict() {
    let item = VaultItemRef(path: "A/x.canvas", kind: .board)

    let result = VaultMoveBatch.plan([item], into: "B", exists: { $0 == "B/x.canvas" })

    guard case .refused(let reasons) = result else {
        Issue.record("expected .refused for a destination collision, got \(result)")
        return
    }
    #expect(reasons.contains { $0.contains("x.canvas") })
}

@Test func planRefusesTwoItemsInOneBatchThatWouldLandOnTheSameNameEvenWithNoDiskCollision() {
    let fromA = VaultItemRef(path: "A/x.canvas", kind: .board)
    let fromC = VaultItemRef(path: "C/x.canvas", kind: .board)

    let result = VaultMoveBatch.plan([fromA, fromC], into: "B", exists: { _ in false })

    guard case .refused = result else {
        Issue.record("expected .refused for two items landing on the same destination name, got \(result)")
        return
    }
}

// MARK: - R-11/R-12: inverse is the undo half of a completed move

@Test func inverseSwapsFromAndToPerMoveAndPreservesOrder() {
    let refA = VaultItemRef(path: "A/x.canvas", kind: .board)
    let refB = VaultItemRef(path: "C/y.md", kind: .note)
    let moves = [
        VaultMove(item: refA, from: "A", to: "B"),
        VaultMove(item: refB, from: "C", to: "B"),
    ]

    let inverse = VaultMoveBatch.inverse(of: moves)

    #expect(inverse == [
        VaultMove(item: refA, from: "B", to: "A"),
        VaultMove(item: refB, from: "B", to: "C"),
    ])
}

@Test func inverseOfInverseRestoresTheOriginalMoves() {
    let ref = VaultItemRef(path: "A/x.canvas", kind: .board)
    let moves = [VaultMove(item: ref, from: "A", to: "B")]

    #expect(VaultMoveBatch.inverse(of: VaultMoveBatch.inverse(of: moves)) == moves)
}
