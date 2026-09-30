import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0071 (Contenitore) §D10, plan docs/plans/contenitore.md, Task 6 - R-23, R-24. A document is
// linked by its scheda's note id (ADR-0059), so the link survives every pair rename and move; an
// id that names no document opens the pane with nothing selected and says why, once.

private let folder = "Contenitore/Fatture/2026"
private let stem = "20260314 Fattura"
private var scheda: String { "\(folder)/\(stem).md" }

// MARK: - Parsing

@Test func aContenitoreLinkParsesToItsIDAndAMissingIDIsNotARoute() throws {
    let id = UUID().uuidString.lowercased()
    let link = try #require(PergamenumLink.contenitore(id: id))

    #expect(link.absoluteString == "pergamenum://contenitore?id=\(id)")
    #expect(PergamenumRoute(link) == .contenitore(id: id))
    #expect(PergamenumRoute(try #require(URL(string: "pergamenum://contenitore"))) == nil)
    #expect(PergamenumRoute(try #require(URL(string: "pergamenum://contenitore?id="))) == nil)
}

// MARK: - Resolution (R-23)

@MainActor
@Test func aMintedSchedaIDSelectsItsDocumentAfterAPairRenameAndAPairMove() async throws {
    let vault = try TemporaryVault()
    try ContenitoreFixture.seed(stem: stem, in: folder, vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let session = try #require(harness.vault.session)
    let id = try #require(session.mintNoteID(for: scheda))
    let route = PergamenumRoute.contenitore(id: id)

    #expect(await harness.vault.handle(route))
    #expect(harness.vault.routeState.pendingContenitore == .select(scheda))

    #expect(await harness.actions.rename(scheda, to: "20260314 Fattura luce"))
    let renamed = "\(folder)/20260314 Fattura luce.md"
    #expect(session.exists("\(folder)/20260314 Fattura luce.pdf"))
    #expect(await harness.vault.handle(route))
    #expect(harness.vault.routeState.pendingContenitore == .select(renamed))

    let outcome = try await session.moveDocument(at: renamed, toContainer: "Contenitore/Utenze")
    #expect(outcome.newPath == "Contenitore/Utenze/2026/20260314 Fattura luce.md")
    #expect(await harness.vault.handle(route))
    #expect(harness.vault.routeState.pendingContenitore == .select(outcome.newPath))
}

@MainActor
@Test func consumingTheRouteSelectsTheDocumentAndClearsWhatWouldHideIt() async throws {
    let vault = try TemporaryVault()
    try ContenitoreFixture.seed(stem: stem, in: folder, vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let id = try #require(harness.vault.session?.mintNoteID(for: scheda))
    harness.contenitore.scope = .inbox
    harness.contenitore.filter.colours = [.rosso]

    #expect(await harness.vault.handle(.contenitore(id: id)))
    harness.contenitore.consumeRoute()

    #expect(harness.contenitore.selection == scheda)
    #expect(harness.contenitore.scope == .all)
    #expect(!harness.contenitore.filter.isActive)
    #expect(harness.vault.routeState.pendingContenitore == nil, "a link is acted on once")
}

// MARK: - A link that misses (R-24)

@MainActor
@Test func anUnknownIDOpensThePaneWithNothingSelectedAndOneProblem() async throws {
    let vault = try TemporaryVault()
    try ContenitoreFixture.seed(stem: stem, in: folder, vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let before = harness.vault.problems.count

    #expect(!(await harness.vault.handle(.contenitore(id: UUID().uuidString.lowercased()))))

    #expect(harness.vault.routeState.pendingContenitore == ContenitoreRouteTarget.none)
    #expect(harness.vault.problems.count == before + 1)
}

@MainActor
@Test func theIDOfANoteThatIsNotASchedaOpensThePaneWithNothingSelectedAndOneProblem() async throws {
    let vault = try TemporaryVault()
    try vault.write("---\ndate: 2026-09-29\ntags:\n  - type-note\n---\n\nNota.\n", to: "Contenitore/Nota.md")
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let id = try #require(harness.vault.session?.mintNoteID(for: "Contenitore/Nota.md"))
    let before = harness.vault.problems.count

    #expect(!(await harness.vault.handle(.contenitore(id: id))))

    #expect(harness.vault.routeState.pendingContenitore == ContenitoreRouteTarget.none)
    #expect(harness.vault.problems.count == before + 1)
    #expect(harness.vault.problems.last?.contains("Contenitore/Nota.md") == true)
}

// MARK: - «Copia link Pergamenum» (R-23)

@MainActor
@Test func copyLinkMintsOnFirstUseAndReusesTheSameIDAfter() async throws {
    let vault = try TemporaryVault()
    try ContenitoreFixture.seed(stem: stem, in: folder, vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    let session = try #require(harness.vault.session)
    #expect(session.lookUpNote(id: UUID().uuidString.lowercased()) == .unknown)

    #expect(harness.contenitore.copyLink(for: scheda))
    let first = try #require(harness.contenitore.pasteboard.string(forType: .string))
    let id = try #require(session.mintNoteID(for: scheda))
    #expect(first == PergamenumLink.contenitore(id: id)?.absoluteString)

    harness.contenitore.pasteboard.clearContents()
    #expect(harness.contenitore.copyLink(for: scheda))
    #expect(harness.contenitore.pasteboard.string(forType: .string) == first)
}
