import Foundation
import Testing
@testable import Pergamenum

// ADR-0084 §D6 («Dove compare» is read off the files) and ADR-0049 §D4 (a pratica's links are
// read from the file, never from a cache-reused record), SPEC R-28, plan
// docs/plans/note-workflow-n3.md Task 1.
//
// `VaultSession.noteAppearances(of:)` against a temporary vault: boards through `CanvasStore`, the
// pratica's `pergamenum-dossier-links-notes` and a message's `pergamenum-mail-note` through the
// parsers that already read them. App only; nothing here is a connector.

private func note(_ body: String) -> String {
    "---\ndate: 2026-10-07\ntags:\n  - type-note\n---\n\n\(body)\n"
}

private let praticaFolder = "01 Progetti/Rossi/Offerta"

private func praticaNote(linking titles: [String]) -> String {
    let links = titles.isEmpty
        ? ""
        : "pergamenum-dossier-links-notes:\n" + titles.map { "  - \"[[\($0)]]\"\n" }.joined()
    return """
    ---
    pergamenum-dossier: 1
    pergamenum-dossier-counterparts:
      - m.rossi@rossi-spa.it
    \(links)---

    Appunti pratica.

    """
}

private func message(linking title: String?) -> String {
    let link = title.map { "pergamenum-mail-note: \"[[\($0)]]\"\n" } ?? ""
    return """
    ---
    date: 2026-06-10
    tags:
      - type-note
      - type-email
    pergamenum-mail: 1
    pergamenum-mail-message-id: "<abc@rossi-spa.it>"
    pergamenum-mail-direction: received
    pergamenum-mail-date: 2026-06-10T14:06:00+02:00
    pergamenum-mail-from: "Mario Rossi <m.rossi@rossi-spa.it>"
    pergamenum-mail-subject: "Richiesta offerta"
    pergamenum-mail-body: complete
    \(link)---

    Buongiorno,
    """
}

private func board(withFilesAt paths: [String]) -> String {
    let nodes = paths.enumerated().map { index, path in
        "{\"id\":\"n\(index)\",\"type\":\"file\",\"file\":\"\(path)\",\"x\":0,\"y\":0,\"width\":260,\"height\":180}"
    }
    return "{\"nodes\":[\(nodes.joined(separator: ","))],\"edges\":[]}"
}

/// The note under test, its board, a board that is not JSON, a board with a sibling only, a
/// pratica that lists the note and a message that names it.
@MainActor
private func vaultWithAppearances(_ vault: borrowing TemporaryVault) throws {
    try vault.write(note("Corpo."), to: "Tecnica/Curva.md")
    try vault.write(note("Sorella."), to: "Tecnica/Curva 2.md")
    try vault.write(board(withFilesAt: ["Tecnica/Curva.md", "Tecnica/Curva.md"]), to: "Lavagne/Taratura.canvas")
    try vault.write(board(withFilesAt: ["Tecnica/Curva 2.md", "Tecnica"]), to: "Lavagne/Sorella.canvas")
    try vault.write("questo non è JSON {", to: "Lavagne/Rotta.canvas")
    try vault.write(praticaNote(linking: ["Curva"]), to: "\(praticaFolder)/pratica.md")
    try vault.write(message(linking: "Curva"), to: "\(praticaFolder)/email/msg.md")
}

@MainActor
private func openSession(_ vault: borrowing TemporaryVault) async -> VaultSession {
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

@MainActor
@Test func theBoardsAndPraticheThatPointAtTheNoteAreReadOffTheFiles() async throws {
    let vault = try TemporaryVault()
    try vaultWithAppearances(vault)
    let session = await openSession(vault)

    let appearances = session.noteAppearances(of: "Tecnica/Curva.md")

    #expect(
        appearances.boards.map(\.path) == ["Lavagne/Taratura.canvas"],
        "la board con un nodo-file su questa nota, una volta"
    )
    #expect(appearances.unreadableBoards == 1, "la board che non è JSON è contata, non è un errore")
    #expect(appearances.pratiche.map(\.folder) == [praticaFolder])
    let pratica = try #require(appearances.pratiche.first)
    #expect(pratica.title == "Offerta")
    #expect(pratica.linksNote, "pratica.md elenca la nota in pergamenum-dossier-links-notes")
    #expect(pratica.messages == ["\(praticaFolder)/email/msg.md"], "il messaggio che nomina la nota")
}

@MainActor
@Test func aNoteNobodyPointsAtAppearsNowhereButStillCountsTheBrokenBoard() async throws {
    let vault = try TemporaryVault()
    try vaultWithAppearances(vault)
    try vault.write(note("Isolata."), to: "Isolata.md")
    let session = await openSession(vault)

    let appearances = session.noteAppearances(of: "Isolata.md")

    #expect(appearances.boards.isEmpty)
    #expect(appearances.pratiche.isEmpty)
    #expect(appearances.unreadableBoards == 1)
}

@MainActor
@Test func theSiblingNoteIsNotClaimedByAPathPrefix() async throws {
    let vault = try TemporaryVault()
    try vaultWithAppearances(vault)
    let session = await openSession(vault)

    let appearances = session.noteAppearances(of: "Tecnica/Curva 2.md")

    #expect(appearances.boards.map(\.path) == ["Lavagne/Sorella.canvas"])
    #expect(appearances.pratiche.isEmpty, "i riferimenti «Curva» non sono «Curva 2»")
}

@MainActor
@Test func aSecondNoteOfTheSameTitleMakesTheReferencesAmbiguousAndClaimedByNeither() async throws {
    let vault = try TemporaryVault()
    try vaultWithAppearances(vault)
    try vault.write(note("Gemella in un'altra cartella."), to: "Archivio/Curva.md")
    let session = await openSession(vault)

    let mine = session.noteAppearances(of: "Tecnica/Curva.md")
    let twin = session.noteAppearances(of: "Archivio/Curva.md")

    #expect(mine.pratiche.isEmpty, "«[[Curva]]» ora è ambiguo: nessuna delle due note lo rivendica")
    #expect(twin.pratiche.isEmpty)
    // A board node names a path, so it is never ambiguous.
    #expect(mine.boards.map(\.path) == ["Lavagne/Taratura.canvas"])
    #expect(twin.boards.isEmpty)
}

@MainActor
@Test func aMessageIsReadOffItsFileEvenWhenThePraticaLinksNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(note("Corpo."), to: "Tecnica/Curva.md")
    try vault.write(praticaNote(linking: []), to: "\(praticaFolder)/pratica.md")
    try vault.write(message(linking: "Curva"), to: "\(praticaFolder)/email/msg.md")
    try vault.write(message(linking: nil), to: "\(praticaFolder)/email/altro.md")
    let session = await openSession(vault)

    let pratica = try #require(session.noteAppearances(of: "Tecnica/Curva.md").pratiche.first)

    #expect(!pratica.linksNote)
    #expect(pratica.messages == ["\(praticaFolder)/email/msg.md"], "solo il messaggio che nomina la nota")
}

/// ADR-0049 §D4: a record reused from the cache has no foreign keys. A second launch over the
/// same state directory reuses every record, and the appearances still come out right because
/// they are read off the files.
@MainActor
@Test func aCacheReusedRecordGivesTheSameAppearances() async throws {
    let vault = try TemporaryVault()
    try vaultWithAppearances(vault)
    let first = await openSession(vault)
    let expected = first.noteAppearances(of: "Tecnica/Curva.md")
    try #require(expected.pratiche.count == 1)

    let relaunched = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await relaunched.rescan()
    await relaunched.rescan()
    try #require(relaunched.index.reusedFromCache > 0, "il secondo avvio deve riusare la cache")

    #expect(relaunched.noteAppearances(of: "Tecnica/Curva.md") == expected)
}
