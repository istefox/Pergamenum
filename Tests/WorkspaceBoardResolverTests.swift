import Testing
@testable import Pergamenum

// PG-038: the file-name comparison `IndexSnapshot.tasks(assignedToWorkspace:)` and
// `WorkspacePicker.row` each implemented independently. These tests are the contract the
// shared `WorkspaceBoardResolver` replaces both with.

@Test func resolveFindsTheUniqueBoardMatchingTheFileName() {
    let resolution = WorkspaceBoardResolver.resolve(
        "vibrofer-emea.canvas", in: ["02 Clienti/Vibrofer/vibrofer-emea.canvas", "Altro/board.canvas"]
    )

    #expect(resolution == .unique("02 Clienti/Vibrofer/vibrofer-emea.canvas"))
}

@Test func resolveMatchesCaseInsensitively() {
    let resolution = WorkspaceBoardResolver.resolve(
        "Board.CANVAS", in: ["Cartella/board.canvas"]
    )

    #expect(resolution == .unique("Cartella/board.canvas"))
}

@Test func resolveIsAmbiguousWhenTwoBoardsShareTheFileName() {
    let resolution = WorkspaceBoardResolver.resolve(
        "board.canvas", in: ["Alfa/board.canvas", "Beta/board.canvas"]
    )

    #expect(resolution == .ambiguous)
}

@Test func resolveIsNotFoundWhenNoBoardMatches() {
    let resolution = WorkspaceBoardResolver.resolve("sparita.canvas", in: ["Alfa/board.canvas"])

    #expect(resolution == .notFound)
}

@Test func resolveIsNotFoundForANilWorkspacePath() {
    let resolution = WorkspaceBoardResolver.resolve(nil, in: ["Alfa/board.canvas"])

    #expect(resolution == .notFound)
}

@Test func matchesIsFalseForAPlainMentionWithADifferentName() {
    #expect(!WorkspaceBoardResolver.matches("Alfa/board.canvas", workspacePath: "altro.canvas"))
}

// ADR-0025 §D5: "which board does this folder mean" shares `WorkspaceBoardResolution` with
// "which board does this marker name" above - one enum, two questions. `board(inFolder:among:)`
// is the resolver the breadcrumb, a folder card's double click, and the editor hand-off all call
// instead of guessing at a folder-derived board (ADR-0025 §D1 deletes that derivation outright).
// Plan docs/superpowers/plans/2026-08-27-workspace-folder-board-separation.md, Task 4.

@Test func boardInFolderFindsTheUniqueBoardInThatFolder() {
    let resolution = WorkspaceBoardResolver.board(inFolder: "A", among: ["A/x.canvas"])

    #expect(resolution == .unique("A/x.canvas"))
}

@Test func boardInFolderIsAmbiguousWhenTwoBoardsShareTheFolder() {
    let resolution = WorkspaceBoardResolver.board(
        inFolder: "A", among: ["A/x.canvas", "A/y.canvas"]
    )

    #expect(resolution == .ambiguous)
}

@Test func boardInFolderIsNotFoundForABoardInASubfolder() {
    // A board one level deeper is not this folder's board - the match is on
    // `deletingLastPathComponent`, never `hasPrefix`.
    let resolution = WorkspaceBoardResolver.board(inFolder: "A", among: ["A/b/x.canvas"])

    #expect(resolution == .notFound)
}

@Test func boardInFolderTreatsTheVaultRootAsAnOrdinaryFolder() {
    let resolution = WorkspaceBoardResolver.board(
        inFolder: "", among: ["Pergamena.canvas", "A/x.canvas"]
    )

    #expect(resolution == .unique("Pergamena.canvas"))
}

@Test func boardInFolderIsNotFoundWhenTheFolderHasNoBoards() {
    let resolution = WorkspaceBoardResolver.board(inFolder: "A", among: [])

    #expect(resolution == .notFound)
}
