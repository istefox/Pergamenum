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

// MARK: - The heading marker (ADR-0018 §D1)

@Test func stylesTheHeadingMarkerSeparatelyFromTheHeadingSpan() {
    // Isolated from the heading span: the marker is its own range, not a slice reported
    // out of `.heading`'s.
    #expect(styled("# Titolo", .headingMarker) == "# ")
    #expect(styled("## Titolo", .headingMarker) == "## ")
}

@Test func theHeadingMarkerRangeIncludesExactlyOneTrailingSpace() {
    // Hashes plus the single space after them - not the extra spaces before the title.
    #expect(styled("#   Titolo", .headingMarker) == "# ")
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
    #expect(!spans("# ").contains(.headingMarker))
    #expect(!spans("#   ").contains(.headingMarker))
}

@Test func aTagIsNeverAHeadingMarker() {
    #expect(!spans("#type-note in apertura di riga").contains(.headingMarker))
}

@Test func headingMarkerRangeExcludesIndentation() {
    // Mirrors `indentedTaskMarkersKeepTheirPosition`: the marker's start is measured
    // from where the line's own content begins, not from column zero.
    #expect(styled("  # Titolo", .headingMarker) == "# ")
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
    #expect(spans("testo _corsivo_ qui").contains(.italic))
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
    #expect(!spans("vedi https://x.test/a#type-note").contains(.tag("#type-note")))
    #expect(spans("nota con #topic-acoustics dentro").contains(.tag("#topic-acoustics")))
}

@Test func doesNotStyleAMalformedTag() {
    // `#varie` has no namespace, so it is not a tag at all (T-01).
    #expect(!spans("testo #varie").contains { if case .tag = $0 { true } else { false } })
}

@Test func stylesTaskMarkers() {
    #expect(styled("- [ ] Da fare", .taskMarker(state: .open)) == "- [ ]")
    #expect(styled("- [x] Fatto", .taskMarker(state: .done)) == "- [x]")
    #expect(spans("- [>] Rimandato").contains(.taskMarker(state: .rescheduled)))
    #expect(spans("- [-] Annullato").contains(.taskMarker(state: .cancelled)))
}

@Test func indentedTaskMarkersKeepTheirPosition() {
    #expect(styled("    - [ ] Annidato", .taskMarker(state: .open)) == "- [ ]")
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

/// Issue #188 follow-up: a wikilink whose visible text was selected and made bold
/// (`[[**Prova**]]`, produced by the format bar/Cmd+B) used to carry `.linkTarget("**Prova**")`
/// - the URL/navigation this resolves to then looked for a note literally titled "**Prova**",
/// found none, and Cmd+click silently did nothing. The payload now resolves through the
/// wrapping markers to the actual note title, while the styled RANGE stays the full literal
/// source text (`**Prova**`, all 9 characters) so the visible bold run is what is clickable.
@Test func aWikilinkTargetWrappedInBoldStillResolvesToTheBareTitle() {
    let text = "vedi [[**Prova**]] qui"
    #expect(styled(text, .linkTarget("Prova")) == "**Prova**")
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

// MARK: PG-084 - recursive inline spans

// A matched `**...**` used to consume its entire range as one atomic `.bold` span, so a
// `~~...~~` nested inside it was invisible: rendered (and would conceal) only as bold, the
// `~~` markers left plain and unstyled. `inlineSpans` now recurses into a run's own inner
// content, so the nested span is emitted too.
@Test func strikethroughNestedInsideBoldIsRecognizedAlongsideTheOuterBoldSpan() {
    #expect(styled("**~~testo~~**", .bold) == "**~~testo~~**")
    #expect(styled("**~~testo~~**", .strikethrough) == "~~testo~~")
}

@Test func strikethroughNestedInsideItalicIsRecognizedAlongsideTheOuterItalicSpan() {
    #expect(styled("*~~testo~~*", .italic) == "*~~testo~~*")
    #expect(styled("*~~testo~~*", .strikethrough) == "~~testo~~")
}

// The reverse nesting: bold inside strikethrough. Not the ticket's literal example, but the
// same recursion mechanism handles it for free - including the nested run's own
// `.emphasisMarker` pair, since the recursive call re-triggers `inlineSpans`' own
// `characters[index] == "*"` guard on the inner slice's fresh `characters` array.
@Test func boldNestedInsideStrikethroughIsRecognizedWithItsOwnEmphasisMarkers() {
    #expect(styled("~~**testo**~~", .strikethrough) == "~~**testo**~~")
    #expect(styled("~~**testo**~~", .bold) == "**testo**")
    #expect(emphasisMarkers("~~**testo**~~") == ["**", "**"])
}

// A plain, non-nested run must render identically to before this fix: the inner slice
// contains no further markers, so the recursive call contributes nothing.
@Test func aNonNestedRunIsUnaffectedByTheRecursiveInnerScan() {
    #expect(styled("testo **grassetto** qui", .bold) == "**grassetto**")
    #expect(!spans("testo **grassetto** qui").contains(.strikethrough))
}

// Offset correctness: the outer match does not start at line position 0, so the recursion's
// `absolute` closure composition (outer offset + inner offset) must still land on the right
// `String.Index` range rather than one shifted by the leading text's length.
@Test func aNestedSpanPrecededByOtherTextResolvesToTheCorrectAbsoluteRange() {
    #expect(styled("prima **~~dopo~~** qui", .strikethrough) == "~~dopo~~")
    #expect(styled("prima **~~dopo~~** qui", .bold) == "**~~dopo~~**")
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

@Test func aHeadingInsideAFenceHasNoMarkerSpan() {
    // `# nota per #project-forno` is a shell comment inside the fence, not a heading -
    // the whole line is skipped by the per-line loop, so it gains no marker either.
    #expect(!spans(shellNote).contains(.headingMarker))
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

// MARK: - The embed run (ADR-0018, slice 3)

@Test func stylesAWikilinkEmbedAloneOnALine() {
    #expect(styled("![[foto.png]]", .embedRun) == "![[foto.png]]")
}

@Test func stylesACommonMarkEmbedAloneOnALine() {
    #expect(styled("![alt](foto.png)", .embedRun) == "![alt](foto.png)")
}

@Test func embedRunRangeExcludesIndentationAndTrailingSpace() {
    // Indentation is tolerated; the range reported is the embed's own characters, not
    // the row it sits on - trailing whitespace included, since nothing else on the row
    // needs to keep it.
    #expect(styled("  ![[foto.png]]  ", .embedRun) == "![[foto.png]]")
}

@Test func aBareWikilinkHasNoEmbedRunSpan() {
    // D4, the regression this slice must never reintroduce: `![[nota]]` with no
    // extension stays a transclusion, and a transclusion must never collapse the way
    // an image does.
    #expect(!spans("![[nota]]").contains(.embedRun))
}

@Test func anEmbedInsideASentenceHasNoEmbedRunSpan() {
    // Only a whole line is an embed - `Attachment.embed(inLine:)`'s own rule, which
    // `Transclusion.target(ofLine:)` inherits: a picture named inside a sentence stays
    // inline text, not something to collapse.
    #expect(!spans("vedi ![[foto.png]] qui sotto").contains(.embedRun))
}

@Test func anEmbedInsideAFenceHasNoEmbedRunSpan() {
    // Inside a fence, markdown is not markdown - the same exclusion `spans(in:)` already
    // applies to every other line-level span, and `embedRun(inLine:)` never sees a line
    // the per-line loop has skipped.
    let note = "```md\n![[foto.png]]\n```"
    #expect(!spans(note).contains(.embedRun))
}

@Test func aRemoteEmbedTargetHasNoEmbedRunSpan() {
    // The app makes no network call (principle 2, fully offline);
    // `Transclusion.target(ofLine:)` already drops a remote target before either
    // branch, so this never reaches `.file`.
    #expect(!spans("![[https://example.com/foto.png]]").contains(.embedRun))
    #expect(!spans("![alt](http://example.com/foto.png)").contains(.embedRun))
}

@Test func embedRunSuppressesSpellCheck() {
    // A file name is not prose to correct.
    #expect(MarkdownStyler.suppressesSpellCheck(.embedRun))
}

// MARK: - List markers (ADR-0028 §D1, §D2 - plan `2026-08-29-wysiwyg-markdown-in-workspace`, Task 1)

/// Whether any list marker, of any kind or level, is among a line's spans - used by the
/// negative assertions below, which do not care which level a false positive would claim.
private func hasAnyListMarker(_ line: String) -> Bool {
    spans(line).contains { if case .listMarker = $0 { true } else { false } }
}

@Test func stylesUnorderedListMarkersAtLevelOne() {
    // R-01. The styled text is the marker and its trailing space, character for
    // character - `-`, `*` and `+` are not normalised to one another.
    #expect(styled("- primo", .listMarker(kind: .bullet, level: 1)) == "- ")
    #expect(styled("* primo", .listMarker(kind: .bullet, level: 1)) == "* ")
    #expect(styled("+ primo", .listMarker(kind: .bullet, level: 1)) == "+ ")
}

@Test func stylesOrderedListMarkersAtLevelOne() {
    // R-01. Both delimiters (`.`/`)`) and multi-digit ordinals are recognised, and the
    // styled text keeps the digits and the delimiter exactly as written.
    #expect(styled("1. uno", .listMarker(kind: .ordered, level: 1)) == "1. ")
    #expect(styled("12. dodici", .listMarker(kind: .ordered, level: 1)) == "12. ")
    #expect(styled("12) dodici", .listMarker(kind: .ordered, level: 1)) == "12) ")
}

@Test func nestedListMarkersReportTheirIndentLevel() {
    // R-01, R-04: a child's level is measured against its parent's content column
    // (marker start + marker width + the mandatory space), not a fixed division of its
    // own indentation - so every case here supplies a real parent line to nest under.
    let twoSpaceChild = "- padre\n  - sotto"
    #expect(spans(twoSpaceChild).contains(.listMarker(kind: .bullet, level: 2)))

    // Four spaces is still >= the "- " parent's content column (2), so it nests at the
    // same depth a two-space child does - it is not a deeper level on its own.
    let fourSpaceChild = "- padre\n    - sotto"
    #expect(spans(fourSpaceChild).contains(.listMarker(kind: .bullet, level: 2)))

    // A tab counts as four columns, reaching the same content column a four-space child
    // does.
    let tabChild = "- padre\n\t- sotto"
    #expect(spans(tabChild).contains(.listMarker(kind: .bullet, level: 2)))

    // A genuinely three-deep chain - each line's own marker opens the content column the
    // next line nests under.
    let threeDeep = "- uno\n  - due\n    - tre"
    #expect(spans(threeDeep).contains(.listMarker(kind: .bullet, level: 3)))
}

@Test func aLoneIndentedListLineWithNoParentIsLevelOne() {
    // No preceding line means no open ancestor list to measure against - CommonMark's
    // content-column rule has nothing to compare indentation to, so an isolated indented
    // item is still level 1, however deep its own indentation. This replaces the old
    // fixed-column classifier's behavior of computing a level from indentation alone.
    #expect(spans("  - sotto").contains(.listMarker(kind: .bullet, level: 1)))
    #expect(spans("    - sotto").contains(.listMarker(kind: .bullet, level: 1)))
    #expect(spans("\t- sotto").contains(.listMarker(kind: .bullet, level: 1)))
    let twentySpaces = String(repeating: " ", count: 20)
    #expect(spans("\(twentySpaces)- sotto").contains(.listMarker(kind: .bullet, level: 1)))
}

@Test func deepIndentationIsCappedAtLevelSix() {
    // R-07: six genuinely nested levels, each indented two columns past its parent's
    // content column - a seventh would compute to level 7 uncapped; the classifier caps
    // it at 6.
    let sixDeep = (1...6)
        .map { String(repeating: "  ", count: $0 - 1) + "- n\($0)" }
        .joined(separator: "\n")
    #expect(spans(sixDeep).contains(.listMarker(kind: .bullet, level: 6)))

    let sevenDeep = sixDeep + "\n" + String(repeating: "  ", count: 6) + "- n7"
    #expect(spans(sevenDeep).contains(.listMarker(kind: .bullet, level: 6)))
}

@Test func orderedMarkersOfDifferentWidthProduceDifferentChildThresholds() {
    // R-05: CommonMark's content column depends on marker width, so a 3-space child does
    // NOT nest under an ordered parent whose marker is wide enough to push the content
    // column past 3 - it stays a level-1 sibling instead.
    let underWideOrdinal = "12. padre\n   - troppo vicino"
    #expect(spans(underWideOrdinal).contains(.listMarker(kind: .bullet, level: 1)))

    // The same three-space indent DOES nest under a narrow "- " parent (content column 2).
    let underBullet = "- padre\n   - sotto"
    #expect(spans(underBullet).contains(.listMarker(kind: .bullet, level: 2)))
}

@Test func spansTieBreakAttachesToTheDeepestListThatStillFits() {
    // R-06: an indentation strictly between two open lists' content columns attaches to
    // the deeper one still <= it. "- a" (content column 2) opens a child "- b" (indent 2,
    // content column 4); a third line indented 3 does not reach "- b"'s content column
    // (4) but does reach "- a"'s (2), so it nests as "- b"'s sibling, not as its child.
    let text = "- a\n  - b\n   - c"
    #expect(spans(text).contains(.listMarker(kind: .bullet, level: 2)))
}

@Test func aCheckboxLineHasNoListMarkerSpanButKeepsItsTaskMarker() {
    // The R-06 guard, asserted both ways: a checkbox line is not a list line (ADR-0028
    // §D2), so it must gain no list span at all, and it must keep exactly the
    // `.taskMarker` span it already had - nothing about today's checkbox rendering
    // may change.
    let checkboxLines: [(line: String, state: TaskItem.State)] = [
        ("- [ ] Da fare", .open),
        ("- [x] Fatto", .done),
        ("- [>] Rimandato", .rescheduled),
        ("- [-] Annullato", .cancelled),
        ("    - [ ] Annidato", .open),
    ]
    for (line, state) in checkboxLines {
        #expect(!hasAnyListMarker(line), "\"\(line)\" must not yield a list marker span")
        #expect(spans(line).contains(.taskMarker(state: state)))
    }
}

@Test func aListMarkerInsideAFenceHasNoListMarkerSpan() {
    // The fence filter that already keeps every other per-line span out of a fenced
    // block (`markdownStopsBeingMarkdownInsideAFence` above) must also keep the new
    // recogniser out - asserted so a future change to the fence filter cannot regress
    // this silently.
    let note = "```md\n- non è una lista qui\n```"
    #expect(!hasAnyListMarker(note))
}

@Test func aMarkerWithNoTrailingSpaceIsNotAListMarker() {
    // A marker needs its trailing space: a lone dash, a dash immediately followed by a
    // letter, and an ordered marker with no space or no text after it are all plain text.
    for line in ["-", "-nodash", "1.no-space", "1."] {
        #expect(!hasAnyListMarker(line), "\"\(line)\" must not yield a list marker span")
    }
}

@Test func listMarkerSuppressesSpellCheck() {
    #expect(MarkdownStyler.suppressesSpellCheck(.listMarker(kind: .bullet, level: 1)))
}

// MARK: - ADR-0029 (plan 2026-09-02-editor-wysiwyg-unification, Task 1) -
// blockquote, strikethrough marker, horizontal rule, CommonMark link syntax

/// Whether `text` yields a `.blockquoteMarker`/`.strikethroughMarker`/`.horizontalRule`/
/// `.linkSyntax` span at all - used by the fence and negative assertions below, which do
/// not care about the exact level or range a false positive would claim.
private func hasAnyBlockquoteMarker(_ text: String) -> Bool {
    spans(text).contains { if case .blockquoteMarker = $0 { true } else { false } }
}

private func strikethroughMarkers(_ text: String) -> [String] {
    MarkdownStyler.spans(in: text)
        .filter { $0.span == .strikethroughMarker }
        .map { String(text[$0.range]) }
}

@Test(arguments: [
    (">", "citazione", 1, "> "),
    (">>", "due", 2, ">> "),
    (">>>>", "quattro", 4, ">>>> "),
])
func stylesBlockquoteMarkersAtAnyLevelUnbounded(prefix: String, rest: String, level: Int, marker: String) {
    // R-03: unbounded nesting - no cap the way `.listMarker`'s level is capped at 6, and
    // level 4 here is deliberately past `.headingMarker`'s own six-hash ceiling to show the
    // two are unrelated limits.
    let text = "\(prefix) \(rest)"
    #expect(styled(text, .blockquoteMarker(level: level)) == marker)
}

@Test func aBlockquoteMarkerWithNoTrailingSpaceIsStillRecognised() {
    // GFM allows the space after the last `>` to be omitted; the styled text is then the
    // `>`s alone, with nothing to include after them.
    #expect(styled(">>>senza spazio", .blockquoteMarker(level: 3)) == ">>>")
}

@Test(arguments: ["---", "- - -", "***", "___"])
func stylesAWholeThematicBreakLineAsOneHorizontalRule(rule: String) {
    #expect(styled(rule, .horizontalRule) == rule)
    #expect(spans(rule).filter { $0 == .horizontalRule }.count == 1)
}

@Test func twoCharactersIsNotEnoughForARule() {
    #expect(!spans("--").contains(.horizontalRule))
}

@Test func theFrontmatterDelimiterIsNeverAlsoAHorizontalRule() {
    // Regression guard: `spans(in:)` starts at `bodyStart`, so the opening/closing `---` of
    // a note's own frontmatter block must never double as a rule.
    let note = "---\ndate: 2026-08-11\n---\ncorpo"
    #expect(!spans(note).contains(.horizontalRule))
}

@Test func aStrikethroughRunYieldsTwoMarkersAndStillYieldsStrikethrough() {
    #expect(strikethroughMarkers("~~testo~~") == ["~~", "~~"])
    #expect(spans("~~testo~~").contains(.strikethrough))
}

@Test func anEmptyStrikethroughRunHasNoMarkerSpan() {
    // The `emphasisMarkers` guard's twin: hiding an empty run's delimiters would collapse
    // it to nothing.
    #expect(strikethroughMarkers("~~~~").isEmpty)
}

@Test func stylesACommonMarkLinkSyntaxSeparatelyFromItsLabel() {
    // Reuses the existing `.linkSyntax` case (ADR §D1) rather than adding a new one for the
    // delimiters - the opening bracket and the `](url)` tail are each their own span. The
    // label itself now carries a `.linkTarget` span of its own (issue #188, R-03/R-04): the
    // same case a wikilink's target already uses, carrying the raw href rather than a note
    // title - `MarkdownAttributedText.targetURL(for:)` is what tells the two apart.
    let text = "[testo](https://x.it)"
    let spansIn = MarkdownStyler.spans(in: text)
    let linkSyntaxRanges = spansIn
        .filter { $0.span == .linkSyntax }
        .map { String(text[$0.range]) }
    #expect(Set(linkSyntaxRanges) == Set(["[", "](https://x.it)"]))
    #expect(!linkSyntaxRanges.contains("testo"))

    let linkTargetSpans = spansIn.filter {
        if case .linkTarget = $0.span { return true }
        return false
    }
    #expect(linkTargetSpans.count == 1)
    #expect(linkTargetSpans.first.map { String(text[$0.range]) } == "testo")
    #expect(linkTargetSpans.first?.span == .linkTarget("https://x.it"))
}

@Test func aCommonMarkLinkWithAnEmptyHrefGetsNoLinkTargetSpan() {
    // `[testo]()` - the empty-target guard in `markdownLinkSpans`, the same shape as the
    // `****`/`~~~~` empty-run guards elsewhere in this file.
    let text = "[testo]()"
    let hasLinkTarget = MarkdownStyler.spans(in: text).contains {
        if case .linkTarget = $0.span { return true }
        return false
    }
    #expect(!hasLinkTarget)
}

@Test func everyADR0029ConstructInsideAFenceYieldsNoneOfItsSpans() {
    // R-09's sibling for the four new constructs: inside a fence, markdown is not markdown,
    // the same exclusion `spans(in:)` already applies to every other per-line and per-note
    // span.
    let note = "```md\n> citazione\n---\n~~testo~~\n[testo](https://x.it)\n```"
    #expect(!hasAnyBlockquoteMarker(note))
    #expect(!spans(note).contains(.horizontalRule))
    #expect(strikethroughMarkers(note).isEmpty)
    #expect(!spans(note).contains(.linkSyntax))
}

@Test func theFourADR0029ConstructsSuppressSpellCheck() {
    // All four are syntax, never prose - the same shelf `.headingMarker`/`.emphasisMarker`/
    // `.listMarker` already occupy.
    #expect(MarkdownStyler.suppressesSpellCheck(.blockquoteMarker(level: 1)))
    #expect(MarkdownStyler.suppressesSpellCheck(.strikethroughMarker))
    #expect(MarkdownStyler.suppressesSpellCheck(.horizontalRule))
    #expect(MarkdownStyler.suppressesSpellCheck(.tableRun))
}
