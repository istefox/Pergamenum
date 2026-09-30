import Foundation
import Testing
@testable import Pergamenum

// MARK: - The embed run (ADR-0018, slice 3)

@Test func stylesAWikilinkEmbedAloneOnALine() {
    #expect(MarkdownStylerFixture.styled("![[foto.png]]", .embedRun) == "![[foto.png]]")
}

@Test func stylesACommonMarkEmbedAloneOnALine() {
    #expect(MarkdownStylerFixture.styled("![alt](foto.png)", .embedRun) == "![alt](foto.png)")
}

@Test func embedRunRangeExcludesIndentationAndTrailingSpace() {
    // Indentation is tolerated; the range reported is the embed's own characters, not
    // the row it sits on - trailing whitespace included, since nothing else on the row
    // needs to keep it.
    #expect(MarkdownStylerFixture.styled("  ![[foto.png]]  ", .embedRun) == "![[foto.png]]")
}

@Test func aBareWikilinkHasNoEmbedRunSpan() {
    // D4, the regression this slice must never reintroduce: `![[nota]]` with no
    // extension stays a transclusion, and a transclusion must never collapse the way
    // an image does.
    #expect(!MarkdownStylerFixture.spans("![[nota]]").contains(.embedRun))
}

@Test func anEmbedInsideASentenceHasNoEmbedRunSpan() {
    // Only a whole line is an embed - `Attachment.embed(inLine:)`'s own rule, which
    // `Transclusion.target(ofLine:)` inherits: a picture named inside a sentence stays
    // inline text, not something to collapse.
    #expect(!MarkdownStylerFixture.spans("vedi ![[foto.png]] qui sotto").contains(.embedRun))
}

@Test func anEmbedInsideAFenceHasNoEmbedRunSpan() {
    // Inside a fence, markdown is not markdown - the same exclusion `MarkdownStylerFixture.spans(in:)` already
    // applies to every other line-level span, and `embedRun(inLine:)` never sees a line
    // the per-line loop has skipped.
    let note = "```md\n![[foto.png]]\n```"
    #expect(!MarkdownStylerFixture.spans(note).contains(.embedRun))
}

@Test func aRemoteEmbedTargetHasNoEmbedRunSpan() {
    // The app makes no network call (principle 2, fully offline);
    // `Transclusion.target(ofLine:)` already drops a remote target before either
    // branch, so this never reaches `.file`.
    #expect(!MarkdownStylerFixture.spans("![[https://example.com/foto.png]]").contains(.embedRun))
    #expect(!MarkdownStylerFixture.spans("![alt](http://example.com/foto.png)").contains(.embedRun))
}

@Test func embedRunSuppressesSpellCheck() {
    // A file name is not prose to correct.
    #expect(MarkdownStyler.suppressesSpellCheck(.embedRun))
}

// MARK: - List markers (ADR-0028 §D1, §D2 - plan `2026-08-29-wysiwyg-markdown-in-workspace`, Task 1)

/// Whether any list marker, of any kind or level, is among a line's spans - used by the
/// negative assertions below, which do not care which level a false positive would claim.
private func hasAnyListMarker(_ line: String) -> Bool {
    MarkdownStylerFixture.spans(line).contains { if case .listMarker = $0 { true } else { false } }
}

@Test func stylesUnorderedListMarkersAtLevelOne() {
    // R-01. The styled text is the marker and its trailing space, character for
    // character - `-`, `*` and `+` are not normalised to one another.
    #expect(MarkdownStylerFixture.styled("- primo", .listMarker(kind: .bullet, level: 1)) == "- ")
    #expect(MarkdownStylerFixture.styled("* primo", .listMarker(kind: .bullet, level: 1)) == "* ")
    #expect(MarkdownStylerFixture.styled("+ primo", .listMarker(kind: .bullet, level: 1)) == "+ ")
}

@Test func stylesOrderedListMarkersAtLevelOne() {
    // R-01. Both delimiters (`.`/`)`) and multi-digit ordinals are recognised, and the
    // styled text keeps the digits and the delimiter exactly as written.
    #expect(MarkdownStylerFixture.styled("1. uno", .listMarker(kind: .ordered, level: 1)) == "1. ")
    #expect(MarkdownStylerFixture.styled("12. dodici", .listMarker(kind: .ordered, level: 1)) == "12. ")
    #expect(MarkdownStylerFixture.styled("12) dodici", .listMarker(kind: .ordered, level: 1)) == "12) ")
}

@Test func nestedListMarkersReportTheirIndentLevel() {
    // R-01, R-04: a child's level is measured against its parent's content column
    // (marker start + marker width + the mandatory space), not a fixed division of its
    // own indentation - so every case here supplies a real parent line to nest under.
    let twoSpaceChild = "- padre\n  - sotto"
    #expect(MarkdownStylerFixture.spans(twoSpaceChild).contains(.listMarker(kind: .bullet, level: 2)))

    // Four spaces is still >= the "- " parent's content column (2), so it nests at the
    // same depth a two-space child does - it is not a deeper level on its own.
    let fourSpaceChild = "- padre\n    - sotto"
    #expect(MarkdownStylerFixture.spans(fourSpaceChild).contains(.listMarker(kind: .bullet, level: 2)))

    // A tab counts as four columns, reaching the same content column a four-space child
    // does.
    let tabChild = "- padre\n\t- sotto"
    #expect(MarkdownStylerFixture.spans(tabChild).contains(.listMarker(kind: .bullet, level: 2)))

    // A genuinely three-deep chain - each line's own marker opens the content column the
    // next line nests under.
    let threeDeep = "- uno\n  - due\n    - tre"
    #expect(MarkdownStylerFixture.spans(threeDeep).contains(.listMarker(kind: .bullet, level: 3)))
}

@Test func aLoneIndentedListLineWithNoParentIsLevelOne() {
    // No preceding line means no open ancestor list to measure against - CommonMark's
    // content-column rule has nothing to compare indentation to, so an isolated indented
    // item is still level 1, however deep its own indentation. This replaces the old
    // fixed-column classifier's behavior of computing a level from indentation alone.
    #expect(MarkdownStylerFixture.spans("  - sotto").contains(.listMarker(kind: .bullet, level: 1)))
    #expect(MarkdownStylerFixture.spans("    - sotto").contains(.listMarker(kind: .bullet, level: 1)))
    #expect(MarkdownStylerFixture.spans("\t- sotto").contains(.listMarker(kind: .bullet, level: 1)))
    let twentySpaces = String(repeating: " ", count: 20)
    #expect(MarkdownStylerFixture.spans("\(twentySpaces)- sotto").contains(.listMarker(kind: .bullet, level: 1)))
}

@Test func deepIndentationIsCappedAtLevelSix() {
    // R-07: six genuinely nested levels, each indented two columns past its parent's
    // content column - a seventh would compute to level 7 uncapped; the classifier caps
    // it at 6.
    let sixDeep = (1...6)
        .map { String(repeating: "  ", count: $0 - 1) + "- n\($0)" }
        .joined(separator: "\n")
    #expect(MarkdownStylerFixture.spans(sixDeep).contains(.listMarker(kind: .bullet, level: 6)))

    let sevenDeep = sixDeep + "\n" + String(repeating: "  ", count: 6) + "- n7"
    #expect(MarkdownStylerFixture.spans(sevenDeep).contains(.listMarker(kind: .bullet, level: 6)))
}

@Test func orderedMarkersOfDifferentWidthProduceDifferentChildThresholds() {
    // R-05: CommonMark's content column depends on marker width, so a 3-space child does
    // NOT nest under an ordered parent whose marker is wide enough to push the content
    // column past 3 - it stays a level-1 sibling instead.
    let underWideOrdinal = "12. padre\n   - troppo vicino"
    #expect(MarkdownStylerFixture.spans(underWideOrdinal).contains(.listMarker(kind: .bullet, level: 1)))

    // The same three-space indent DOES nest under a narrow "- " parent (content column 2).
    let underBullet = "- padre\n   - sotto"
    #expect(MarkdownStylerFixture.spans(underBullet).contains(.listMarker(kind: .bullet, level: 2)))
}

@Test func spansTieBreakAttachesToTheDeepestListThatStillFits() {
    // R-06: an indentation strictly between two open lists' content columns attaches to
    // the deeper one still <= it. "- a" (content column 2) opens a child "- b" (indent 2,
    // content column 4); a third line indented 3 does not reach "- b"'s content column
    // (4) but does reach "- a"'s (2), so it nests as "- b"'s sibling, not as its child.
    let text = "- a\n  - b\n   - c"
    #expect(MarkdownStylerFixture.spans(text).contains(.listMarker(kind: .bullet, level: 2)))
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
        #expect(MarkdownStylerFixture.spans(line).contains(.taskMarker(state: state)))
    }
}

@Test func aListMarkerInsideAFenceHasNoListMarkerSpan() {
    // The fence filter that already keeps every other per-line span out of a fenced
    // block (`markdownStopsBeingMarkdownInsideAFence`, in `Tests/MarkdownStylerTests.swift`)
    // must also keep the new recogniser out - asserted so a future change to the fence
    // filter cannot regress this silently.
    let note = "```md\n- non è una lista qui\n```"
    #expect(!hasAnyListMarker(note))
}

@Test func listMarkerLevelsAreUnaffectedByFrontmatterAndAFenceAheadOfTheList() {
    // PG-139 (issue #239), Task 1: `ListNesting.levels(in:)` scans the whole note from
    // `text.startIndex`, frontmatter and fences included, exactly as the backward walk it
    // now precomputes for already did, one line at a time. This fixture puts a YAML list
    // inside the frontmatter and a list-looking line inside a fence ahead of a real nested
    // list, so a regression that let either leak an "open ancestor" past its own closing
    // `---`/fence boundary would show up as a wrong *level* below, not merely a spurious
    // styled marker (already guarded by `aListMarkerInsideAFenceHasNoListMarkerSpan` above).
    let note = """
    ---
    tags:
      - uno
      - due
    ---

    ```md
    - non è una lista qui
    ```

    - primo
      - secondo
        - terzo
    """
    let listMarkers = MarkdownStylerFixture.spans(note).filter { if case .listMarker = $0 { true } else { false } }
    #expect(
        listMarkers.count == 3,
        "the frontmatter's YAML list and the fenced list-looking line must not gain a styled marker"
    )
    #expect(listMarkers.contains(.listMarker(kind: .bullet, level: 1)))
    #expect(listMarkers.contains(.listMarker(kind: .bullet, level: 2)))
    #expect(listMarkers.contains(.listMarker(kind: .bullet, level: 3)))
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
    MarkdownStylerFixture.spans(text).contains { if case .blockquoteMarker = $0 { true } else { false } }
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
    #expect(MarkdownStylerFixture.styled(text, .blockquoteMarker(level: level)) == marker)
}

@Test func aBlockquoteMarkerWithNoTrailingSpaceIsStillRecognised() {
    // GFM allows the space after the last `>` to be omitted; the styled text is then the
    // `>`s alone, with nothing to include after them.
    #expect(MarkdownStylerFixture.styled(">>>senza spazio", .blockquoteMarker(level: 3)) == ">>>")
}

@Test(arguments: ["---", "- - -", "***", "___"])
func stylesAWholeThematicBreakLineAsOneHorizontalRule(rule: String) {
    #expect(MarkdownStylerFixture.styled(rule, .horizontalRule) == rule)
    #expect(MarkdownStylerFixture.spans(rule).filter { $0 == .horizontalRule }.count == 1)
}

@Test func twoCharactersIsNotEnoughForARule() {
    #expect(!MarkdownStylerFixture.spans("--").contains(.horizontalRule))
}

@Test func theFrontmatterDelimiterIsNeverAlsoAHorizontalRule() {
    // Regression guard: `MarkdownStylerFixture.spans(in:)` starts at `bodyStart`, so the opening/closing `---` of
    // a note's own frontmatter block must never double as a rule.
    let note = "---\ndate: 2026-08-11\n---\ncorpo"
    #expect(!MarkdownStylerFixture.spans(note).contains(.horizontalRule))
}

@Test func aStrikethroughRunYieldsTwoMarkersAndStillYieldsStrikethrough() {
    #expect(strikethroughMarkers("~~testo~~") == ["~~", "~~"])
    #expect(MarkdownStylerFixture.spans("~~testo~~").contains(.strikethrough))
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
    // the same exclusion `MarkdownStylerFixture.spans(in:)` already applies to every other per-line and per-note
    // span.
    let note = "```md\n> citazione\n---\n~~testo~~\n[testo](https://x.it)\n```"
    #expect(!hasAnyBlockquoteMarker(note))
    #expect(!MarkdownStylerFixture.spans(note).contains(.horizontalRule))
    #expect(strikethroughMarkers(note).isEmpty)
    #expect(!MarkdownStylerFixture.spans(note).contains(.linkSyntax))
}

@Test func theFourADR0029ConstructsSuppressSpellCheck() {
    // All four are syntax, never prose - the same shelf `.headingMarker`/`.emphasisMarker`/
    // `.listMarker` already occupy.
    #expect(MarkdownStyler.suppressesSpellCheck(.blockquoteMarker(level: 1)))
    #expect(MarkdownStyler.suppressesSpellCheck(.strikethroughMarker))
    #expect(MarkdownStyler.suppressesSpellCheck(.horizontalRule))
    #expect(MarkdownStyler.suppressesSpellCheck(.tableRun))
}

// MARK: - CRLF notes (PG-274)

@Test func stylesTheFrontmatterBlockOfACRLFNote() {
    let note = "---\r\ndate: 2026-08-11\r\n---\r\ncorpo"
    #expect(MarkdownStylerFixture.styled(note, .frontmatter) == "---\r\ndate: 2026-08-11\r\n---")
}

@Test func aCRLFNoteStylesItsHeadingsOnTheirOwnLines() {
    let lf = "# Uno\ntesto\n## Due\n"
    let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
    // Raw text on purpose: stripping the "\r" before comparing hid a span that carried it.
    let headings = { (text: String) in
        MarkdownStyler.spans(in: text).compactMap { match -> String? in
            if case .heading = match.span { return String(text[match.range]) }
            return nil
        }
    }
    #expect(headings(crlf) == ["# Uno", "## Due"])
    #expect(headings(crlf) == headings(lf))
    for match in MarkdownStyler.spans(in: crlf) {
        #expect(!crlf[match.range].contains("\r\n"), "a span carries its line break: \(match.span)")
        #expect(!crlf[match.range].unicodeScalars.contains("\r"), "a span carries a CR: \(match.span)")
    }
}

@Test func theFrontmatterRangeOfACRLFNoteMatchesItsLFTwin() {
    let lf = "---\ndate: 2026-08-11\ntags: []\n---\ncorpo\n---\naltro"
    let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
    // The block ends at the first closing rule, not the later one in the body.
    #expect(MarkdownStylerFixture.styled(lf, .frontmatter) == "---\ndate: 2026-08-11\ntags: []\n---")
    #expect(MarkdownStylerFixture.styled(crlf, .frontmatter) == "---\r\ndate: 2026-08-11\r\ntags: []\r\n---")
    // An empty block is still a block.
    #expect(MarkdownStylerFixture.styled("---\n---\ncorpo", .frontmatter) == "---\n---")
    #expect(MarkdownStylerFixture.styled("---\r\n---\r\ncorpo", .frontmatter) == "---\r\n---")
}

@Test func anUnclosedFrontmatterOpeningIsNoFrontmatterInEitherEnding() {
    let lf = "---\ndate: 2026-08-11\ncorpo senza chiusura\n"
    let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
    #expect(MarkdownStylerFixture.styled(lf, .frontmatter) == nil)
    #expect(MarkdownStylerFixture.styled(crlf, .frontmatter) == nil)
    // Nothing follows the opening rule at all.
    #expect(MarkdownStylerFixture.styled("---", .frontmatter) == nil)
    #expect(MarkdownStylerFixture.styled("---\r\n", .frontmatter) == nil)
}
