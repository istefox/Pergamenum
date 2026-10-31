import Foundation
import Testing
@testable import Pergamenum

// ADR-0097 §D1/§D2, plan docs/plans/pg-399-rename-backlink-rule.md Task 1 (R-01, R-02, R-03).
//
// A wikilink names the note whose title equals its `resolvedTitle`, compared case-insensitively
// with surrounding spaces and tabs ignored. `Wikilink.names(_:)` is that predicate and
// `Wikilink.target(_:names:)` the same predicate over a bare interior. Each case parses a body
// with `WikilinkParser.links(in:)`, so the parser's own reading of the spelling is part of what
// is pinned.

private func firstLink(_ source: String) throws -> Wikilink {
    try #require(WikilinkParser.links(in: source).first, "nessun link in: \(source)")
}

// MARK: - names(_:)

@Test(arguments: [
    "[[Curva]]",
    "[[curva]]",
    "[[**Curva**]]",
    "[[~~Curva~~]]",
    "[[*Curva*]]",
    "[[**Curva**#Sez|alias]]",
    "![[**Curva**]]",
    "[[** Curva **]]",
])
func aLinkNamesTheTitleItsEmphasisWraps(source: String) throws {
    #expect(try firstLink(source).names("Curva"), "\(source) dovrebbe nominare Curva")
}

@Test(arguments: [
    "[[**Curva** vecchio]]",
    "[[Curvatura]]",
    // One pair only: this link names `*Curva*`, as it does today (ADR-0065 R-19).
    "[[***Curva***]]",
])
func aLinkThatNamesAnotherTitleDoesNotNameCurva(source: String) throws {
    #expect(try !firstLink(source).names("Curva"), "\(source) non dovrebbe nominare Curva")
}

@Test func theTitleIsCaseInsensitiveAndTrimmedOnBothSides() throws {
    #expect(try firstLink("[[**CURVA**]]").names("curva"))
    #expect(try firstLink("[[Curva]]").names("  Curva\t"))
}

// MARK: - target(_:names:)

@Test func theBareInteriorFormIsTheSamePredicate() {
    #expect(Wikilink.target("**Curva**", names: "Curva"))
    #expect(Wikilink.target("Curva", names: " curva "))
    #expect(Wikilink.target("~~Curva~~", names: "CURVA"))
    #expect(!Wikilink.target("**Curva** vecchio", names: "Curva"))
    #expect(!Wikilink.target("***Curva***", names: "Curva"))
    #expect(Wikilink.target("***Curva***", names: "*Curva*"))
}

// MARK: - resolvedTitle (R-02)

@Test func resolvedTitleTrimsAfterStrippingItsOnePair() throws {
    #expect(try firstLink("[[** Curva **]]").resolvedTitle == "Curva")
    #expect(try firstLink("[[**Curva**]]").resolvedTitle == "Curva")
}

@Test func resolvedTitleIsTheTargetWhenTrimmingLeavesNothing() throws {
    #expect(try firstLink("[[** **]]").resolvedTitle == "** **")
}

// MARK: - isNoteLink judges the resolved title (R-03)

@Test(arguments: ["[[**Q4.canvas**]]", "![[**foto.png**]]"])
func anEmphasisedBoardOrFileIsNotANoteLink(source: String) throws {
    #expect(try !firstLink(source).isNoteLink, "\(source) non è un link a una nota")
}

@Test(arguments: ["[[**Nota**]]", "![[**Nota**]]"])
func anEmphasisedNoteLinkIsANoteLink(source: String) throws {
    #expect(try firstLink(source).isNoteLink, "\(source) è un link a una nota")
}

// MARK: - NoteStore.linkTargets(in:) stores the resolved title (R-03)

@Test func theIndexStoresTheResolvedTitleDeduplicatedOnIt() {
    let document = NoteDocument.parse("Con enfasi [[**Curva**]] e senza [[Curva]].")

    #expect(NoteStore.linkTargets(in: document) == ["Curva"])
}

@Test func theIndexStoresTheResolvedTitleInSourceOrder() {
    let document = NoteDocument.parse("[[~~Forno~~]] e [[Altra]]")

    #expect(NoteStore.linkTargets(in: document) == ["Forno", "Altra"])
}

@Test func anEmphasisedBoardLinkStaysOutOfTheIndex() {
    // ADR-0065 §D9.5 (R-20): a `.canvas` target is judged after the emphasis is stripped.
    #expect(NoteStore.linkTargets(in: NoteDocument.parse("[[**Q4.canvas**]]")).isEmpty)
}

// MARK: - (coverage) a tab inside the pair is trimmed like a space (ADR-0097 §D1)

@Test func aTabInsideTheEmphasisPairIsTrimmedLikeASpace() throws {
    let link = try firstLink("[[**\tCurva\t**]]")

    #expect(link.resolvedTitle == "Curva")
    #expect(link.names("Curva"))
    #expect(Wikilink.target("~~\t Curva \t~~", names: "curva"))
}
