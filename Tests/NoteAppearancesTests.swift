import Foundation
import Testing
@testable import Pergamenum

// ADR-0084 §D6 («Dove compare» is asked for, read-only, and read off the files), SPEC R-28, plan
// docs/plans/note-workflow-n3.md Task 1.
//
// `NoteAppearances.build` is the pure join: boards and pratiche arrive as already-read values and
// `candidates` stands for the index's `resolve(title:)`. `NoteAppearancesSessionTests` reads the
// same facts off real files.

private let notePath = "Tecnica/Curva.md"

/// A resolver that knows exactly one reference as exactly one path: `PraticaLinkResolver.note`'s
/// `unique`.
private func resolver(_ table: [String: [String]]) -> (String) -> [String] {
    { table[$0] ?? [] }
}

private func build(
    boards: [(path: String, filePaths: [String])] = [],
    unreadableBoards: Int = 0,
    praticaLinks: [(folder: String, references: [String])] = [],
    messageLinks: [(path: String, folder: String, reference: String)] = [],
    candidates: [String: [String]] = [:]
) -> NoteAppearances {
    NoteAppearances.build(
        notePath: notePath,
        boards: boards,
        unreadableBoards: unreadableBoards,
        praticaLinks: praticaLinks,
        messageLinks: messageLinks,
        candidates: resolver(candidates)
    )
}

// MARK: - Boards

@Test func aBoardAppearsOnceWhenAnyFileNodeIsThisNote() {
    let result = build(boards: [
        (path: "Lavagne/Taratura.canvas", filePaths: ["Altro.md", notePath, notePath]),
    ])

    #expect(result.boards.map(\.path) == ["Lavagne/Taratura.canvas"], "una board compare una volta, anche con due nodi")
}

@Test func aBoardWithOnlyASiblingPathOrAPrefixIsNotAnAppearance() {
    let result = build(boards: [
        (path: "A.canvas", filePaths: ["Tecnica/Curva 2.md", "Altra/Curva.md", "Tecnica/Curva.md.bak"]),
        (path: "B.canvas", filePaths: ["Tecnica/Cur", "Tecnica", "tecnica/curva.md"]),
    ])

    #expect(result.boards.isEmpty, "solo l'uguaglianza esatta del percorso conta")
}

@Test func boardsAreSortedByPath() {
    let result = build(boards: [
        (path: "Z.canvas", filePaths: [notePath]),
        (path: "A/Sotto.canvas", filePaths: [notePath]),
        (path: "M.canvas", filePaths: [notePath]),
    ])

    #expect(result.boards.map(\.path) == ["A/Sotto.canvas", "M.canvas", "Z.canvas"])
}

@Test func theUnreadableBoardCountIsPassedThrough() {
    #expect(build(unreadableBoards: 3).unreadableBoards == 3)
    #expect(build().unreadableBoards == 0)
}

// MARK: - Pratiche

@Test func aPraticaReferenceIsClaimedWhenItResolvesToThisNoteAlone() {
    let result = build(
        praticaLinks: [(folder: "01 Progetti/Rossi/Offerta", references: ["Curva"])],
        candidates: ["Curva": [notePath]]
    )

    #expect(result.pratiche.count == 1)
    #expect(result.pratiche.first?.folder == "01 Progetti/Rossi/Offerta")
    #expect(result.pratiche.first?.title == "Offerta", "il titolo di una pratica è il nome della sua cartella")
    #expect(result.pratiche.first?.linksNote == true)
    #expect(result.pratiche.first?.messages == [])
}

@Test func aReferenceThatResolvesToAnotherNoteIsNotClaimed() {
    let result = build(
        praticaLinks: [(folder: "P/Uno", references: ["Altra"])],
        candidates: ["Altra": ["Tecnica/Altra.md"]]
    )

    #expect(result.pratiche.isEmpty)
}

@Test func anAmbiguousReferenceIsClaimedByNobody() {
    // Two notes called «Curva»: this one is one of them, and still the reference is not its own.
    let result = build(
        praticaLinks: [(folder: "P/Uno", references: ["Curva"])],
        candidates: ["Curva": [notePath, "Archivio/Curva.md"]]
    )

    #expect(result.pratiche.isEmpty)
}

@Test func aReferenceThatResolvesToNothingIsNotClaimed() {
    let result = build(praticaLinks: [(folder: "P/Uno", references: ["Fantasma"])])

    #expect(result.pratiche.isEmpty)
}

@Test func aPraticaWithSeveralReferencesIsOneRowClaimedByTheOneThatIsThisNote() {
    let result = build(
        praticaLinks: [(folder: "P/Uno", references: ["Altra", "Curva", "Ancora"])],
        candidates: ["Altra": ["Altra.md"], "Curva": [notePath], "Ancora": ["Ancora.md"]]
    )

    #expect(result.pratiche.map(\.folder) == ["P/Uno"])
    #expect(result.pratiche.first?.linksNote == true)
}

// MARK: - Messages

@Test func aMessageIsGroupedUnderItsPraticaWhichNeedNotLinkTheNoteItself() {
    let result = build(
        messageLinks: [
            (path: "P/Uno/email/b.md", folder: "P/Uno", reference: "Curva"),
            (path: "P/Uno/email/a.md", folder: "P/Uno", reference: "Curva"),
        ],
        candidates: ["Curva": [notePath]]
    )

    #expect(result.pratiche.count == 1)
    #expect(result.pratiche.first?.folder == "P/Uno")
    #expect(result.pratiche.first?.linksNote == false, "la pratica non linka la nota: solo i suoi messaggi")
    #expect(result.pratiche.first?.messages == ["P/Uno/email/a.md", "P/Uno/email/b.md"])
}

@Test func aMessageAndItsPraticaShareOneRow() {
    let result = build(
        praticaLinks: [(folder: "P/Uno", references: ["Curva"])],
        messageLinks: [(path: "P/Uno/email/a.md", folder: "P/Uno", reference: "Curva")],
        candidates: ["Curva": [notePath]]
    )

    #expect(result.pratiche.count == 1)
    #expect(result.pratiche.first?.linksNote == true)
    #expect(result.pratiche.first?.messages == ["P/Uno/email/a.md"])
}

@Test func anAmbiguousOrForeignMessageReferenceIsNotClaimed() {
    let result = build(
        messageLinks: [
            (path: "P/Uno/email/a.md", folder: "P/Uno", reference: "Gemella"),
            (path: "P/Uno/email/b.md", folder: "P/Uno", reference: "Altra"),
        ],
        candidates: ["Gemella": [notePath, "Archivio/Curva.md"], "Altra": ["Altra.md"]]
    )

    #expect(result.pratiche.isEmpty)
}

@Test func pratichePerFolderAreSortedByFolder() {
    let result = build(
        praticaLinks: [
            (folder: "P/Zeta", references: ["Curva"]),
            (folder: "P/Alfa", references: ["Curva"]),
        ],
        messageLinks: [(path: "P/Medio/email/a.md", folder: "P/Medio", reference: "Curva")],
        candidates: ["Curva": [notePath]]
    )

    #expect(result.pratiche.map(\.folder) == ["P/Alfa", "P/Medio", "P/Zeta"])
}

// MARK: - Nothing

@Test func noBoardsAndNoPraticheIsTheEmptyValue() {
    #expect(build() == .empty)
    #expect(NoteAppearances.empty.boards.isEmpty)
    #expect(NoteAppearances.empty.pratiche.isEmpty)
    #expect(NoteAppearances.empty.unreadableBoards == 0)
}
