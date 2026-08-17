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

// MARK: - Fenced code blocks (M8)

/// The note used by most of the fence tests: three lines of shell, every one of which the
/// styler used to read as something else entirely.
private let shellNote = """
Prima del blocco.

```sh
# nota per #project-forno
perg index --vault "$HOME/Labs" >2026-01-01
echo *tutto*
```

Dopo il blocco, con #topic-cli e *corsivo*.
"""

@Test func aFenceIsStyledAsOneBlockIncludingItsBackticks() {
    #expect(styled(shellNote, .codeBlock)?.hasPrefix("```sh") == true)
    #expect(styled(shellNote, .codeBlock)?.hasSuffix("```") == true)
}

@Test func markdownStopsBeingMarkdownInsideAFence() {
    // The defect this slice closes, in one assertion per shape. The editor had never
    // known that a fence exists, so a shell comment was styled as a tag, a SQL or shell
    // `>date` as a scheduling marker, and a pair of wildcards as italics.
    let result = spans(shellNote)
    #expect(!result.contains(.tag("#project-forno")))
    #expect(!result.contains(.scheduled))
    // Asserted on the text and not on the presence of `.italic`, because there is a real
    // one further down the note: what must not exist is the pair inside the fence.
    #expect(italics(shellNote) == ["*corsivo*"])
}

private func italics(_ text: String) -> [String] {
    MarkdownStyler.spans(in: text)
        .filter { $0.span == .italic }
        .map { String(text[$0.range]) }
}

@Test func whatIsOutsideTheFenceIsStillMarkdown() {
    // The other half, and the one a too-eager fix would break: the block must not turn
    // the rest of the note into code.
    let result = spans(shellNote)
    #expect(result.contains(.tag("#topic-cli")))
    #expect(styled(shellNote, .italic) == "*corsivo*")
}

@Test func theGrammarReachesTheCodeInsideTheFence() {
    #expect(spans(shellNote).contains(.codeToken(.comment)))
    #expect(styled(shellNote, .codeToken(.string)) == "\"$HOME/Labs\"")
}

@Test func aWikilinkInsideAFenceIsNotClickable() {
    // An example of the syntax, not a link out of the note.
    let note = "```md\nvedi [[Altra nota]]\n```"
    #expect(styled(note, .linkTarget("Altra nota")) == nil)
    #expect(!spans(note).contains(.linkSyntax))
}

@Test func anUnclosedFenceEndsWithTheNoteAndSoDoesTheReadingView() {
    // Asserted on both parsers at once, because they are two traversals of one rule
    // (`CodeFence`) and the only thing keeping them together is that they agree here.
    // While someone types the opening backticks, every note is a note with an open fence.
    let note = "Prima.\n\n```swift\nlet a = 1"
    #expect(styled(note, .codeBlock) == "```swift\nlet a = 1")

    let blocks = MarkdownBlockParser.blocks(in: note)
    let code = blocks.compactMap { block -> [String]? in
        if case .code(_, let lines) = block { return lines }
        return nil
    }
    #expect(code == [["let a = 1"]])
}

@Test func aFenceWithNothingInItIsStillAFence() {
    // Two backtick lines and no body: the state a note is in for one keystroke after the
    // slash menu writes a code block.
    let note = "```\n```"
    #expect(styled(note, .codeBlock) == note)
    #expect(!spans(note).contains { if case .codeToken = $0 { true } else { false } })
}

@Test func inlineCodeInProseIsUntouchedByAnyOfThis() {
    // A single backtick run is not a fence and never was; the fence work must not have
    // moved it.
    #expect(styled("usa `codice` inline", .code) == "`codice`")
    #expect(!spans("usa `codice` inline").contains(.codeBlock))
}
