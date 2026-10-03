import Foundation
import Testing
@testable import Pergamenum

// PG-378: `RelatedSection.parse` reads the bullets «Collega» and «Scollega» read, through the one
// line-role walk: a `-` line in a fence, indented four columns or more, or nested under a bullet
// is not a structural link.

private typealias Fixture = RelatedSectionFixture

@Test func aFencedLinkLineIsNotALinkSoCollegaTowardsItWrites() throws {
    let section = "## Note correlate\n\n- [[A]] — a\n\n```\n- [[B]] — b\n```\n"
    let text = Fixture.note(related: ["[[A]]"], section)
    #expect(RelatedSection.parse(from: NoteDocument.parse(text).body).map(\.target) == ["A"])

    let linked = try RelatedLink.add(target: "B", reason: "motivo", to: text, selfTitle: "Nota")

    #expect(linked.hasSuffix("## Note correlate\n\n- [[A]] — a\n- [[B]] — motivo\n\n```\n- [[B]] — b\n```\n"))
    let document = NoteDocument.parse(linked)
    #expect(document.frontmatter.related.contains { $0.contains("[[B]]") })
    let discrepancies = RelatedSection.discrepancies(
        frontmatterRelated: document.frontmatter.related,
        sectionLinks: RelatedSection.parse(from: document.body)
    )
    #expect(discrepancies.missingInSection.isEmpty)
    #expect(discrepancies.missingInFrontmatter.isEmpty)
}

// Pins the in-memory entry point, `violations(path:title:text:)` (the open note's buffer); the
// on-disk vault-wide one is `vaultWideLintOfAFileWithAFencedLinkLineReportsNoDiscrepancy`.
@MainActor
@Test func theLinterInventsNoDiscrepancyFromAFencedLinkLine() throws {
    let vault = try TemporaryVault()
    let session = VaultSession(
        root: vault.root, stateBase: vault.stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    let text = Fixture.note(related: ["[[A]]"], "## Note correlate\n\n- [[A]] — a\n\n```\n- [[B]] — b\n```\n")

    let violations = session.violations(path: "Nota.md", title: "Nota", text: text)

    #expect(violations.relatedMissingInSection.isEmpty)
    #expect(violations.relatedMissingInFrontmatter.isEmpty)
}

@Test(arguments: ["    ", "\t", "  \t", "     "])
func aLineIndentedFourColumnsOrMoreIsNotALink(indent: String) {
    #expect(RelatedSection.parse(from: "## Note correlate\n\n\(indent)- [[B]] — b\n").isEmpty)
}

@Test func aNestedSubItemIsNotALink() {
    let body = "## Note correlate\n\n- [[A]] — a\n  - [[B]] — dettaglio\n   - [[C]] — dettaglio\n- [[D]] — d\n"
    #expect(RelatedSection.parse(from: body).map(\.target) == ["A", "D"])
}

@Test func nestedSubItemsDoNotCountTowardsTheLinkLimit() throws {
    // Four links, each with a sub-item that links too: eight to the old reading, past W-09's five.
    let bullets = ["A", "B", "C", "D"].map { "- [[\($0)]] — \($0)\n  - [[\($0) dettaglio]] — d\n" }.joined()
    let text = Fixture.note(related: ["[[A]]", "[[B]]", "[[C]]", "[[D]]"], "## Note correlate\n\n" + bullets)

    let linked = try RelatedLink.add(target: "E", reason: "e", to: text, selfTitle: "Nota")

    #expect(linked.hasSuffix(bullets + "- [[E]] — e\n"))
    #expect(RelatedSection.parse(from: NoteDocument.parse(linked).body).map(\.target) == ["A", "B", "C", "D", "E"])
}

@Test func aBulletIndentedByOneToThreeColumnsIsStillALink() {
    for indent in [" ", "  ", "   "] {
        #expect(RelatedSection.parse(from: "## Note correlate\n\n\(indent)- [[A]] — a\n").map(\.target) == ["A"])
    }
    // One column past the bullet above is a sibling, not a sub-item.
    #expect(RelatedSection.parse(from: "## Note correlate\n\n- [[A]] — a\n - [[B]] — b\n").map(\.target) == ["A", "B"])
}

@Test(arguments: ["\n", "\r\n"])
func theReasonIsReadAfterAnyOfTheFourSeparators(nl: String) {
    let body = [
        "## Note correlate", "", "- [[A]] — uno", "- [[B]] – due", "- [[C]] - tre", "- [[D]]: quattro",
        "- [[E|alias]] —  cinque  ", "- [[F]]",
    ].joined(separator: nl) + nl
    #expect(RelatedSection.parse(from: body) == [
        StructuralLink(target: "A", reason: "uno"),
        StructuralLink(target: "B", reason: "due"),
        StructuralLink(target: "C", reason: "tre"),
        StructuralLink(target: "D", reason: "quattro"),
        StructuralLink(target: "E", reason: "cinque"),
        StructuralLink(target: "F", reason: ""),
    ])
}

// PG-378, the cases the first pass left open: CRLF and unterminated fences, a continuation's own
// `-` line, «Scollega» beside a fence, the limit's boundary, and the two session doors (search's
// vault-wide lint and the connectors' `addStructuralLink`).

@Test func aFencedLinkLineInACRLFSectionIsNotALinkAndCollegaKeepsCRLF() throws {
    let text = "---\r\ndate: 2026-09-26\r\ntags:\r\n  - type-note\r\nrelated:\r\n  - \"[[A]]\"\r\n---\r\n"
        + "## Note correlate\r\n\r\n- [[A]] — a\r\n\r\n```\r\n- [[B]] — b\r\n```\r\n"
    #expect(RelatedSection.parse(from: NoteDocument.parse(text).body).map(\.target) == ["A"])

    let linked = try RelatedLink.add(target: "B", reason: "motivo", to: text, selfTitle: "Nota")

    #expect(Fixture.isAllCRLF(linked))
    #expect(linked.hasSuffix(
        "## Note correlate\r\n\r\n- [[A]] — a\r\n- [[B]] — motivo\r\n\r\n```\r\n- [[B]] — b\r\n```\r\n"
    ))
    #expect(linked.contains("related:\r\n  - \"[[A]]\"\r\n  - \"[[B]]\"\r\n"))
}

@Test func anUnterminatedFenceRunsToTheSectionEndAndHidesItsLinkLines() throws {
    let section = "## Note correlate\n\n- [[A]] — a\n\n```\n- [[B]] — b\n- [[C]] — c\n"
    #expect(RelatedSection.parse(from: section).map(\.target) == ["A"])

    let linked = try RelatedLink.add(
        target: "B", reason: "motivo", to: Fixture.note(related: ["[[A]]"], section), selfTitle: "Nota"
    )

    #expect(linked.hasSuffix("- [[A]] — a\n- [[B]] — motivo\n\n```\n- [[B]] — b\n- [[C]] — c\n"))
}

@Test func aDashLineUnderALinkBulletIsPartOfItAndNotALink() {
    let body = "## Note correlate\n\n- [[A]] — a\n  riga a capo\n  - [[X]] — sotto\n"
        + "    - [[Y]] — ancora sotto\n- [[B]] — b\n"
    #expect(RelatedSection.parse(from: body).map(\.target) == ["A", "B"])
}

@Test func unlinkingABulletTakesItsNestedLinkLineAndKeepsTheSibling() {
    let section = "## Note correlate\n\n- [[A]] — a\n  - [[X]] — sotto\n- [[B]] — b\n"
    let unlinked = RelatedLink.remove(target: "A", from: Fixture.note(related: ["[[A]]", "[[B]]"], section))
    #expect(unlinked.hasSuffix("## Note correlate\n\n- [[B]] — b\n"))
}

@Test func unlinkOfATitleOnlyInAFenceLeavesTheFenceIntact() {
    let section = "## Note correlate\n\n- [[A]] — a\n\n```\n- [[B]] — b\n```\n"
    let text = Fixture.note(related: ["[[A]]", "[[B]]"], section)

    let unlinked = RelatedLink.remove(target: "B", from: text)

    #expect(unlinked.hasSuffix(section))
    #expect(!NoteDocument.parse(unlinked).frontmatter.related.contains { $0.contains("[[B]]") })
}

@Test func theLinkLimitCountsOnlyRealBulletsAtItsBoundary() throws {
    let fenced = "\n```\n- [[F1]]\n- [[F2]]\n- [[F3]]\n```\n"
    let four = ["A", "B", "C", "D"].map { "- [[\($0)]] — x\n" }.joined()
    let fiveTitles = ["A", "B", "C", "D", "E"]
    // Four real links plus three fenced ones: a fifth is still allowed.
    let ok = Fixture.note(related: ["[[A]]", "[[B]]", "[[C]]", "[[D]]"], "## Note correlate\n\n" + four + fenced)
    let linked = try RelatedLink.add(target: "E", reason: "e", to: ok, selfTitle: "Nota")
    #expect(RelatedSection.parse(from: NoteDocument.parse(linked).body).map(\.target) == fiveTitles)

    // Five real links: a sixth is refused, and the count in the error is the real one plus one -
    // six, not the nine a reading that counted the three fenced lines would report.
    let five = fiveTitles.map { "- [[\($0)]] — x\n" }.joined()
    let full = Fixture.note(related: fiveTitles.map { "[[\($0)]]" }, "## Note correlate\n\n" + five + fenced)
    #expect {
        try RelatedLink.add(target: "G", reason: "g", to: full, selfTitle: "Nota")
    } throws: { error in
        guard case RelatedLink.Error.tooManyLinks(let count) = error else { return false }
        return count == 6
    }
}

// Pins the on-disk vault-wide entry point, `violations(forRecordAt:)` (the file as written); the
// in-memory one is `theLinterInventsNoDiscrepancyFromAFencedLinkLine`.
@MainActor
@Test func vaultWideLintOfAFileWithAFencedLinkLineReportsNoDiscrepancy() throws {
    let vault = try TemporaryVault()
    try vault.write(
        Fixture.note(related: ["[[A]]"], "## Note correlate\n\n- [[A]] — a\n\n```\n- [[B]] — b\n```\n"),
        to: "Nota.md"
    )
    let session = VaultSession(
        root: vault.root, stateBase: vault.stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )

    let violations = try #require(session.violations(forRecordAt: "Nota.md"))

    #expect(violations.relatedMissingInSection.isEmpty)
    #expect(violations.relatedMissingInFrontmatter.isEmpty)
}

@MainActor
@Test func addStructuralLinkWritesBothNotesWhenTheSourceFencesALinkToTheTarget() async throws {
    let vault = try TemporaryVault()
    try vault.write(
        Fixture.note(related: ["[[A]]"], "## Note correlate\n\n- [[A]] — a\n\n```\n- [[Destinazione]] — finto\n```\n"),
        to: "Origine.md"
    )
    try vault.write(Fixture.note("Corpo."), to: "Destinazione.md")
    try vault.write(Fixture.note("Corpo."), to: "A.md")
    let session = VaultSession(
        root: vault.root, stateBase: vault.stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    await session.rescan()

    let outcome = await session.addStructuralLink(
        from: "Origine.md", to: "Destinazione", reason: "usa i dati", reverseReason: "fornisce i dati"
    )

    #expect(outcome.created)
    #expect(outcome.written.count == 2)
    #expect(session.problems.isEmpty)
    let source = try session.read("Origine.md").text
    let target = try session.read("Destinazione.md").text
    #expect(source.contains("- [[Destinazione]] — usa i dati\n"))
    #expect(source.hasSuffix("```\n- [[Destinazione]] — finto\n```\n"))
    #expect(target.contains("- [[Origine]] — fornisce i dati"))
    #expect(NoteDocument.parse(source).frontmatter.related.contains { $0.contains("[[Destinazione]]") })
    let lint = session.violations(path: "Origine.md", title: "Origine", text: source)
    #expect(lint.relatedMissingInSection.isEmpty)
    #expect(lint.relatedMissingInFrontmatter.isEmpty)
}
