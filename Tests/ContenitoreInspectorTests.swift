import Foundation
import Testing
@testable import Pergamenum

// ADR-0071 (Contenitore) §D1, §D7 and §D11, plan docs/plans/contenitore.md, Task 7 - R-16, R-17.
// Every inspector edit is one write through the guarded door with the hash the model read, so a
// scheda another writer touched in between is refused and left as that writer left it.

private let folder = "Contenitore/Fatture/2026"
private let scheda = "\(folder)/20260314 Fattura.md"

@MainActor
private func openSession(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try ContenitoreFixture.seed(stem: "20260314 Fattura", in: folder, vault: vault)
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

// MARK: - Guarded edits (R-16)

@MainActor
@Test func editingTheFourFieldsWritesThemThroughTheGuardedDoorAndKeepsEveryOtherKey() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault)
    var model = try #require(ContenitoreInspectorModel(session: session, schedaPath: scheda))
    let date = try #require(CalendarDate(iso: "2026-03-20"))
    let tags = [ContenitoreFixture.typeNote, ContenitoreFixture.inbox, Tag(namespace: .topic, value: "fatture")]

    let outcome = await model.save(description: "  Bolletta di marzo\n", date: date, colour: .verde, tags: tags)

    #expect(outcome == .saved)
    let text = try ContenitoreFixture.text(scheda, in: vault.root)
    let document = NoteDocument.parse(text)
    #expect(document.body == "\nBolletta di marzo\n")
    #expect(document.frontmatter.date == date)
    #expect(Set(document.frontmatter.tags) == Set(tags))
    let facts = try #require(ContenitoreScheda.facts(in: document.frontmatter.foreignKeys))
    #expect(facts.colour == .verde)
    #expect(facts.fileName == "20260314 Fattura.pdf")
    #expect(facts.sha256 == ContenitoreFixture.hash)
    #expect(facts.originalName == "Scansione.pdf")
    let draft = model.draft
    #expect(draft.description == "Bolletta di marzo")
    #expect(draft.date == date)
    #expect(draft.colour == .verde)
    #expect(Set(draft.tags) == Set(tags))

    let again = await model.save(description: "Bolletta di marzo", date: date, colour: .verde, tags: draft.tags)
    #expect(again == .unchanged)
    #expect(try ContenitoreFixture.text(scheda, in: vault.root) == text)
}

@MainActor
@Test func aSchedaChangedOnDiskAfterTheReadIsRefusedAndLeftAsTheOtherWriterLeftIt() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault)
    var model = try #require(ContenitoreInspectorModel(session: session, schedaPath: scheda))
    let external = try ContenitoreFixture.schedaText(fileName: "20260314 Fattura.pdf", colour: .giallo)
        + "\nScritta da un altro editor.\n"
    try vault.write(external, to: scheda)
    let before = session.problems.count

    let outcome = await model.save(description: "La mia descrizione", date: nil, colour: .rosso, tags: [])

    #expect(outcome == .refused)
    #expect(try ContenitoreFixture.text(scheda, in: vault.root) == external)
    #expect(model.text == external, "the model reloads what is on disk")
    #expect(model.draft.colour == .giallo)
    #expect(session.problems.count == before + 1)
}

// MARK: - Colour and date (R-17)

@Test func colourAcceptsOnlyTheSixNamesAndTakesTheStickyTokens() {
    #expect(ContenitoreColour.allCases.map(\.rawValue) == ["rosso", "arancio", "giallo", "verde", "ciano", "viola"])
    #expect(ContenitoreColour(rawValue: "blu") == nil)
    #expect(ContenitoreColour(rawValue: "") == nil)
    #expect(ContenitoreColour.allCases.map(\.token) == (1...6).map(StickyPreset.token(for:)))
    #expect(ContenitoreColour.allCases.map(\.token)
        == [.stickyPink, .stickyOrange, .stickyYellow, .stickyGreen, .stickyBlue, .stickyPurple])
}

@MainActor
@Test func clearingTheColourRemovesItsKeyAndNothingElse() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault)
    var model = try #require(ContenitoreInspectorModel(session: session, schedaPath: scheda))
    let draft = model.draft
    #expect(await model.save(description: draft.description, date: draft.date, colour: .ciano, tags: draft.tags) == .saved)

    #expect(await model.save(description: draft.description, date: draft.date, colour: nil, tags: draft.tags) == .saved)

    let text = try ContenitoreFixture.text(scheda, in: vault.root)
    #expect(!text.contains(ContenitoreScheda.colourKey + ":"))
    #expect(text == (try ContenitoreFixture.schedaText(fileName: "20260314 Fattura.pdf")))
}

@MainActor
@Test func changingTheDateToAnotherYearDoesNotMoveThePair() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault)
    var model = try #require(ContenitoreInspectorModel(session: session, schedaPath: scheda))
    let draft = model.draft
    let lastYear = try #require(CalendarDate(iso: "2025-12-31"))

    #expect(await model.save(description: draft.description, date: lastYear, colour: nil, tags: draft.tags) == .saved)

    #expect(session.exists(scheda))
    #expect(session.exists("\(folder)/20260314 Fattura.pdf"))
    #expect(!FileManager.default.fileExists(
        atPath: vault.root.appending(path: "Contenitore/Fatture/2025").path(percentEncoded: false)
    ))
    #expect(NoteDocument.parse(try ContenitoreFixture.text(scheda, in: vault.root)).frontmatter.date == lastYear)
}
