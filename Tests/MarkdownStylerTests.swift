import Foundation
import Testing
@testable import Pergamenum

@Test func stylesTheFrontmatterBlock() {
    let note = "---\ndate: 2026-08-11\n---\ncorpo"
    #expect(MarkdownStylerFixture.styled(note, .frontmatter) == "---\ndate: 2026-08-11\n---")
}

@Test func doesNotTreatARuleInTheBodyAsFrontmatter() {
    // A `---` further down is a horizontal rule, not a frontmatter block.
    #expect(!MarkdownStylerFixture.spans("testo\n\n---\n\naltro").contains(.frontmatter))
}

@Test(arguments: [1, 2, 3, 6])
func stylesHeadings(_ level: Int) {
    let text = String(repeating: "#", count: level) + " Titolo"
    #expect(MarkdownStylerFixture.spans(text).contains(.heading(level: level)))
}

@Test func doesNotTreatATagAsAHeading() {
    // `#tag` has no space after the hashes, so it is a tag and not a heading.
    let result = MarkdownStylerFixture.spans("#type-note in apertura di riga")
    #expect(!result.contains { if case .heading = $0 { true } else { false } })
    #expect(result.contains(.tag("#type-note")))
}

// MARK: - The heading marker (ADR-0018 §D1)

@Test func stylesTheHeadingMarkerSeparatelyFromTheHeadingSpan() {
    // Isolated from the heading span: the marker is its own range, not a slice reported
    // out of `.heading`'s.
    #expect(MarkdownStylerFixture.styled("# Titolo", .headingMarker) == "# ")
    #expect(MarkdownStylerFixture.styled("## Titolo", .headingMarker) == "## ")
}

@Test func theHeadingMarkerRangeIncludesExactlyOneTrailingSpace() {
    // Hashes plus the single space after them - not the extra spaces before the title.
    #expect(MarkdownStylerFixture.styled("#   Titolo", .headingMarker) == "# ")
}

@Test func theHeadingMarkerSpanIsOrderedAfterTheHeadingSpan() {
    // Later spans win on overlap; the marker must come second so its colour lands on
    // top of the heading's own font and colour rather than the other way round.
    let ordered = MarkdownStyler.spans(in: "# Titolo").map(\.span)
    let headingIndex = ordered.firstIndex(of: .heading(level: 1))
    let markerIndex = ordered.firstIndex(of: .headingMarker)
    #expect(headingIndex != nil)
    #expect(markerIndex != nil)
    if let headingIndex, let markerIndex {
        #expect(headingIndex < markerIndex)
    }
}

@Test func aHeadingWithNoTitleYetHasNoMarkerSpan() {
    // Hiding the hashes on an empty heading would shrink the row to nothing the instant
    // the caret left it - worse than four characters that do nothing yet.
    #expect(!MarkdownStylerFixture.spans("# ").contains(.headingMarker))
    #expect(!MarkdownStylerFixture.spans("#   ").contains(.headingMarker))
}

@Test func aTagIsNeverAHeadingMarker() {
    #expect(!MarkdownStylerFixture.spans("#type-note in apertura di riga").contains(.headingMarker))
}

@Test func headingMarkerRangeExcludesIndentation() {
    // Mirrors `indentedTaskMarkersKeepTheirPosition`: the marker's start is measured
    // from where the line's own content begins, not from column zero.
    #expect(MarkdownStylerFixture.styled("  # Titolo", .headingMarker) == "# ")
}

// MARK: - The emphasis marker (ADR-0018 §D1, slice 2)

private func emphasisMarkers(_ text: String) -> [String] {
    MarkdownStyler.spans(in: text)
        .filter { $0.span == .emphasisMarker }
        .map { String(text[$0.range]) }
}

@Test func anItalicRunYieldsTwoOneCharacterMarkers() {
    #expect(emphasisMarkers("testo *corsivo* qui") == ["*", "*"])
}

@Test func aBoldRunYieldsTwoTwoCharacterMarkers() {
    #expect(emphasisMarkers("testo **grassetto** qui") == ["**", "**"])
}

@Test func theEmphasisMarkerSpansComeAfterTheRunSpan() {
    // Same rule as the heading marker: later spans win on overlap, so the marker's
    // colour lands on top of the run's own font rather than the other way round.
    let ordered = MarkdownStyler.spans(in: "*corsivo*").map(\.span)
    let runIndex = ordered.firstIndex(of: .italic)
    let markerIndices = ordered.indices.filter { ordered[$0] == .emphasisMarker }
    #expect(runIndex != nil)
    #expect(markerIndices.count == 2)
    if let runIndex {
        #expect(markerIndices.allSatisfy { runIndex < $0 })
    }
}

@Test func underscoreEmphasisHasNoMarkerSpan() {
    // Deliberate narrowing of ADR-0018 §D1: `emphasis(_:at:)` has no word-boundary rule,
    // so `nome_file_lungo` already parses as italic. Hiding `_` would read as
    // `nomefilelungo`, so it stays visible - parsed and coloured, never collapsed.
    #expect(emphasisMarkers("testo _corsivo_ qui").isEmpty)
    #expect(MarkdownStylerFixture.spans("testo _corsivo_ qui").contains(.italic))
}

@Test func anEmptyEmphasisRunHasNoMarkerSpan() {
    // `****` and adjacent empty `**` would collapse to nothing if hidden - worse than
    // four visible characters, the same reasoning as the empty heading.
    #expect(emphasisMarkers("testo **** qui").isEmpty)
}

@Test func anUnclosedEmphasisRunHasNoMarkerSpan() {
    #expect(emphasisMarkers("un asterisco * solo").isEmpty)
}

@Test func twoEmphasisRunsOnOneLineYieldFourMarkers() {
    #expect(emphasisMarkers("*uno* e **due**") == ["*", "*", "**", "**"])
}

@Test func emphasisInsideAFenceHasNoMarkerSpan() {
    // `echo *tutto*` inside the fence is not italic at all (`markdownStopsBeingMarkdownInsideAFence`),
    // so it yields no marker either; the only pair present is the real `*corsivo*` after the fence.
    #expect(emphasisMarkers(shellNote) == ["*", "*"])
}

@Test func stylesInlineTagsOnlyAtWordBoundaries() {
    // The `#` inside a URL fragment is not a tag.
    #expect(!MarkdownStylerFixture.spans("vedi https://x.test/a#type-note").contains(.tag("#type-note")))
    #expect(MarkdownStylerFixture.spans("nota con #topic-acoustics dentro").contains(.tag("#topic-acoustics")))
}

@Test func doesNotStyleAMalformedTag() {
    // `#varie` has no namespace, so it is not a tag at all (T-01).
    #expect(!MarkdownStylerFixture.spans("testo #varie").contains { if case .tag = $0 { true } else { false } })
}

@Test func stylesTaskMarkers() {
    #expect(MarkdownStylerFixture.styled("- [ ] Da fare", .taskMarker(state: .open)) == "- [ ]")
    #expect(MarkdownStylerFixture.styled("- [x] Fatto", .taskMarker(state: .done)) == "- [x]")
    #expect(MarkdownStylerFixture.spans("- [>] Rimandato").contains(.taskMarker(state: .rescheduled)))
    #expect(MarkdownStylerFixture.spans("- [-] Annullato").contains(.taskMarker(state: .cancelled)))
}

@Test func indentedTaskMarkersKeepTheirPosition() {
    #expect(MarkdownStylerFixture.styled("    - [ ] Annidato", .taskMarker(state: .open)) == "- [ ]")
}

@Test func stylesSchedulingMarkers() {
    #expect(MarkdownStylerFixture.styled("- [ ] Task >2026-08-15", .scheduled) == ">2026-08-15")
    #expect(MarkdownStylerFixture.styled("- [ ] Task !2026-08-20", .due) == "!2026-08-20")
    #expect(MarkdownStylerFixture.styled("- [x] Task @done(2026-08-11)", .annotation) == "@done(2026-08-11)")
}

@Test func doesNotStyleAQuoteAsAScheduledDate() {
    // A blockquote and a comparison must not be mistaken for `>YYYY-MM-DD`.
    #expect(!MarkdownStylerFixture.spans("> citazione").contains(.scheduled))
    #expect(!MarkdownStylerFixture.spans("se x > 3 allora").contains(.scheduled))
    #expect(!MarkdownStylerFixture.spans("scadenza >2026-8-1").contains(.scheduled))
}

@Test func stylesWikilinkTargetSeparatelyFromItsBrackets() {
    let text = "vedi [[Curva di trasmissibilità]] qui"
    #expect(MarkdownStylerFixture.styled(text, .linkTarget("Curva di trasmissibilità")) == "Curva di trasmissibilità")
    #expect(MarkdownStylerFixture.styled(text, .linkSyntax) == "[[Curva di trasmissibilità]]")
}

/// `wikilinkSpans` shifts each link from the parser's slice back onto the note by walking only
/// the gap since the previous link (one pass over the note, not one walk per link). The
/// positions must come out the same as when each was measured from the start: here with
/// multi-byte and combined characters between the links, a frontmatter block that the slice
/// skips, and a fence whose own link is left unstyled and does not break the walk.
@Test func everyWikilinkOfALongNoteLandsOnItsOwnText() {
    var text = "---\ntags: [a]\n---\n"
    var expected: [String] = []
    for n in 0..<300 {
        text += "Riga \(n) à👨‍👩‍👧 con [[Nota \(n)|alias ✓]] e ![[file \(n).pdf]] fine.\n\n"
        expected.append("[[Nota \(n)|alias ✓]]")
        expected.append("![[file \(n).pdf]]")
        if n == 150 { text += "```\n[[nel fence]]\n```\n\n" }
    }
    let styled = MarkdownStyler.spans(in: text)
        .filter { $0.span == .linkSyntax }
        .map { String(text[$0.range]) }
    #expect(styled == expected)
}

/// An embed is styled like a link but is not one: it leads to a file, and clicking it
/// used to ask the vault for a note named "schema.pdf" and, finding none, do nothing.
@Test func stylesAnEmbedAsItsOwnKindOfLink() {
    let text = "![[schema.pdf]]"
    #expect(MarkdownStylerFixture.styled(text, .linkSyntax) == "![[schema.pdf]]")
    #expect(MarkdownStylerFixture.styled(text, .embedTarget("schema.pdf")) == "schema.pdf")
    #expect(MarkdownStylerFixture.styled(text, .linkTarget("schema.pdf")) == nil)
}

/// `!` opens a deadline (`!2026-08-11`), and an embed starts with the same character.
@Test func anEmbedIsNotADeadline() {
    #expect(!MarkdownStylerFixture.spans("![[foto.png]]").contains(.due))
    #expect(MarkdownStylerFixture.spans("scadenza !2026-08-11").contains(.due))
}

/// Issue #188 follow-up: a wikilink whose visible text was selected and made bold
/// (`[[**Prova**]]`, produced by the format bar/Cmd+B) used to carry `.linkTarget("**Prova**")`
/// - the URL/navigation this resolves to then looked for a note literally titled "**Prova**",
/// found none, and Cmd+click silently did nothing. The payload now resolves through the
/// wrapping markers to the actual note title, while the styled RANGE stays the full literal
/// source text (`**Prova**`, all 9 characters) so the visible bold run is what is clickable.
@Test func aWikilinkTargetWrappedInBoldStillResolvesToTheBareTitle() {
    let text = "vedi [[**Prova**]] qui"
    #expect(MarkdownStylerFixture.styled(text, .linkTarget("Prova")) == "**Prova**")
}

@Test func stylesWikilinksInsideTheBodyOfANoteWithFrontmatter() {
    // The body scan starts after the frontmatter; an off-by-one here would shift
    // every styled range in every real note.
    let note = "---\ndate: 2026-08-11\n---\n\nvedi [[Altra nota]] qui"
    #expect(MarkdownStylerFixture.styled(note, .linkTarget("Altra nota")) == "Altra nota")
}

@Test func stylesEmphasisAndCode() {
    #expect(MarkdownStylerFixture.styled("testo **grassetto** qui", .bold) == "**grassetto**")
    #expect(MarkdownStylerFixture.styled("testo *corsivo* qui", .italic) == "*corsivo*")
    #expect(MarkdownStylerFixture.styled("usa `codice` inline", .code) == "`codice`")
}

@Test func leavesUnclosedEmphasisAlone() {
    #expect(!MarkdownStylerFixture.spans("un asterisco * solo").contains(.bold))
    #expect(!MarkdownStylerFixture.spans("un asterisco * solo").contains(.italic))
}

// MARK: PG-084 - recursive inline spans

// A matched `**...**` used to consume its entire range as one atomic `.bold` span, so a
// `~~...~~` nested inside it was invisible: rendered (and would conceal) only as bold, the
// `~~` markers left plain and unstyled. `inlineSpans` now recurses into a run's own inner
// content, so the nested span is emitted too.
@Test func strikethroughNestedInsideBoldIsRecognizedAlongsideTheOuterBoldSpan() {
    #expect(MarkdownStylerFixture.styled("**~~testo~~**", .bold) == "**~~testo~~**")
    #expect(MarkdownStylerFixture.styled("**~~testo~~**", .strikethrough) == "~~testo~~")
}

@Test func strikethroughNestedInsideItalicIsRecognizedAlongsideTheOuterItalicSpan() {
    #expect(MarkdownStylerFixture.styled("*~~testo~~*", .italic) == "*~~testo~~*")
    #expect(MarkdownStylerFixture.styled("*~~testo~~*", .strikethrough) == "~~testo~~")
}

// The reverse nesting: bold inside strikethrough. Not the ticket's literal example, but the
// same recursion mechanism handles it for free - including the nested run's own
// `.emphasisMarker` pair, since the recursive call re-triggers `inlineSpans`' own
// `characters[index] == "*"` guard on the inner slice's fresh `characters` array.
@Test func boldNestedInsideStrikethroughIsRecognizedWithItsOwnEmphasisMarkers() {
    #expect(MarkdownStylerFixture.styled("~~**testo**~~", .strikethrough) == "~~**testo**~~")
    #expect(MarkdownStylerFixture.styled("~~**testo**~~", .bold) == "**testo**")
    #expect(emphasisMarkers("~~**testo**~~") == ["**", "**"])
}

// A plain, non-nested run must render identically to before this fix: the inner slice
// contains no further markers, so the recursive call contributes nothing.
@Test func aNonNestedRunIsUnaffectedByTheRecursiveInnerScan() {
    #expect(MarkdownStylerFixture.styled("testo **grassetto** qui", .bold) == "**grassetto**")
    #expect(!MarkdownStylerFixture.spans("testo **grassetto** qui").contains(.strikethrough))
}

// Offset correctness: the outer match does not start at line position 0, so the recursion's
// `absolute` closure composition (outer offset + inner offset) must still land on the right
// `String.Index` range rather than one shifted by the leading text's length.
@Test func aNestedSpanPrecededByOtherTextResolvesToTheCorrectAbsoluteRange() {
    #expect(MarkdownStylerFixture.styled("prima **~~dopo~~** qui", .strikethrough) == "~~dopo~~")
    #expect(MarkdownStylerFixture.styled("prima **~~dopo~~** qui", .bold) == "**~~dopo~~**")
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
    #expect(MarkdownStylerFixture.styled(shellNote, .codeBlock)?.hasPrefix("```sh") == true)
    #expect(MarkdownStylerFixture.styled(shellNote, .codeBlock)?.hasSuffix("```") == true)
}

@Test func markdownStopsBeingMarkdownInsideAFence() {
    // The defect this slice closes, in one assertion per shape. The editor had never
    // known that a fence exists, so a shell comment was styled as a tag, a SQL or shell
    // `>date` as a scheduling marker, and a pair of wildcards as italics.
    let result = MarkdownStylerFixture.spans(shellNote)
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
    let result = MarkdownStylerFixture.spans(shellNote)
    #expect(result.contains(.tag("#topic-cli")))
    #expect(MarkdownStylerFixture.styled(shellNote, .italic) == "*corsivo*")
}

@Test func aHeadingInsideAFenceHasNoMarkerSpan() {
    // `# nota per #project-forno` is a shell comment inside the fence, not a heading -
    // the whole line is skipped by the per-line loop, so it gains no marker either.
    #expect(!MarkdownStylerFixture.spans(shellNote).contains(.headingMarker))
}

@Test func theGrammarReachesTheCodeInsideTheFence() {
    #expect(MarkdownStylerFixture.spans(shellNote).contains(.codeToken(.comment)))
    #expect(MarkdownStylerFixture.styled(shellNote, .codeToken(.string)) == "\"$HOME/Labs\"")
}

@Test func aWikilinkInsideAFenceIsNotClickable() {
    // An example of the syntax, not a link out of the note.
    let note = "```md\nvedi [[Altra nota]]\n```"
    #expect(MarkdownStylerFixture.styled(note, .linkTarget("Altra nota")) == nil)
    #expect(!MarkdownStylerFixture.spans(note).contains(.linkSyntax))
}

@Test func anUnclosedFenceEndsWithTheNoteAndSoDoesTheReadingView() {
    // Asserted on both parsers at once, because they are two traversals of one rule
    // (`CodeFence`) and the only thing keeping them together is that they agree here.
    // While someone types the opening backticks, every note is a note with an open fence.
    let note = "Prima.\n\n```swift\nlet a = 1"
    #expect(MarkdownStylerFixture.styled(note, .codeBlock) == "```swift\nlet a = 1")

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
    #expect(MarkdownStylerFixture.styled(note, .codeBlock) == note)
    #expect(!MarkdownStylerFixture.spans(note).contains { if case .codeToken = $0 { true } else { false } })
}

@Test func inlineCodeInProseIsUntouchedByAnyOfThis() {
    // A single backtick run is not a fence and never was; the fence work must not have
    // moved it.
    #expect(MarkdownStylerFixture.styled("usa `codice` inline", .code) == "`codice`")
    #expect(!MarkdownStylerFixture.spans("usa `codice` inline").contains(.codeBlock))
}
