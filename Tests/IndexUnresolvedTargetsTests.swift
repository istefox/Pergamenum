import Foundation
import Testing
@testable import Pergamenum

// ADR-0084 §D2 (the inspector's unresolved links are the open note's own), SPEC R-25, plan
// docs/plans/note-workflow-n3.md Task 1.
//
// One derivation, three callers: `IndexSnapshot.unresolvedTargets(of:)` (new), `VaultAPI.links`
// (the connector read, unchanged JSON) and the query field `unresolved` (`ViewField.unresolved`
// through `ViewEvaluator`). The three-way test runs all of them over one vault and demands one
// answer for every note, the shape of the drift that wrote this derivation out three times.

private func note(_ body: String) -> String {
    "---\ndate: 2026-10-07\ntags:\n  - type-note\n---\n\n\(body)\n"
}

/// A vault with every shape the derivation has to keep apart.
@MainActor
private func corpusSession(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(note("Corpo."), to: "B.md")
    // Two notes called Gemello: a link to it is ambiguous, not dangling.
    try vault.write(note("Prima."), to: "X/Gemello.md")
    try vault.write(note("Seconda."), to: "Y/Gemello.md")
    try vault.write(
        note("Link: [[B]] [[Ghost]] [[ghost]] [[Fantasma]] [[Ghost]] [[Gemello]] e ancora [[b]]."),
        to: "A.md"
    )
    try vault.write(note("Nessun link."), to: "C.md")
    try vault.write(
        note("```\n[[NelCodice]]\n```\nE `[[Inline]]`, la board [[Q4.canvas]] e ![[foto.png]] non contano. [[Reale]]."),
        to: "D.md"
    )
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

@MainActor
@Test func theUnresolvedTargetsOfOneNoteAreItsDanglingLinksInLinkTargetsOrder() async throws {
    let vault = try TemporaryVault()
    let session = try await corpusSession(vault)

    // `[[Ghost]]` and `[[ghost]]` are two spellings kept as given; `[[B]]`/`[[b]]` resolve;
    // `[[Gemello]]` is ambiguous and so resolved.
    #expect(session.index.unresolvedTargets(of: "A.md") == ["Ghost", "ghost", "Fantasma"])
    #expect(session.index.unresolvedTargets(of: "D.md") == ["Reale"], "codice, board e file non sono link a note")
    #expect(session.index.unresolvedTargets(of: "C.md").isEmpty)
    #expect(session.index.unresolvedTargets(of: "B.md").isEmpty)
}

@MainActor
@Test func aPathTheIndexDoesNotKnowHasNoUnresolvedTargets() async throws {
    let vault = try TemporaryVault()
    let session = try await corpusSession(vault)

    #expect(session.index.unresolvedTargets(of: "Assente.md").isEmpty)
}

@MainActor
@Test func theSnapshotTheConnectorAndTheQueryFieldGiveOneListForEveryNote() async throws {
    let vault = try TemporaryVault()
    let session = try await corpusSession(vault)
    let block = try ViewBlock.parse("render: table\ncolumns: [title, unresolved]")
    let result = ViewEvaluator.evaluate(block, over: session.index) { candidate in
        try? session.read(candidate.relativePath).text
    }
    let paths = session.index.allNotes.map(\.relativePath)
    try #require(paths.count == 6)
    try #require(result.rows.count == 6)

    for path in paths {
        let snapshot = session.index.unresolvedTargets(of: path)
        let connector = try VaultAPI.links(session, at: path).unresolved
        let row = try #require(result.rows.first { $0.path == path })
        guard case .list(let field)? = row.values[.unresolved] else {
            Issue.record("\(path): il campo unresolved non è una lista")
            continue
        }

        #expect(snapshot == connector, "\(path): indice e connettore devono dare la stessa lista")
        #expect(snapshot == field, "\(path): indice e campo di query devono dare la stessa lista")
    }

    // Not vacuous: the corpus does hold dangling links for the three to agree on.
    #expect(paths.contains { !session.index.unresolvedTargets(of: $0).isEmpty })
}
