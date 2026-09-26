import Foundation
import Testing
@testable import Pergamenum

// ADR-0065 §D1-§D3, plan docs/plans/format-edge-hardening.md, Task 1 - R-01, R-03, R-04, R-05.
//
// `NoteDocument` keeps the lines it read and edits the block in place: what the caller did not
// change comes back byte for byte.

private typealias VaultTag = Pergamenum.Tag

/// A category change the way `linkCategory` makes one: filter every occurrence, then append.
private func withCategory(_ slug: String, _ text: String) -> String {
    var document = NoteDocument.parse(text)
    document.frontmatter.foreignKeys.removeAll { $0.name == "pergamenum-category" }
    document.frontmatter.foreignKeys.append(
        Frontmatter.ForeignKey(name: "pergamenum-category", lines: ["pergamenum-category: \(slug)"])
    )
    return document.serialized()
}

private func withRelated(_ related: [String], _ text: String) -> String {
    var document = NoteDocument.parse(text)
    document.frontmatter.related = related
    return document.serialized()
}

@Test(arguments: FormatEdgeCorpus.notes)
func everyNoteCaseRoundTripsByteIdentical(_ note: FormatEdgeCorpus.NoteCase) {
    #expect(NoteDocument.parse(note.text).serialized() == note.text)
}

@Test func aCRLFNoteGainsOneLineOnACategoryChange() {
    let written = withCategory("presse", FormatEdgeCorpus.crlfWithFrontmatter.text)
    #expect(written == "---\r\ndate: 2026-09-26\r\ntags:\r\n  - type-note\r\npergamenum-category: presse\r\n---\r\n# Titolo\r\n\r\nCorpo.\r\n")
    let lines = written.components(separatedBy: "\n").dropLast()
    #expect(lines.allSatisfy { $0.hasSuffix("\r") })
    #expect(lines.filter { $0 == "---\r" }.count == 2)
}

@Test func aNoteWithoutFrontmatterSerializesToItself() {
    for note in [FormatEdgeCorpus.crlfWithoutFrontmatter, FormatEdgeCorpus.lfWithoutFrontmatter] {
        let written = NoteDocument.parse(note.text).serialized()
        #expect(written == note.text)
        #expect(!written.contains("---"))
    }
}

@Test func aNoteWithoutFrontmatterThatGainsAKeyGetsOneBlock() {
    let written = withRelated(["[[Alfa]]"], FormatEdgeCorpus.crlfWithoutFrontmatter.text)
    #expect(written == "---\r\nrelated:\r\n  - \"[[Alfa]]\"\r\n---\r\n" + FormatEdgeCorpus.crlfWithoutFrontmatter.text)
}

@Test func aCRLFBodyIsTheVerbatimTail() {
    let text = FormatEdgeCorpus.crlfWithFrontmatter.text
    let document = NoteDocument.parse(text)
    #expect(document.hasFrontmatterBlock)
    #expect(document.body == "# Titolo\r\n\r\nCorpo.\r\n")
    #expect(text.hasSuffix(document.body))
    #expect(document.frontmatter.tags.map(\.description) == ["type-note"])
    #expect(document.frontmatter.date == CalendarDate(iso: "2026-09-26"))
}

@Test func aClosingDelimiterWithoutLineBreakGainsNone() {
    let written = withRelated(["[[Alfa]]"], FormatEdgeCorpus.closingWithoutLineBreak.text)
    #expect(written == "---\ndate: 2026-09-26\ntags:\n  - type-note\nrelated:\n  - \"[[Alfa]]\"\n---")
}

@Test func aTextBorneBOMStaysFirst() {
    let text = FormatEdgeCorpus.textBorneBOM.text
    #expect(NoteDocument.parse(text).serialized() == text)
    #expect(NoteDocument.parse(text).hasFrontmatterBlock)
    let written = withCategory("presse", text)
    #expect(written.hasPrefix("\u{FEFF}---\n"))
    #expect(written.unicodeScalars.filter { $0 == "\u{FEFF}" }.count == 1)
    #expect(written == "\u{FEFF}---\ndate: 2026-09-26\ntags: [type-note]\npergamenum-category: presse\n---\nCorpo.\n")
}

@Test func anUnparsableTagSurvivesATagWrite() throws {
    var document = NoteDocument.parse(FormatEdgeCorpus.unparsableTag.text)
    #expect(document.frontmatter.unparsableTags == ["cliente-acme"])
    document.frontmatter.tags.append(try #require(VaultTag("topic-gomma")))
    let valid = TagRules.ordered(document.frontmatter.tags).map { "  - \($0)\n" }.joined()
    #expect(document.serialized().contains("tags:\n" + valid + "  - cliente-acme\n---"))
}

@Test func aFreshRenderWritesUnparsableTagsLast() throws {
    var frontmatter = Frontmatter.empty
    frontmatter.tags = [try #require(VaultTag("type-note"))]
    frontmatter.unparsableTags = ["cliente-acme"]
    #expect(FrontmatterSerializer.render(frontmatter).contains("  - type-note\n  - cliente-acme\n"))
}

@Test func anUnchangedTagsKeyKeepsItsSourceOrder() {
    let written = withRelated(["[[Alfa]]"], FormatEdgeCorpus.unsortedInlineTags.text)
    #expect(written.components(separatedBy: "\n").contains("tags: [topic-zeta, type-note]"))
}

@Test func aColumnZeroCommentStaysOnItsLine() {
    let written = withRelated(["[[Alfa]]"], FormatEdgeCorpus.yamlComment.text)
    #expect(written.components(separatedBy: "\n")[1] == "# importato da Plaud")
}

@Test func aColonlessLineAndABlankLineStayInPlace() {
    let written = withCategory("presse", FormatEdgeCorpus.colonlessAndBlankLines.text)
    #expect(written == "---\ndate: 2026-09-26\n\nsolo testo\ntags:\n  - type-note\npergamenum-category: presse\n---\nCorpo.\n")
}

@Test func anOrphanContinuationLineIsKept() {
    let written = withCategory("presse", FormatEdgeCorpus.orphanContinuation.text)
    #expect(written.components(separatedBy: "\n")[1] == "  - vagante")
    #expect(written == "---\n  - vagante\ndate: 2026-09-26\ntags:\n  - type-note\npergamenum-category: presse\n---\nCorpo.\n")
}

@Test func aDuplicatedTagsKeySurvivesACategoryWrite() {
    let written = withCategory("presse", FormatEdgeCorpus.duplicateTags.text)
    #expect(written == "---\ndate: 2026-09-26\ntags:\n  - type-note\ntags:\n  - topic-gomma\npergamenum-category: presse\n---\nCorpo.\n")
    #expect(NoteDocument.parse(written).frontmatter.tags.map(\.description) == ["topic-gomma"])
}

@Test func aDuplicatedForeignKeySurvivesAnUnrelatedWrite() {
    let written = withRelated(["[[Alfa]]"], FormatEdgeCorpus.duplicateForeign.text)
    #expect(written == "---\ncssclass: wide\ndate: 2026-09-26\ncssclass: narrow\ntags:\n  - type-note\nrelated:\n  - \"[[Alfa]]\"\n---\nCorpo.\n")
}

@Test func aChangedDuplicatedKeyRewritesTheLastOccurrence() {
    var document = NoteDocument.parse(FormatEdgeCorpus.duplicateRelated.text)
    #expect(document.frontmatter.related == ["[[Beta]]"])
    document.frontmatter.related.append("[[Gamma]]")
    let written = document.serialized()
    #expect(written == "---\ndate: 2026-09-26\ntags:\n  - type-note\nrelated:\n  - \"[[Alfa]]\"\nrelated:\n  - \"[[Beta]]\"\n  - \"[[Gamma]]\"\n---\nCorpo.\n")
    #expect(NoteDocument.parse(written).frontmatter.related == ["[[Beta]]", "[[Gamma]]"])
}

@Test func anEmptiedDuplicatedKeyIsWrittenBare() {
    let written = withRelated([], FormatEdgeCorpus.duplicateRelated.text)
    #expect(written == "---\ndate: 2026-09-26\ntags:\n  - type-note\nrelated:\n  - \"[[Alfa]]\"\nrelated:\n---\nCorpo.\n")
    #expect(NoteDocument.parse(written).frontmatter.related.isEmpty)
}

@Test func aCodecOwnedDuplicateFollowsTheCodec() {
    let written = withCategory("presse", FormatEdgeCorpus.duplicateCategory.text)
    #expect(written == "---\ndate: 2026-09-26\ntags:\n  - type-note\npergamenum-category: presse\n---\nCorpo.\n")
}
