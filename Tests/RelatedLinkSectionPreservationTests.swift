import Foundation
import Testing
@testable import Pergamenum

// PG-372: «Collega» inserts one line into `## Note correlate` and leaves the rest of the
// section as written. Complements the tests in `RelatedSectionTests.swift` with the
// fence-that-looks-like-links shape and the app's own door, `VaultSession.addStructuralLink`.

private func doc(_ body: String) -> String {
    "---\ndate: 2026-09-26\ntags:\n  - type-note\n---\n\n\(body)"
}

private let fencedSection = "## Note correlate\n\n- [[A]] — a\n\n"
    + "```\n- [[Z]] — z\n- [[B]] — b\n```\n\nChiusura.\n"

@Test func collegaLeavesLinkLookingLinesInAFenceUntouched() throws {
    let linked = try RelatedLink.add(target: "C", reason: "c", to: doc(fencedSection), selfTitle: "Nota")
    #expect(linked.hasSuffix(
        "## Note correlate\n\n- [[A]] — a\n- [[C]] — c\n\n```\n- [[Z]] — z\n- [[B]] — b\n```\n\nChiusura.\n"
    ))
}

@Test func collegaNeverUsesAFenceLineAsTheSortAnchor() throws {
    // `[[Y]]` sorts before the fence's `[[Z]]`: the fence's line must not pull the new bullet in.
    let linked = try RelatedLink.add(target: "Y", reason: "y", to: doc(fencedSection), selfTitle: "Nota")
    #expect(linked.hasSuffix(
        "## Note correlate\n\n- [[A]] — a\n- [[Y]] — y\n\n```\n- [[Z]] — z\n- [[B]] — b\n```\n\nChiusura.\n"
    ))
}

@Test func collegaBeforeTheFirstBulletKeepsTheFence() throws {
    let body = "## Note correlate\n\n- [[M]] — m\n\n```\n- [[A]] — fence\n```\n"
    let linked = try RelatedLink.add(target: "B", reason: "b", to: doc(body), selfTitle: "Nota")
    #expect(linked.hasSuffix("## Note correlate\n\n- [[B]] — b\n- [[M]] — m\n\n```\n- [[A]] — fence\n```\n"))
}

@Test func collegaOnASectionWithoutALineBreakAtTheEnd() throws {
    let linked = try RelatedLink.add(
        target: "B", reason: "b", to: doc("## Note correlate\n\n- [[A]] — a"), selfTitle: "Nota"
    )
    #expect(linked.hasSuffix("## Note correlate\n\n- [[A]] — a\n- [[B]] — b\n"))
}

@MainActor
@Test func addStructuralLinkKeepsTheFenceAndProseOfTheSourceSection() async throws {
    let vault = try TemporaryVault()
    let source = doc(fencedSection)
    try vault.write(source, to: "Origine.md")
    try vault.write(doc("Corpo."), to: "Destinazione.md")
    let session = VaultSession(
        root: vault.root,
        stateBase: vault.stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    await session.rescan()

    let (created, _) = await session.addStructuralLink(
        from: "Origine.md", toNoteAt: "Destinazione.md", reason: "usa", reverseReason: "fornisce"
    )

    #expect(created)
    let text = try session.read("Origine.md").text
    #expect(text.hasSuffix(
        "## Note correlate\n\n- [[A]] — a\n- [[Destinazione]] — usa\n\n"
            + "```\n- [[Z]] — z\n- [[B]] — b\n```\n\nChiusura.\n"
    ))
    #expect(try session.read("Destinazione.md").text.contains("- [[Origine]] — fornisce"))
}

// PG-372 review: the line roles of `RelatedLink.roles(of:code:)` and the edge shapes of the two
// writers, each pinned on its own.

/// `doc(_:)` in the given line break, frontmatter included, so the note's own break is detected.
private func doc(_ body: String, lineBreak nl: String) -> String {
    "---\(nl)date: 2026-09-26\(nl)tags:\(nl)  - type-note\(nl)---\(nl)\(nl)\(body)"
}

/// No `\n` in `text` that is not the second half of a CRLF pair.
private func hasNoBareLF(_ text: String) -> Bool {
    !text.replacingOccurrences(of: "\r\n", with: "").contains("\n")
}

@Test func aTabUnderABulletIsFourColumnsSoItsDashLineIsASubItem() {
    // At one column a tab would make `\t- dettaglio` a sibling bullet; at four it is a sub-item
    // and goes with its bullet, as does the tab-indented wrapped line after it.
    let section = "## Note correlate\n\n- [[A]] — a\n\t- dettaglio\n\tseguito\n- [[B]] — b\n"
    #expect(RelatedLink.remove(target: "A", from: doc(section)).hasSuffix("## Note correlate\n\n- [[B]] — b\n"))
}

@Test func aTabIndentedDashLineIsNotATopLevelBullet() throws {
    // Four columns is past the three a bullet allows, so with no bullet above it the line is
    // `other`: «Scollega» leaves it, and «Collega» does not sort against it.
    let section = "## Note correlate\n\n\t- [[B]] — b\n"
    #expect(RelatedLink.remove(target: "B", from: doc(section)).hasSuffix(section))
    let linked = try RelatedLink.add(target: "A", reason: "a", to: doc(section), selfTitle: "Nota")
    #expect(linked.hasSuffix("## Note correlate\n\n- [[A]] — a\n\n\t- [[B]] — b\n"))
}

@Test func aDashOneColumnPastABulletIsASiblingAndTwoColumnsASubItem() {
    let sibling = "## Note correlate\n\n- [[A]] — a\n - [[B]] — b\n"
    #expect(RelatedLink.remove(target: "A", from: doc(sibling)).hasSuffix("## Note correlate\n\n - [[B]] — b\n"))
    #expect(RelatedLink.remove(target: "B", from: doc(sibling)).hasSuffix("## Note correlate\n\n- [[A]] — a\n"))

    let subItem = "## Note correlate\n\n- [[A]] — a\n  - [[B]] — b\n"
    let unlinked = RelatedLink.remove(target: "A", from: doc(subItem))
    #expect(!unlinked.contains("[[B]]"))
    #expect(unlinked.hasSuffix("## Note correlate\n"))
}

@Test(arguments: ["\n", "\r\n"])
func collegaUnderAHeadingThatEndsTheNoteWithNoLineBreak(nl: String) throws {
    let linked = try RelatedLink.add(
        target: "A", reason: "a", to: doc("## Note correlate", lineBreak: nl), selfTitle: "Nota"
    )
    #expect(linked.hasSuffix("## Note correlate\(nl)\(nl)- [[A]] — a\(nl)"))
    if nl == "\r\n" { #expect(hasNoBareLF(linked)) }
}

@Test func unlinkOnASectionWhoseLastBulletHasNoLineBreak() {
    let section = "## Note correlate\n\n- [[A]] — a\n- [[B]] — b"
    // The bullet left last keeps the line break it already had.
    #expect(RelatedLink.remove(target: "B", from: doc(section)).hasSuffix("## Note correlate\n\n- [[A]] — a\n"))
    // The unterminated bullet left last stays unterminated.
    #expect(RelatedLink.remove(target: "A", from: doc(section)).hasSuffix("## Note correlate\n\n- [[B]] — b"))
}

@Test func collegaInACRLFSectionWithOnlyProse() throws {
    let text = doc("## Note correlate\r\n\r\nVedi anche la cartella.\r\n", lineBreak: "\r\n")
    let linked = try RelatedLink.add(target: "A", reason: "motivo", to: text, selfTitle: "Nota")
    #expect(hasNoBareLF(linked))
    #expect(linked.hasSuffix("## Note correlate\r\n\r\n- [[A]] — motivo\r\n\r\nVedi anche la cartella.\r\n"))
}

@Test func unlinkABulletBetweenBlankLinesInACRLFNote() {
    let text = doc("## Note correlate\r\n\r\nIntro.\r\n\r\n- [[A]] — a\r\n\r\nChiusura.\r\n", lineBreak: "\r\n")
    let unlinked = RelatedLink.remove(target: "A", from: text)
    #expect(hasNoBareLF(unlinked))
    // The bullet takes one of the two blank lines with it.
    #expect(unlinked.hasSuffix("## Note correlate\r\n\r\nIntro.\r\n\r\nChiusura.\r\n"))
}

@Test(arguments: ["- [[A|alias]] — r", "- [[A#Sezione]] — r", "- [[A#Sezione|alias]] — r"])
func unlinkFindsTheTargetBehindAnAliasOrAHeading(bullet: String) {
    let unlinked = RelatedLink.remove(target: "A", from: doc("## Note correlate\n\n\(bullet)\n- [[B]] — b\n"))
    #expect(unlinked.hasSuffix("## Note correlate\n\n- [[B]] — b\n"))
}

@Test func unlinkLeavesABulletWhoseFirstLinkIsAnEmbed() {
    // `RelatedSection.parse` reads a bullet's first wikilink only, and skips the line when that
    // one is an embed: it does not fall through to a later link. Neither line is a structural
    // link, so «Scollega» touches neither, whichever target it is asked for.
    let section = "## Note correlate\n\n- ![[A]] — r\n- ![[A]] [[B]] — r\n"
    #expect(RelatedSection.parse(from: section).isEmpty)
    #expect(RelatedLink.remove(target: "A", from: doc(section)).hasSuffix(section))
    #expect(RelatedLink.remove(target: "B", from: doc(section)).hasSuffix(section))
}

@Test func unlinkKeepsALooseItemsLaterParagraphAsProse() {
    let section = "## Note correlate\n\n- [[A]] — a\n\n  seconda parte\n"
    #expect(RelatedLink.remove(target: "A", from: doc(section)).hasSuffix("## Note correlate\n\n  seconda parte\n"))
}
