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
