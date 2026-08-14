import Foundation
import Testing
@testable import Pergamenum

private func spans(_ text: String) -> [MarkdownStyler.Span] {
    MarkdownStyler.spans(in: text).map(\.span)
}

private func styled(_ text: String, _ span: MarkdownStyler.Span) -> String? {
    guard let match = MarkdownStyler.spans(in: text).first(where: { $0.span == span }) else { return nil }
    return String(text[match.range])
}

@Test func stylesTheFrontmatterBlock() {
    let note = "---\ndate: 2026-08-11\n---\ncorpo"
    #expect(styled(note, .frontmatter) == "---\ndate: 2026-08-11\n---")
}

@Test func doesNotTreatARuleInTheBodyAsFrontmatter() {
    // A `---` further down is a horizontal rule, not a frontmatter block.
    #expect(!spans("testo\n\n---\n\naltro").contains(.frontmatter))
}

@Test(arguments: [1, 2, 3, 6])
func stylesHeadings(_ level: Int) {
    let text = String(repeating: "#", count: level) + " Titolo"
    #expect(spans(text).contains(.heading(level: level)))
}

@Test func doesNotTreatATagAsAHeading() {
    // `#tag` has no space after the hashes, so it is a tag and not a heading.
    let result = spans("#type-note in apertura di riga")
    #expect(!result.contains { if case .heading = $0 { true } else { false } })
    #expect(result.contains(.tag("#type-note")))
}

@Test func stylesInlineTagsOnlyAtWordBoundaries() {
    // The `#` inside a URL fragment is not a tag.
    #expect(!spans("vedi https://x.test/a#type-note").contains(.tag("#type-note")))
    #expect(spans("nota con #topic-acoustics dentro").contains(.tag("#topic-acoustics")))
}

@Test func doesNotStyleAMalformedTag() {
    // `#varie` has no namespace, so it is not a tag at all (T-01).
    #expect(!spans("testo #varie").contains { if case .tag = $0 { true } else { false } })
}

@Test func stylesTaskMarkers() {
    #expect(styled("- [ ] Da fare", .taskMarker(done: false)) == "- [ ]")
    #expect(styled("- [x] Fatto", .taskMarker(done: true)) == "- [x]")
    // `- [>]` is rescheduled and `- [-]` cancelled: both are open, not done.
    #expect(spans("- [>] Rimandato").contains(.taskMarker(done: false)))
    #expect(spans("- [-] Annullato").contains(.taskMarker(done: false)))
}

@Test func indentedTaskMarkersKeepTheirPosition() {
    #expect(styled("    - [ ] Annidato", .taskMarker(done: false)) == "- [ ]")
}

@Test func stylesSchedulingMarkers() {
    #expect(styled("- [ ] Task >2026-08-15", .scheduled) == ">2026-08-15")
    #expect(styled("- [ ] Task !2026-08-20", .due) == "!2026-08-20")
    #expect(styled("- [x] Task @done(2026-08-11)", .annotation) == "@done(2026-08-11)")
}

@Test func doesNotStyleAQuoteAsAScheduledDate() {
    // A blockquote and a comparison must not be mistaken for `>YYYY-MM-DD`.
    #expect(!spans("> citazione").contains(.scheduled))
    #expect(!spans("se x > 3 allora").contains(.scheduled))
    #expect(!spans("scadenza >2026-8-1").contains(.scheduled))
}

@Test func stylesWikilinkTargetSeparatelyFromItsBrackets() {
    let text = "vedi [[Curva di trasmissibilità]] qui"
    #expect(styled(text, .linkTarget("Curva di trasmissibilità")) == "Curva di trasmissibilità")
    #expect(styled(text, .linkSyntax) == "[[Curva di trasmissibilità]]")
}

/// An embed is styled like a link but is not one: it leads to a file, and clicking it
/// used to ask the vault for a note named "schema.pdf" and, finding none, do nothing.
@Test func stylesAnEmbedAsItsOwnKindOfLink() {
    let text = "![[schema.pdf]]"
    #expect(styled(text, .linkSyntax) == "![[schema.pdf]]")
    #expect(styled(text, .embedTarget("schema.pdf")) == "schema.pdf")
    #expect(styled(text, .linkTarget("schema.pdf")) == nil)
}

/// `!` opens a deadline (`!2026-08-11`), and an embed starts with the same character.
@Test func anEmbedIsNotADeadline() {
    #expect(!spans("![[foto.png]]").contains(.due))
    #expect(spans("scadenza !2026-08-11").contains(.due))
}

@Test func stylesWikilinksInsideTheBodyOfANoteWithFrontmatter() {
    // The body scan starts after the frontmatter; an off-by-one here would shift
    // every styled range in every real note.
    let note = "---\ndate: 2026-08-11\n---\n\nvedi [[Altra nota]] qui"
    #expect(styled(note, .linkTarget("Altra nota")) == "Altra nota")
}

@Test func stylesEmphasisAndCode() {
    #expect(styled("testo **grassetto** qui", .bold) == "**grassetto**")
    #expect(styled("testo *corsivo* qui", .italic) == "*corsivo*")
    #expect(styled("usa `codice` inline", .code) == "`codice`")
}

@Test func leavesUnclosedEmphasisAlone() {
    #expect(!spans("un asterisco * solo").contains(.bold))
    #expect(!spans("un asterisco * solo").contains(.italic))
}

@Test func handlesAnEmptyNote() {
    #expect(MarkdownStyler.spans(in: "").isEmpty)
}
