import Foundation
import Testing
@testable import Pergamenum

// ADR-0083 §D5 (several matches are a choice, never a guess) and §D6 (a dangling link offers to
// create its note), SPEC R-22 and R-23, plan docs/plans/note-workflow-n3.md Task 1.
//
// `LinkDestination.resolve` is the one place a link target becomes a destination: the index's
// answer for a title and the board resolver's answer for a `.canvas` name arrive as inputs, so
// nothing here needs a vault.

private func resolve(
    _ target: String,
    notes: [String: [String]] = [:],
    boards: [String: String] = [:]
) -> LinkDestination {
    LinkDestination.resolve(
        target,
        notePaths: { notes[$0] ?? [] },
        board: { boards[$0] }
    )
}

// MARK: - A title is one note, several, or none

@Test func aTitleWithOneNoteIsThatNote() {
    let destination = resolve("Curva", notes: ["Curva": ["Tecnica/Curva.md"]])

    #expect(destination == .note(path: "Tecnica/Curva.md"))
}

@Test func aTitleWithTwoNotesIsAmbiguousAndKeepsThePathsInTheOrderTheIndexGave() {
    // The order is `resolve(title:)`'s: the choice shows what the index said, not a re-sort.
    let destination = resolve("Curva", notes: ["Curva": ["Z/Curva.md", "A/Curva.md"]])

    #expect(destination == .ambiguous(title: "Curva", paths: ["Z/Curva.md", "A/Curva.md"]))
}

@Test func aTitleWithNoNoteIsMissingAndCreatableWhenItIsAValidTitle() {
    #expect(resolve("Bozza") == .missing(title: "Bozza", creatable: true))
}

@Test func aMissingTitleThatCannotBeANoteNameIsMissingAndNotCreatable() {
    // PG-356: `[[TRUST.md]]` names a path, not a title, and keeps the «nota non trovata» sentence.
    #expect(resolve("TRUST.md") == .missing(title: "TRUST.md", creatable: false))
}

// MARK: - isCreatable

@Test func aValidTitleIsCreatable() {
    #expect(LinkDestination.isCreatable("Bozza"), "una nota con un titolo valido si può creare")
}

@Test(arguments: [
    ("TRUST.md", "un nome di file con .md è un percorso, non un titolo"),
    ("Cartella/Nota", "la barra è vietata in un titolo"),
    ("a:b", "i due punti sono vietati in un titolo"),
    ("X.canvas", ".canvas è una board, non una nota"),
    ("", "un titolo vuoto non si crea"),
    (String(repeating: "a", count: 61), "61 caratteri superano il massimo"),
])
func aTitleThatCannotNameANoteIsNotCreatable(title: String, why: String) {
    #expect(!LinkDestination.isCreatable(title), Comment(rawValue: why))
}

// MARK: - A .canvas target is a board

@Test func aCanvasTargetIsABoardWhenTheBoardResolverAnswersAPath() {
    var asked: [String] = []
    let destination = LinkDestination.resolve(
        "Q4.canvas",
        notePaths: { _ in
            Issue.record("un target .canvas non si chiede all'indice delle note")
            return []
        },
        board: { name in
            asked.append(name)
            return "Progetti/Q4.canvas"
        }
    )

    #expect(destination == .board(path: "Progetti/Q4.canvas"))
    #expect(asked == ["Q4.canvas"], "il risolutore di board riceve il target come scritto")
}

@Test func aCanvasTargetNoBoardAnswersIsAMissingBoardNamedAsWritten() {
    #expect(resolve("Q4.canvas") == .missingBoard(name: "Q4.canvas"))
}

@Test func aNoteTargetNeverAsksTheBoardResolver() {
    _ = LinkDestination.resolve(
        "Curva",
        notePaths: { _ in ["Curva.md"] },
        board: { _ in
            Issue.record("un target di nota non si chiede al risolutore delle board")
            return nil
        }
    )
}
