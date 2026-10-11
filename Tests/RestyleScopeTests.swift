import Foundation
import Testing
@testable import Pergamenum

// ADR-0091 §D2 and §D3, plan docs/plans/per-paragraph-restyle.md, Task 1 (R-04).
//
// One named case per SPEC edge case, each asserting the decision `RestyleScope` takes for one edit: a
// full restyle with its reason, or the lines to restyle. The table asserted is ADR-0091 §D3's, in its
// order: frontmatter, fence lines, fence bodies, tables, lists, wikilink tokens, wikilink pending, and
// everything else as the edited lines.
//
// A `.lines` range is asserted without its last line terminator, because the ADR aligns the range
// to styler lines and does not say whether the "\n" that ends the last one is in it. Every other
// bound is exact. Red until Task 2 gives the placeholders their bodies.

// MARK: - Helpers

private struct Outcome {
    var decision: RestyleScope.Decision?
    var text: String
    var scope: RestyleScope
}

private func nsRange(of needle: String, in text: String) -> NSRange {
    let found = (text as NSString).range(of: needle)
    // A missing needle is a defect in the test, reported as an issue: a trap would end the whole run.
    guard found.location != NSNotFound else {
        Issue.record("\(needle.debugDescription) is not in \(text.debugDescription)")
        return NSRange(location: 0, length: 0)
    }
    return found
}

/// An edit as a text storage reports it, applied to `old` and recorded on a scope built from `old`.
private func decide(_ old: String, replacing range: NSRange, with replacement: String) -> Outcome {
    var scope = RestyleScope(text: old)
    let new = (old as NSString).replacingCharacters(in: range, with: replacement)
    let length = (replacement as NSString).length
    scope.record(
        StorageEdit(range: NSRange(location: range.location, length: length), delta: length - range.length),
        in: new as NSString
    )
    return Outcome(decision: scope.take(), text: new, scope: scope)
}

/// Inserts `replacement` right after the first `needle`.
private func decide(_ old: String, inserting replacement: String, after needle: String) -> Outcome {
    let found = nsRange(of: needle, in: old)
    return decide(old, replacing: NSRange(location: NSMaxRange(found), length: 0), with: replacement)
}

/// `range` without the one line terminator it may end with ("\n" or "\r\n").
private func withoutTerminator(_ range: NSRange, in text: String) -> NSRange {
    let units = Array(text.utf16)
    var end = NSMaxRange(range)
    if end > range.location, end <= units.count, units[end - 1] == 10 {
        end -= 1
        if end > range.location, units[end - 1] == 13 { end -= 1 }
    }
    return NSRange(location: range.location, length: end - range.location)
}

/// The styler line holding `location`, without its terminator: a line ends at "\n" or "\r\n" only.
private func stylerLine(at location: Int, in text: String) -> NSRange {
    let units = Array(text.utf16)
    var start = min(location, units.count)
    while start > 0, units[start - 1] != 10 { start -= 1 }
    var end = min(location, units.count)
    while end < units.count, units[end] != 10 { end += 1 }
    if end < units.count, end > start, units[end - 1] == 13 { end -= 1 }
    return NSRange(location: start, length: end - start)
}

/// From the start of the line holding `first` to the end of the line holding `last`.
private func block(from first: String, to last: String, in text: String) -> NSRange {
    let head = stylerLine(at: nsRange(of: first, in: text).location, in: text)
    let tail = stylerLine(at: nsRange(of: last, in: text).location, in: text)
    return NSRange(location: head.location, length: NSMaxRange(tail) - head.location)
}

private func line(containing needle: String, in text: String) -> NSRange {
    stylerLine(at: nsRange(of: needle, in: text).location, in: text)
}

private func describe(_ outcome: Outcome) -> String {
    "decision \(String(describing: outcome.decision)) for \(outcome.text.debugDescription)"
}

/// The `.lines` range, less its last terminator, or nil for anything else.
private func linesRange(_ outcome: Outcome) -> NSRange? {
    guard case .lines(let range)? = outcome.decision else { return nil }
    return withoutTerminator(range, in: outcome.text)
}

private func expectFull(
    _ reason: RestyleScope.Reason, _ outcome: Outcome, sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(outcome.decision == .full(reason), "\(describe(outcome))", sourceLocation: sourceLocation)
}

private func expectLines(
    _ expected: NSRange, _ outcome: Outcome, sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(linesRange(outcome) == expected, "expected \(expected): \(describe(outcome))", sourceLocation: sourceLocation)
}

// MARK: - Fences: opened, closed, and their lines (full restyle)

// (R-04) Typing the third backtick of an opening fence.
@Test func typingTheThirdBacktickOfAnOpeningFenceIsAFullRestyle() {
    expectFull(.fenceLine, decide("intro\n``\nbody\nend", inserting: "`", after: "``"))
}

// (R-04) Typing the third backtick of a closing fence.
@Test func typingTheThirdBacktickOfAClosingFenceIsAFullRestyle() {
    expectFull(.fenceLine, decide("intro\n```swift\nbody\n``\nend", inserting: "`", after: "body\n``"))
}

// (R-04) The `~~~` fence is a fence line too: `WikilinkParser.codeRanges` treats it as one.
@Test func typingTheThirdTildeOfATildeFenceIsAFullRestyle() {
    expectFull(.fenceLine, decide("intro\n~~\nbody\nend", inserting: "~", after: "~~"))
}

// (R-04) A fence line that stops being one: the old line carried the mark.
@Test func deletingABacktickOffAFenceLineIsAFullRestyle() {
    let old = "intro\n```\nbody\n```\nend"
    expectFull(.fenceLine, decide(old, replacing: NSRange(location: 6, length: 1), with: ""))
}

// (R-04) A `pergamenum-view` fence line is a fence line.
@Test func editingAViewBlockFenceLineIsAFullRestyle() {
    expectFull(.fenceLine, decide("intro\n```pergamenum-view\nselect: x\n```\nend", inserting: "x", after: "pergamenum-view"))
}

// MARK: - Fence bodies (widen to the region)

// (R-04) An edit in a closed fence's body restyles the whole region, opening line to closing line.
@Test func anEditInsideAClosedFenceBodyWidensToTheRegion() {
    let outcome = decide("pre\n```swift\nlet a = 1\nlet b = 2\n```\npost", inserting: "0", after: "let a = 1")
    expectLines(block(from: "```swift", to: "```\npost", in: outcome.text), outcome)
}

// (R-04) An unclosed fence runs to the end of the note.
@Test func anEditInsideAnUnclosedFenceBodyWidensToTheEndOfTheNote() {
    let outcome = decide("pre\n```swift\nlet a = 1\nlet b = 2", inserting: "0", after: "let a = 1")
    let length = (outcome.text as NSString).length
    let start = nsRange(of: "```swift", in: outcome.text).location
    expectLines(NSRange(location: start, length: length - start), outcome)
}

// (R-04) A view block is a fence: its body edit widens to the whole fence, not to the note.
@Test func anEditInsideAViewBlockBodyWidensToTheWholeFence() {
    let outcome = decide("pre\n```pergamenum-view\nselect: x\n```\npost", inserting: "y", after: "select: x")
    expectLines(block(from: "```pergamenum-view", to: "```\npost", in: outcome.text), outcome)
}

// MARK: - Frontmatter (full restyle)

private let withFrontmatter = "---\ntitle: a\ntags: []\n---\nbody text\nsecond line"

// (R-04) An edit inside the block.
@Test func anEditInsideFrontmatterIsAFullRestyle() {
    expectFull(.frontmatter, decide(withFrontmatter, inserting: "x", after: "title: "))
}

// (R-04) The closing line itself.
@Test func anEditToTheClosingFrontmatterLineIsAFullRestyle() {
    expectFull(.frontmatter, decide(withFrontmatter, inserting: "-", after: "tags: []\n---"))
}

// (R-04) `---` typed at offset 0 of a note without frontmatter makes the first line start with it.
@Test func typingTheRuleAtOffsetZeroIsAFullRestyle() {
    expectFull(.frontmatter, decide("titolo\nbody", replacing: NSRange(location: 0, length: 0), with: "---"))
}

// (R-04) A leading U+FEFF is allowed before the opening `---`.
@Test func typingTheRuleAfterALeadingByteOrderMarkIsAFullRestyle() {
    expectFull(.frontmatter, decide("\u{FEFF}titolo\nbody", replacing: NSRange(location: 1, length: 0), with: "---"))
}

// (R-04) And an edit inside a block that opens after one.
@Test func anEditInsideFrontmatterThatOpensAfterAByteOrderMarkIsAFullRestyle() {
    expectFull(.frontmatter, decide("\u{FEFF}---\ntitle: a\n---\nbody", inserting: "x", after: "title: "))
}

// (R-04) A deleted closing line turns the whole note into the block.
@Test func aDeletedClosingFrontmatterLineIsAFullRestyle() {
    let old = "---\ntitle: a\n---\nbody"
    let closing = NSRange(location: 13, length: 4)
    #expect((old as NSString).substring(with: closing) == "---\n")
    expectFull(.frontmatter, decide(old, replacing: closing, with: ""))
}

// (R-04) Non-vacuity of the rules above: an edit in the body after the block is local. The second body
// line, because the ADR does not say whether the line right after the closing `---` is inside the zone.
@Test func anEditInTheBodyAfterFrontmatterIsLocal() {
    let outcome = decide(withFrontmatter, inserting: "x", after: "second")
    expectLines(line(containing: "secondx line", in: outcome.text), outcome)
}

// MARK: - Tables (widen over the run of table-capable lines)

private let tableNote = "intro\n\n| a | b |\n| - | - |\n| 1 | 2 |\n\noutro"

// (R-04) A header cell.
@Test func anEditInATableHeaderWidensToTheTable() {
    let outcome = decide(tableNote, inserting: "x", after: "| a")
    expectLines(block(from: "| ax | b |", to: "| 1 | 2 |", in: outcome.text), outcome)
}

// (R-04) A body cell.
@Test func anEditInATableBodyRowWidensToTheTable() {
    let outcome = decide(tableNote, inserting: "0", after: "| 1")
    expectLines(block(from: "| a | b |", to: "| 10 | 2 |", in: outcome.text), outcome)
}

// (R-04) The delimiter row.
@Test func anEditToTheDelimiterRowWidensToTheTable() {
    let outcome = decide(tableNote, inserting: "-", after: "| -")
    expectLines(block(from: "| a | b |", to: "| 1 | 2 |", in: outcome.text), outcome)
}

// (R-04) A run of table-capable lines that holds a fence mark is a full restyle with its own reason,
// not the fence-line one: the edit touched no fence line, the run it widens over does.
@Test func aTableRunHoldingAFenceMarkIsAFullRestyle() {
    let old = "intro\n\n| a | b |\n| - | - |\n```x | y |\n\nend"
    expectFull(.tableFence, decide(old, inserting: "x", after: "| a"))
}

// (R-04) A pipe-less delimiter row makes a `| a |` header a table: the typed line is table-capable in
// the new text only, and the header just before it is.
@Test func aPipelessDelimiterRowWidensToTheHeaderBeforeIt() {
    let old = "intro\n\n| a |\nabc\n\nend"
    let found = nsRange(of: "abc", in: old)
    let outcome = decide(old, replacing: found, with: "---")
    expectLines(block(from: "| a |", to: "---", in: outcome.text), outcome)
}

// (R-04) A row emptied splits the run in two: the widening covers both halves, because the line it
// touches is table-capable in the old text and its neighbours are table-capable in the new one.
@Test func blankingARowThatSplitsATableWidensOverBothHalves() {
    let old = "intro\n| a | b |\n| - | - |\n| 1 | 2 |\n| 3 | 4 |\nfine"
    let outcome = decide(old, replacing: nsRange(of: "| 1 | 2 |", in: old), with: "")
    expectLines(block(from: "| a | b |", to: "| 3 | 4 |", in: outcome.text), outcome)
}

// (R-04) A row typed into the blank line between two runs joins them.
@Test func fillingTheBlankLineBetweenTwoRunsWidensOverBoth() {
    let old = "intro\n| a | b |\n| - | - |\n\n| 3 | 4 |\nfine"
    let blank = nsRange(of: "| - | - |\n\n", in: old)
    let outcome = decide(
        old, replacing: NSRange(location: blank.location + 10, length: 0), with: "| 1 | 2 |"
    )
    expectLines(block(from: "| a | b |", to: "| 3 | 4 |", in: outcome.text), outcome)
}

// MARK: - Lists (widen until the stacks converge, a reset stops the walk)

// (R-04) Indenting an item changes the stack after it; the next line brings both stacks together.
@Test func aListIndentChangeWidensUntilTheStacksConverge() {
    let old = "- a\n- b\n  - c\n  - d\n- e"
    let outcome = decide(old, replacing: NSRange(location: nsRange(of: "- b", in: old).location, length: 0), with: "  ")
    expectLines(block(from: "  - b", to: "  - c", in: outcome.text), outcome)
}

// (R-04) An edit that leaves the stacks as they were widens nothing.
@Test func aListEditThatKeepsTheStackIsTheEditedLine() {
    let old = "- a\n- b\n  - c"
    let outcome = decide(old, inserting: "x", after: "- b")
    expectLines(line(containing: "- bx", in: outcome.text), outcome)
}

// (R-04) Dedenting an item changes every stack below it, until a line at column 0 that is no list line
// clears both: the widening ends there at the latest, and never reaches the next list.
@Test func aResetLineStopsTheListWidening() {
    let old = "- a\n  - b\n    - c\n      - d\nparagrafo\n- e"
    let outcome = decide(old, replacing: NSRange(location: nsRange(of: "  - b", in: old).location, length: 2), with: "")
    let range = linesRange(outcome)
    let start = line(containing: "- b", in: outcome.text).location
    let endOfD = NSMaxRange(line(containing: "- d", in: outcome.text))
    let endOfReset = NSMaxRange(line(containing: "paragrafo", in: outcome.text))
    #expect(range?.location == start, "\(describe(outcome))")
    #expect((range.map(NSMaxRange) ?? 0) >= endOfD, "\(describe(outcome))")
    #expect((range.map(NSMaxRange) ?? Int.max) <= endOfReset, "\(describe(outcome))")
}

// MARK: - Blockquote (line-local)

// (R-04) ADR-0091 §D3: nothing joins two quote lines, so a line that becomes a quote is a local change.
@Test func aLineThatBecomesAQuoteStaysLocal() {
    let old = "uno\ndue\ntre"
    let outcome = decide(old, replacing: NSRange(location: nsRange(of: "due", in: old).location, length: 0), with: "> ")
    expectLines(line(containing: "> due", in: outcome.text), outcome)
}

// (R-04) And a line that stops being one.
@Test func aLineThatStopsBeingAQuoteStaysLocal() {
    let old = "uno\n> due\ntre"
    let outcome = decide(old, replacing: nsRange(of: "> ", in: old), with: "")
    expectLines(line(containing: "due", in: outcome.text), outcome)
}

// MARK: - Wikilinks

// (R-04) Typing the second `[`.
@Test func typingAnOpeningBracketPairIsAFullRestyle() {
    expectFull(.wikilinkTokens, decide("a [ b\nc", inserting: "[", after: "a ["))
}

// (R-04) Typing `]]`.
@Test func typingAClosingBracketPairIsAFullRestyle() {
    expectFull(.wikilinkTokens, decide("a [[b\nc", inserting: "]]", after: "[[b"))
}

// (R-04) Deleting one `]` of a link.
@Test func deletingABracketOfALinkIsAFullRestyle() {
    let old = "see [[nota]] qui\nfine"
    expectFull(.wikilinkTokens, decide(old, replacing: NSRange(location: nsRange(of: "]]", in: old).location, length: 1), with: ""))
}

// (R-04) Deleting `[[`.
@Test func deletingAnOpeningPairIsAFullRestyle() {
    let old = "see [[nota]] qui\nfine"
    expectFull(.wikilinkTokens, decide(old, replacing: nsRange(of: "[[", in: old), with: ""))
}

// (R-04) An edit near a link that leaves its tokens as they were is local.
@Test func anEditNextToACompleteLinkIsLocal() {
    let outcome = decide("a [[b]] c\nfine", inserting: "x", after: " c")
    expectLines(line(containing: "c" + "x", in: outcome.text), outcome)
}

// (R-04) A `[[` above with a `]]` below pairs across the edited line, which no signature of it shows.
@Test func aPendingOpenerWithALaterCloserIsAFullRestyle() {
    expectFull(.wikilinkPending, decide("start [[open\nmiddle line\nend ]] tail", inserting: "x", after: "middle"))
}

// (R-04) No `]]` after the opener: nothing pairs.
@Test func anOpenerWithNoCloserAfterItIsLocal() {
    let outcome = decide("start [[open\nmiddle line\nend", inserting: "x", after: "middle")
    expectLines(line(containing: "middlex", in: outcome.text), outcome)
}

// (R-04) An opener in an inline code span is no opener, as `WikilinkParser.codeRanges` reads it.
@Test func anOpenerInsideInlineCodeIsIgnored() {
    let outcome = decide("`[[` x\nmiddle\n]] y", inserting: "x", after: "middle")
    expectLines(line(containing: "middlex", in: outcome.text), outcome)
}

// (R-04) A link closed before the edited line pairs nothing across it.
@Test func aClosedLinkAboveTheEditIsLocal() {
    let outcome = decide("a [[x]] b\nmiddle\nc", inserting: "y", after: "middle")
    expectLines(line(containing: "middley", in: outcome.text), outcome)
}

// MARK: - Plain prose, line endings, wholesale replaces

// (R-04) Plain prose is the edited line and nothing else.
@Test func plainProseIsTheEditedLine() {
    let outcome = decide("alpha\nbeta\ngamma", inserting: "x", after: "bet")
    expectLines(line(containing: "betxa", in: outcome.text), outcome)
}

// (R-04) The first line, edited at offset 0.
@Test func anEditAtOffsetZeroIsTheFirstLine() {
    let outcome = decide("alpha\nbeta\ngamma", replacing: NSRange(location: 0, length: 0), with: "x")
    expectLines(line(containing: "xalpha", in: outcome.text), outcome)
}

// (R-04) The last line, edited at the end of the note.
@Test func anEditAtTheEndOfTheNoteIsTheLastLine() {
    let old = "alpha\nbeta\ngamma"
    let outcome = decide(old, replacing: NSRange(location: (old as NSString).length, length: 0), with: "!")
    expectLines(line(containing: "gamma!", in: outcome.text), outcome)
}

// (R-04) A paste of several lines is the lines it covers.
@Test func aMultiLinePasteIsTheLinesItCovers() {
    let old = "alpha\nbeta\ngamma\ndelta"
    let outcome = decide(old, replacing: nsRange(of: "beta", in: old), with: "be\nta\nsomething")
    expectLines(block(from: "be\n", to: "something", in: outcome.text), outcome)
}

// (R-04) A CRLF line is one line, and the range never splits its "\r\n".
@Test func aCRLFLineIsTheEditedLine() {
    let outcome = decide("alpha\r\nbeta\r\ngamma", inserting: "x", after: "bet")
    expectLines(line(containing: "betxa", in: outcome.text), outcome)
}

// (R-04) A paste over CRLF lines.
@Test func aMultiLinePasteOverCRLFLinesIsTheLinesItCovers() {
    let old = "alpha\r\nbeta\r\ngamma\r\ndelta"
    let outcome = decide(old, replacing: nsRange(of: "beta", in: old), with: "be\r\nta")
    expectLines(block(from: "be\r\n", to: "ta", in: outcome.text), outcome)
}

// (R-04) U+2028 stays inside the line: the styler reads one line, so the range is the whole of it.
@Test func aLineSeparatorInsideALineDoesNotSplitIt() {
    let old = "alpha\u{2028}beta\ngamma"
    let outcome = decide(old, inserting: "x", after: "\u{2028}")
    expectLines(NSRange(location: 0, length: ("alpha\u{2028}xbeta" as NSString).length), outcome)
}

// (R-04) And so does a lone "\r".
@Test func aLoneCarriageReturnInsideALineDoesNotSplitIt() {
    let old = "one\rtwo\nthree"
    let outcome = decide(old, inserting: "x", after: "tw")
    expectLines(NSRange(location: 0, length: ("one\rtwxo" as NSString).length), outcome)
}

// (R-04) A replace of the whole note is a wholesale replace.
@Test func replacingTheWholeNoteIsAFullRestyle() {
    let old = "alpha\nbeta"
    expectFull(.wholesale, decide(old, replacing: NSRange(location: 0, length: (old as NSString).length), with: "altro testo"))
}

// MARK: - Recording, taking, the seed and the fragment's map

// (R-04) With nothing recorded there is nothing to decide, and a decision is taken once.
@Test func takingWithNothingRecordedAnswersNothing() {
    var scope = RestyleScope(text: "alpha\nbeta")
    #expect(scope.take() == nil)
    var recorded = RestyleScope(text: "alpha\nbeta")
    recorded.record(StorageEdit(range: NSRange(location: 1, length: 1), delta: 1), in: "axlpha\nbeta" as NSString)
    #expect(recorded.take() != nil)
    #expect(recorded.take() == nil)
}

// (R-04) Two edits before one restyle are one dirty range, the lines from the first to the last.
@Test func twoRecordedEditsAreOneRangeOverBothLines() {
    var scope = RestyleScope(text: "uno\ndue\ntre\nquattro\ncinque")
    let first = "uxno\ndue\ntre\nquattro\ncinque"
    scope.record(StorageEdit(range: NSRange(location: 1, length: 1), delta: 1), in: first as NSString)
    let secondAt = nsRange(of: "quattro", in: first).location + 2
    let second = (first as NSString).replacingCharacters(in: NSRange(location: secondAt, length: 0), with: "y")
    scope.record(StorageEdit(range: NSRange(location: secondAt, length: 1), delta: 1), in: second as NSString)

    let decision = scope.take()
    guard case .lines(let range)? = decision else {
        Issue.record("expected .lines, got \(String(describing: decision))")
        return
    }
    #expect(withoutTerminator(range, in: second) == block(from: "uxno", to: "quyattro", in: second))
    #expect(scope.take() == nil)
}

// (R-04) The list stack in force at a line's first character, from the map's roles.
@Test func theListSeedIsTheStackBeforeTheLine() {
    let text = "- a\n  - b\n    - c\nparagrafo\n  - d"
    let scope = RestyleScope(text: text)
    #expect(scope.listSeed(at: 0).isEmpty)
    #expect(scope.listSeed(at: nsRange(of: "    - c", in: text).location) == [2, 4])
    #expect(scope.listSeed(at: nsRange(of: "paragrafo", in: text).location) == [2, 4, 6])
    #expect(scope.listSeed(at: nsRange(of: "  - d", in: text).location).isEmpty)
}

// (R-02, R-04) After the restyle the scope takes the fragment's own map, and its map is the one a
// fresh build of the new text gives.
@Test func absorbingTheFragmentsMapLeavesTheMapEqualToOneBuiltFromTheNewText() {
    let old = "intro\n| a | b |\nriga\nfine"
    var outcome = decide(old, replacing: nsRange(of: "riga", in: old), with: "| - | - |")
    guard case .lines(let range)? = outcome.decision else {
        Issue.record("expected .lines, got \(describe(outcome))")
        return
    }
    let fragment = (outcome.text as NSString).substring(with: range)
    outcome.scope.absorb(StructureMap(text: fragment), at: range.location, replacing: range)

    let expected = StructureMap(text: outcome.text)
    #expect(outcome.scope.map == expected)
    #expect(expected.tableRuns == [nsRange(of: "| a | b |\n| - | - |", in: outcome.text)])
}

// MARK: - renumberWindow(before:) (ADR-0093 §D8)
//
// Plan docs/plans/scoped-layout-followup.md, Task 5 (R-10). The window a scope hands the windowed list
// renumbering: where its read starts, and whether a fence is open there. The cases by name are in
// `ListRenumberWindowTests`; here the scope's own life: kept through an edit, and stale after a
// wholesale replace.

// (R-10) A scope kept through an edit gives the window a scope built from the new text gives.
@Test func aScopeKeptThroughAnEditGivesTheWindowAFreshOneGives() {
    let old = "```\ncode\n\n1. a\n2. b\n\n3. c\n4. d\n"
    let outcome = decide(old, inserting: "x", after: "2. b")
    let fresh = RestyleScope(text: outcome.text)
    let offsets = [0, nsRange(of: "2. bx", in: outcome.text).location, nsRange(of: "4. d", in: outcome.text).location]

    for offset in offsets {
        #expect(outcome.scope.renumberWindow(before: offset) == fresh.renumberWindow(before: offset), "at \(offset)")
    }
    // Non-vacuity: the fence above the second run is open at its start, and the window is not the top.
    let window = fresh.renumberWindow(before: offsets[2])
    #expect(window?.fenceOpen == true)
    #expect((window?.start ?? 0) > 0)
}

// (R-10) An edit that turns a line into a fence delimiter moves the parity below it.
@Test func aDelimiterTypedAboveFlipsTheParityBelow() {
    let old = "intro\n\n1. a\n2. b\n"
    // Test correction: the insert was "```" glued to "intro" ("intro```"), which is not a delimiter line
    // (it must start with the fence after its indent), so the implementation rightly answered false.
    // The intent is a delimiter typed on a line of its own above the list: "\n```" after "intro".
    let outcome = decide(old, inserting: "\n```", after: "intro")
    let offset = nsRange(of: "2. b", in: outcome.text).location

    #expect(outcome.scope.renumberWindow(before: offset)?.fenceOpen == true)
    #expect(RestyleScope(text: old).renumberWindow(before: nsRange(of: "2. b", in: old).location)?.fenceOpen == false)
}

// (R-10) A scope made stale by a wholesale replace answers no window, whatever the offset.
@Test func aStaleScopeGivesNoWindowAtAnyOffset() {
    let old = "1. a\n2. b\n"
    // Non-vacuity: before the replace the same scope answers.
    #expect(RestyleScope(text: old).renumberWindow(before: 3) != nil, "a fresh scope gave no window")
    let outcome = decide(old, replacing: NSRange(location: 0, length: (old as NSString).length), with: "9. x\n8. y\n")

    #expect(outcome.decision == .full(.wholesale))
    for offset in [0, 3, 8] { #expect(outcome.scope.renumberWindow(before: offset) == nil, "at \(offset)") }
}
