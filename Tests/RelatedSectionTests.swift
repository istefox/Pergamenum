import Foundation
import Testing
@testable import Pergamenum

// ADR-0065 §D9.3, plan docs/plans/format-edge-hardening.md, Task 6 - R-18, R-01, G1.4.
//
// One locator for `## Note correlate`, shared by the linter (`RelatedSection.parse`), the export
// (`NoteExport`) and «Collega» (`RelatedLink`): the heading is a whole line, a CRLF note is read
// as lines, and «Collega» writes in the note's own line break.

private func note(related: [String] = [], _ body: String) -> String {
    let relatedBlock = related.isEmpty ? "" : "related:\n" + related.map { "  - \"\($0)\"\n" }.joined()
    return "---\ndate: 2026-09-26\ntags:\n  - type-note\n  - topic-vibration-isolation\n\(relatedBlock)---\n\n\(body)"
}

/// Every line break in `text` is CRLF, and `text` ends in one.
private func isAllCRLF(_ text: String) -> Bool {
    let lines = text.components(separatedBy: "\n")
    return lines.last == "" && lines.dropLast().allSatisfy { $0.hasSuffix("\r") }
}

@Test func theExactHeadingIsFound() {
    let links = RelatedSection.parse(from: "# T\n\n## Note correlate\n\n- [[A]] — motivo\n")
    #expect(links == [StructuralLink(target: "A", reason: "motivo")])
}

@Test func aSubHeadingIsNotTheSection() {
    let body = "# T\n\n### Note correlate operative\n\n- [[A]] — motivo\n"
    #expect(RelatedSection.parse(from: body).isEmpty)
    #expect(NoteExport.markdown(from: body).contains("### Note correlate operative"))
    #expect(NoteExport.markdown(from: body).contains("- [[A]] — motivo"))
}

@Test func aMidSentenceMentionIsNotTheSection() {
    #expect(RelatedSection.parse(from: "Vedi ## Note correlate sotto\n\n- [[A]] — motivo\n").isEmpty)
}

@Test func trailingSpacesAndCRAreTolerated() {
    let links = RelatedSection.parse(from: "## Note correlate  \r\n\r\n- [[A]] — r\r\n")
    #expect(links == [StructuralLink(target: "A", reason: "r")])
}

@MainActor
@Test func theLinterInventsNoDiscrepancyFromASubHeading() throws {
    let vault = try TemporaryVault()
    let session = VaultSession(
        root: vault.root, stateBase: vault.stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    let text = note(related: ["[[A]]"], "### Note correlate operative\n\n- [[B]] — motivo\n")

    let violations = session.violations(path: "Nota.md", title: "Nota", text: text)

    #expect(violations.relatedMissingInSection == ["A"])
    #expect(violations.relatedMissingInFrontmatter.isEmpty)
}

/// PG-349: once every `NoteViolations` field defaults to empty, the compiler no longer makes the
/// linter fill this axis. The other six are pinned end to end in `VaultTests.swift`,
/// `theLinterInventsNoDiscrepancyFromASubHeading`, `TaskMarkerLintTests.swift` and
/// `CategoryLintTests.swift`.
@MainActor
@Test func theLinterReportsASectionLinkMissingFromRelated() throws {
    let vault = try TemporaryVault()
    let session = VaultSession(
        root: vault.root, stateBase: vault.stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    let text = note(related: ["[[A]]"], "## Note correlate\n\n- [[A]] — motivo\n- [[B]] — motivo\n")

    let violations = session.violations(path: "Nota.md", title: "Nota", text: text)

    #expect(violations.relatedMissingInFrontmatter == ["B"])
    #expect(violations.relatedMissingInSection.isEmpty)
}

@Test func exportOfACRLFNoteStopsAtTheNextHeading() {
    let text = "---\r\ndate: 2026-09-26\r\ntags:\r\n  - type-note\r\n---\r\n# T\r\n\r\n"
        + "## Note correlate\r\n\r\n- [[A]] — r\r\n\r\n## Altro\r\n\r\nTesto.\r\n"
    let exported = NoteExport.markdown(from: text)
    #expect(exported.contains("## Altro"))
    #expect(exported.contains("Testo."))
    #expect(!exported.contains("Note correlate"))
}

@Test func collegaWritesUnderTheExactHeadingOnly() throws {
    let subSection = "### Note correlate operative\n\n- [[B]] — interno\n"
    let text = note("# Nota\n\n" + subSection)

    let linked = try RelatedLink.add(target: "A", reason: "motivo", to: text, selfTitle: "Nota")

    #expect(linked.contains(subSection + "\n## Note correlate\n\n- [[A]] — motivo\n"))
    #expect(RelatedSection.parse(from: NoteDocument.parse(linked).body)
        == [StructuralLink(target: "A", reason: "motivo")])
}

@Test func collegaOnACRLFNoteKeepsCRLF() throws {
    let linked = try RelatedLink.add(
        target: "A", reason: "motivo", to: FormatEdgeCorpus.crlfWithFrontmatter.text, selfTitle: "Titolo"
    )
    #expect(isAllCRLF(linked))
    #expect(linked.components(separatedBy: "\n").filter { $0 == "---\r" }.count == 2)
    #expect(linked.contains("## Note correlate\r\n\r\n- [[A]] — motivo\r\n"))
    #expect(linked.contains("related:\r\n  - \"[[A]]\"\r\n"))
}

@Test func unlinkOnACRLFNoteKeepsCRLF() throws {
    let linked = try RelatedLink.add(
        target: "A", reason: "motivo", to: FormatEdgeCorpus.crlfWithFrontmatter.text, selfTitle: "Titolo"
    )
    let unlinked = RelatedLink.remove(target: "A", from: linked)
    #expect(isAllCRLF(unlinked))
    #expect(unlinked.components(separatedBy: "\n").filter { $0 == "---\r" }.count == 2)
    #expect(!unlinked.contains("[[A]]"))
}

// PG-278: the heading is found only outside fenced code.

@Test(arguments: [
    "# T\n\n```markdown\n## Note correlate\n\n- [[A]] — motivo\n```\n",
    "# T\n\n~~~\n## Note correlate\n\n- [[A]] — motivo\n~~~\n",
    "# T\r\n\r\n```\r\n## Note correlate\r\n\r\n- [[A]] — motivo\r\n```\r\n",
])
func aHeadingInsideAFenceIsNotTheSection(body: String) {
    #expect(RelatedSection.sectionRange(in: body) == nil)
    #expect(RelatedSection.parse(from: body).isEmpty)
    #expect(NoteExport.markdown(from: body).contains("## Note correlate"))
}

@Test func theRealHeadingAfterAFencedOneIsFound() {
    let body = "# T\n\n```\n## Note correlate\n- [[X]] — finto\n```\n\n## Note correlate\n\n- [[A]] — motivo\n"
    #expect(RelatedSection.parse(from: body) == [StructuralLink(target: "A", reason: "motivo")])
}

@Test func aFencedHashLineDoesNotEndTheSection() {
    let body = "## Note correlate\r\n\r\n- [[A]] — r\r\n\r\n"
        + "```sh\r\n# commento\r\n```\r\n\r\n- [[B]] — s\r\n\r\n## Altro\r\n"
    #expect(RelatedSection.parse(from: body).map(\.target) == ["A", "B"])
    let section = RelatedSection.sectionRange(in: body)
    #expect(section.map { body[$0].hasSuffix("- [[B]] — s\r\n\r\n") } == true)
}

@Test func collegaBesideAFencedHeadingWritesARealSection() throws {
    let fenced = "```\n## Note correlate\n```\n"
    let text = note("# Nota\n\n" + fenced)

    let linked = try RelatedLink.add(target: "A", reason: "motivo", to: text, selfTitle: "Nota")

    #expect(linked.contains(fenced + "\n## Note correlate\n\n- [[A]] — motivo\n"))
}

@Test func anUnclosedFenceHidesAHeadingBelowItButNotOneAbove() {
    let above = "## Note correlate\n\n- [[A]] — r\n\n```\ncodice\n"
    #expect(RelatedSection.parse(from: above).map(\.target) == ["A"])
    let below = "# T\n\n```\n## Note correlate\n- [[A]] — r\n"
    #expect(RelatedSection.sectionRange(in: below) == nil)
}

@Test func aFencedHeadingIsNotAnotherSectionsEndEither() {
    let body = "## Note correlate\n\n- [[A]] — r\n\n~~~\n## Altro\n~~~\n\n- [[B]] — s\n"
    #expect(RelatedSection.parse(from: body).map(\.target) == ["A", "B"])
}

// PG-372: «Collega» adds one bullet and leaves every other line of the section as it was
// written - prose, a fence and its own `-` lines, an indented sub-item, the blank lines.

@Test func collegaKeepsProseAndAFenceInTheSection() throws {
    let section = "## Note correlate\n\nIntro in prosa.\n\n- [[B]] — b\n\n"
        + "```yaml\n- voce\n```\n\nChiusura.\n\n## Altro\n"
    let linked = try RelatedLink.add(
        target: "C", reason: "c", to: note(related: ["[[B]]"], section), selfTitle: "Nota"
    )
    #expect(linked.hasSuffix(
        "## Note correlate\n\nIntro in prosa.\n\n- [[B]] — b\n- [[C]] — c\n\n"
            + "```yaml\n- voce\n```\n\nChiusura.\n\n## Altro\n"
    ))
}

@Test func collegaInsertsInOrderAndKeepsASubItemWithItsBullet() throws {
    let text = "---\r\ndate: 2026-09-26\r\ntags:\r\n  - type-note\r\nrelated:\r\n"
        + "  - \"[[A]]\"\r\n  - \"[[C]]\"\r\n---\r\n"
        + "## Note correlate\r\n\r\n- [[A]] — a\r\n  - dettaglio\r\n- [[C]] — c\r\n"
    let linked = try RelatedLink.add(target: "B", reason: "b", to: text, selfTitle: "Nota")
    #expect(isAllCRLF(linked))
    #expect(linked.hasSuffix(
        "## Note correlate\r\n\r\n- [[A]] — a\r\n  - dettaglio\r\n- [[B]] — b\r\n- [[C]] — c\r\n"
    ))
}

@Test func collegaInASectionWithOnlyProseKeepsTheProse() throws {
    let linked = try RelatedLink.add(
        target: "A", reason: "motivo",
        to: note("## Note correlate\n\nVedi anche la cartella.\n"), selfTitle: "Nota"
    )
    #expect(linked.hasSuffix("## Note correlate\n\n- [[A]] — motivo\n\nVedi anche la cartella.\n"))
}

@Test func collegaUnderABareHeadingBeforeAnotherSection() throws {
    let linked = try RelatedLink.add(
        target: "A", reason: "motivo", to: note("## Note correlate\n## Altro\n"), selfTitle: "Nota"
    )
    #expect(linked.hasSuffix("## Note correlate\n\n- [[A]] — motivo\n\n## Altro\n"))
}

// PG-372, the inverse: removing a link takes out its bullet and leaves every other line of the
// section as it was written.

@Test func unlinkKeepsTheProseAndTheFenceOfTheSection() {
    let section = "## Note correlate\n\nIntro in prosa.\n\n- [[A]] — a\n- [[B]] — b\n\n"
        + "```yaml\n- voce\n```\n\nChiusura.\n\n## Altro\n"
    let unlinked = RelatedLink.remove(target: "A", from: note(related: ["[[A]]", "[[B]]"], section))
    #expect(unlinked.hasSuffix(
        "## Note correlate\n\nIntro in prosa.\n\n- [[B]] — b\n\n```yaml\n- voce\n```\n\nChiusura.\n\n## Altro\n"
    ))
}

@Test func unlinkLeavesTheSameLinkInsideAFence() {
    let section = "## Note correlate\n\n- [[A]] — a\n- [[X]] — x\n\n```\n- [[X]] — x\n```\n"
    let unlinked = RelatedLink.remove(target: "X", from: note(related: ["[[A]]", "[[X]]"], section))
    #expect(unlinked.hasSuffix("## Note correlate\n\n- [[A]] — a\n\n```\n- [[X]] — x\n```\n"))
}

@Test func unlinkOnACRLFSectionWithProseKeepsBoth() {
    let text = "---\r\ndate: 2026-09-26\r\ntags:\r\n  - type-note\r\nrelated:\r\n"
        + "  - \"[[A]]\"\r\n  - \"[[B]]\"\r\n---\r\n"
        + "## Note correlate\r\n\r\nIntro.\r\n\r\n- [[A]] — a\r\n  - dettaglio\r\n- [[B]] — b\r\n"
    let unlinked = RelatedLink.remove(target: "A", from: text)
    #expect(isAllCRLF(unlinked))
    // The sub-item belongs to the removed bullet and goes with it.
    #expect(unlinked.hasSuffix("## Note correlate\r\n\r\nIntro.\r\n\r\n- [[B]] — b\r\n"))
}

@Test func linkThenUnlinkLeavesAProseSectionAsItWas() throws {
    let section = "## Note correlate\n\nVedi anche la cartella.\n"
    let linked = try RelatedLink.add(target: "A", reason: "motivo", to: note(section), selfTitle: "Nota")
    #expect(RelatedLink.remove(target: "A", from: linked).hasSuffix("\n\n" + section))
}

@Test(arguments: [
    ("## Note correlate\n\n- [[A]] — a\n\n## Altro\n", "\n\n## Note correlate\n\n## Altro\n"),
    ("## Note correlate\n\n- [[A]] — a\n", "\n\n## Note correlate\n"),
])
func unlinkingTheLastLinkKeepsTheBareHeading(section: String, expected: String) {
    #expect(RelatedLink.remove(target: "A", from: note(related: ["[[A]]"], section)).hasSuffix(expected))
}

// PG-372 review: a bullet indented by one to three spaces is a link to `RelatedSection.parse`
// (it trims every line), so «Collega» and «Scollega» treat it as one too.

@Test func unlinkRemovesABulletIndentedByOneToThreeSpaces() {
    for indent in ["", " ", "  ", "   "] {
        let section = "## Note correlate\n\n\(indent)- [[A]] — a\n\(indent)- [[B]] — b\n"
        let unlinked = RelatedLink.remove(target: "B", from: note(related: ["[[A]]", "[[B]]"], section))
        #expect(RelatedSection.parse(from: NoteDocument.parse(unlinked).body).map(\.target) == ["A"])
        #expect(unlinked.hasSuffix("## Note correlate\n\n\(indent)- [[A]] — a\n"))
    }
}

@Test func collegaSortsAgainstABulletIndentedByOneToThreeSpaces() throws {
    let linked = try RelatedLink.add(
        target: "A", reason: "a", to: note(related: ["[[B]]"], "## Note correlate\n\n  - [[B]] — b\n"),
        selfTitle: "Nota"
    )
    #expect(linked.hasSuffix("## Note correlate\n\n- [[A]] — a\n  - [[B]] — b\n"))
}

@Test func anIndentedBulletKeepsItsContinuationAndSubItems() {
    let section = "## Note correlate\n\n - [[A]] — a\n    righe a capo\n   - dettaglio\n - [[B]] — b\n"
    let unlinked = RelatedLink.remove(target: "A", from: note(related: ["[[A]]", "[[B]]"], section))
    #expect(unlinked.hasSuffix("## Note correlate\n\n - [[B]] — b\n"))
}

// PG-372 review: only a bullet that links to a note is a sort anchor, so a prose bullet beside
// the links never pulls a new link above it.

@Test func collegaNeverUsesAProseBulletAsTheSortAnchor() throws {
    let section = "## Note correlate\n\n- vedi la cartella\n- [[A]] — a\n"
    let linked = try RelatedLink.add(
        target: "B", reason: "b", to: note(related: ["[[A]]"], section), selfTitle: "Nota"
    )
    #expect(linked.hasSuffix("## Note correlate\n\n- vedi la cartella\n- [[A]] — a\n- [[B]] — b\n"))
}

@Test func collegaAfterTheLastLinkBulletEvenWhenProseBulletsFollow() throws {
    let section = "## Note correlate\n\n- [[A]] — a\n- vedi la cartella\n"
    let linked = try RelatedLink.add(
        target: "B", reason: "b", to: note(related: ["[[A]]"], section), selfTitle: "Nota"
    )
    #expect(linked.hasSuffix("## Note correlate\n\n- [[A]] — a\n- [[B]] — b\n- vedi la cartella\n"))
}
