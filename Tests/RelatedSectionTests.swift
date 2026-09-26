import Foundation
import Testing
@testable import Pergamenum

// ADR-0064 §D9.3, plan docs/plans/format-edge-hardening.md, Task 6 - R-18, R-01, G1.4.
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
