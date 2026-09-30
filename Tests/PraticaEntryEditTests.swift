import Foundation
import Testing
@testable import Pergamenum

// ADR-0076 §D1/§D4 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md, Task 2 -
// R-01, R-11, R-12, R-14, R-19: the pure text transforms behind the timeline's body writes.
// Every fixture is written in LF and run in both line breaks: the expected text is the LF one
// converted the same way, so an equality is the whole of "every other byte is kept".

@Suite struct PraticaEntryEditTests {
    private static let frontmatter = "---\ndate: 2026-06-10\ntags: [type-note]\n---\n"
    private static let free = "## 2026-06-10 14:06 Nota · Mario Rossi"
    private static let anchored = "## 2026-06-11 09:00 Telefonata · Studio Bianchi"
    private static let oldAnchor = "<!-- pergamenum-message: <old@rossi.it> -->"
    private static let newAnchor = "<!-- pergamenum-message: <new@rossi.it> -->"

    /// A free entry, then one anchored to `<old@rossi.it>`.
    private static let source = frontmatter + "\nIntroduzione.\n\n"
        + free + "\ncorpo uno\n\n"
        + anchored + "\n" + oldAnchor + "\ncorpo due\n"

    private static func written(_ lineBreak: LineBreak, _ text: String) -> String {
        lineBreak.normalised(text)
    }

    // MARK: - R-11: anchor and re-anchor

    @Test(arguments: [LineBreak.lf, .crlf])
    func anchoringInsertsTheLineDirectlyAfterTheHeading(_ lineBreak: LineBreak) {
        let expected = Self.frontmatter + "\nIntroduzione.\n\n"
            + Self.free + "\n" + Self.newAnchor + "\ncorpo uno\n\n"
            + Self.anchored + "\n" + Self.oldAnchor + "\ncorpo due\n"

        let result = PraticaEntryEdit.anchoring(
            entryAt: 0, to: "<new@rossi.it>", in: Self.written(lineBreak, Self.source)
        )

        #expect(result == Self.written(lineBreak, expected))
    }

    @Test(arguments: [LineBreak.lf, .crlf])
    func anchoringReplacesAnExistingAnchorKeepingItsLineBreak(_ lineBreak: LineBreak) {
        let expected = Self.frontmatter + "\nIntroduzione.\n\n"
            + Self.free + "\ncorpo uno\n\n"
            + Self.anchored + "\n" + Self.newAnchor + "\ncorpo due\n"

        let result = PraticaEntryEdit.anchoring(
            entryAt: 1, to: "<new@rossi.it>", in: Self.written(lineBreak, Self.source)
        )

        #expect(result == Self.written(lineBreak, expected))
    }

    @Test(arguments: [LineBreak.lf, .crlf])
    func anchoringAHeadingOnTheLastLineWithoutALineBreak(_ lineBreak: LineBreak) {
        let source = Self.written(lineBreak, "Introduzione.\n\n") + Self.free

        let result = PraticaEntryEdit.anchoring(entryAt: 0, to: "<new@rossi.it>", in: source)

        #expect(result == Self.written(lineBreak, "Introduzione.\n\n" + Self.free + "\n" + Self.newAnchor))
    }

    @Test(arguments: [LineBreak.lf, .crlf])
    func anchoringAnswersNilWhenThereIsNothingToWrite(_ lineBreak: LineBreak) {
        let source = Self.written(lineBreak, Self.source)

        #expect(PraticaEntryEdit.anchoring(entryAt: 1, to: "<old@rossi.it>", in: source) == nil)
        #expect(PraticaEntryEdit.anchoring(entryAt: 2, to: "<new@rossi.it>", in: source) == nil)
        #expect(PraticaEntryEdit.anchoring(entryAt: -1, to: "<new@rossi.it>", in: source) == nil)
        #expect(PraticaEntryEdit.anchoring(entryAt: 0, to: "", in: source) == nil)
    }

    // MARK: - R-12: unanchor

    @Test(arguments: [LineBreak.lf, .crlf])
    func unanchoringRemovesTheLineAndItsLineBreakOnly(_ lineBreak: LineBreak) {
        let expected = Self.frontmatter + "\nIntroduzione.\n\n"
            + Self.free + "\ncorpo uno\n\n"
            + Self.anchored + "\ncorpo due\n"

        let result = PraticaEntryEdit.unanchoring(entryAt: 1, in: Self.written(lineBreak, Self.source))

        #expect(result == Self.written(lineBreak, expected))
    }

    @Test(arguments: [LineBreak.lf, .crlf])
    func unanchoringAnIndentedLineTakesItsWhitespaceWithIt(_ lineBreak: LineBreak) {
        let source = Self.written(lineBreak, Self.anchored + "\n  " + Self.oldAnchor + " \ncorpo\n")

        let result = PraticaEntryEdit.unanchoring(entryAt: 0, in: source)

        #expect(result == Self.written(lineBreak, Self.anchored + "\ncorpo\n"))
    }

    @Test(arguments: [LineBreak.lf, .crlf])
    func unanchoringAFreeEntryAnswersNil(_ lineBreak: LineBreak) {
        let source = Self.written(lineBreak, Self.source)

        #expect(PraticaEntryEdit.unanchoring(entryAt: 0, in: source) == nil)
        #expect(PraticaEntryEdit.unanchoring(entryAt: 7, in: source) == nil)
    }

    // MARK: - R-14, R-19: the carry

    private static let anchorM = "<!-- pergamenum-message: <m@rossi.it> -->"
    private static let anchorOther = "<!-- pergamenum-message: <altro@rossi.it> -->"
    private static let blockA = "## 2026-06-10 10:00 Nota · Mario Rossi\n" + anchorM + "\ncorpo A"
    private static let blockB = "## 2026-06-10 11:00 Nota · Mario Rossi\n" + anchorOther + "\ncorpo B"
    private static let blockC = "## 2026-06-10 12:00 Telefonata · Mario Rossi\n" + anchorM + "\ncorpo C"

    /// A, anchored to `<m@rossi.it>`; B, to another message; C, to `<m@rossi.it>` again, followed
    /// by two blank lines at the end of the file.
    private static let carrySource = frontmatter + "\nIntroduzione.\n\n"
        + blockA + "\n\n" + blockB + "\n\n" + blockC + "\n\n\n"

    @Test(arguments: [LineBreak.lf, .crlf])
    func blocksReturnsOnlyThatMessagesBlocksLFNormalisedWithoutTrailingBlankLines(_ lineBreak: LineBreak) {
        let blocks = PraticaEntryEdit.blocks(anchoredTo: "<m@rossi.it>", in: Self.written(lineBreak, Self.carrySource))

        #expect(blocks == [Self.blockA, Self.blockC])
        #expect(PraticaEntryEdit.blocks(anchoredTo: "<nessuno@rossi.it>", in: Self.carrySource).isEmpty)
    }

    @Test(arguments: [LineBreak.lf, .crlf])
    func appendingPutsOneBlankLineBeforeEachBlockInTheTargetsLineBreak(_ lineBreak: LineBreak) {
        let endsWithLineBreak = Self.written(lineBreak, Self.frontmatter + "\ncorpo\n")
        let endsWithoutOne = Self.written(lineBreak, Self.frontmatter + "\ncorpo")
        let endsWithABlankLine = Self.written(lineBreak, Self.frontmatter + "\ncorpo\n\n")
        let expected = Self.written(
            lineBreak, Self.frontmatter + "\ncorpo\n\n" + Self.blockA + "\n\n" + Self.blockC + "\n"
        )

        #expect(PraticaEntryEdit.appending([Self.blockA, Self.blockC], to: endsWithLineBreak) == expected)
        #expect(PraticaEntryEdit.appending([Self.blockA, Self.blockC], to: endsWithoutOne) == expected)
        #expect(PraticaEntryEdit.appending([Self.blockA, Self.blockC], to: endsWithABlankLine) == expected)
        #expect(PraticaEntryEdit.appending([], to: endsWithLineBreak) == endsWithLineBreak)
    }

    @Test func appendingToAnEmptyTargetAddsNoLeadingBlankLine() {
        #expect(PraticaEntryEdit.appending([Self.blockA], to: "") == Self.blockA + "\n")
    }

    @Test(arguments: [LineBreak.lf, .crlf])
    func removingDropsExactlyTheMatchingBlocksAndKeepsEveryOtherByte(_ lineBreak: LineBreak) {
        // C ended the file, so the blank line `appending` would have put before it goes too.
        let expected = Self.frontmatter + "\nIntroduzione.\n\n" + Self.blockB + "\n"

        let removal = PraticaEntryEdit.removing(
            [Self.blockA, Self.blockC], anchoredTo: "<m@rossi.it>", from: Self.written(lineBreak, Self.carrySource)
        )

        #expect(removal == PraticaEntryEdit.Removal(text: Self.written(lineBreak, expected), missing: []))
    }

    @Test(arguments: [LineBreak.lf, .crlf])
    func anEditedBlockIsReportedMissingAndStays(_ lineBreak: LineBreak) {
        let source = Self.written(lineBreak, Self.carrySource)
        let edited = Self.blockA + " modificato"
        let expected = Self.frontmatter + "\nIntroduzione.\n\n" + Self.blockA + "\n\n" + Self.blockB + "\n"

        let removal = PraticaEntryEdit.removing([edited, Self.blockC], anchoredTo: "<m@rossi.it>", from: source)

        #expect(removal.text == Self.written(lineBreak, expected))
        #expect(removal.missing == [edited])
    }

    @Test(arguments: [LineBreak.lf, .crlf])
    func aBlockOfAnotherMessageIsNeverRemoved(_ lineBreak: LineBreak) {
        let source = Self.written(lineBreak, Self.carrySource)

        let removal = PraticaEntryEdit.removing([Self.blockB], anchoredTo: "<m@rossi.it>", from: source)

        #expect(removal == PraticaEntryEdit.Removal(text: source, missing: [Self.blockB]))
    }

    @Test(arguments: [LineBreak.lf, .crlf])
    func twoIdenticalBlocksAreConsumedOnceEach(_ lineBreak: LineBreak) {
        let source = Self.written(lineBreak, Self.blockA + "\n\n" + Self.blockA + "\n\n" + Self.blockC + "\n")

        let once = PraticaEntryEdit.removing([Self.blockA], anchoredTo: "<m@rossi.it>", from: source)
        let twice = PraticaEntryEdit.removing([Self.blockA, Self.blockA], anchoredTo: "<m@rossi.it>", from: source)
        let thrice = PraticaEntryEdit.removing(
            [Self.blockA, Self.blockA, Self.blockA], anchoredTo: "<m@rossi.it>", from: source
        )

        #expect(once == .init(text: Self.written(lineBreak, Self.blockA + "\n\n" + Self.blockC + "\n"), missing: []))
        #expect(twice == .init(text: Self.written(lineBreak, Self.blockC + "\n"), missing: []))
        #expect(thrice == .init(text: Self.written(lineBreak, Self.blockC + "\n"), missing: [Self.blockA]))
    }

    /// The round trip a carry makes: what `blocks` extracts, `appending` writes into another file
    /// and `removing` then finds there again, whatever that file's line break.
    @Test(arguments: [LineBreak.lf, .crlf])
    func appendedBlocksAreFoundAgainByRemoving(_ lineBreak: LineBreak) {
        let blocks = PraticaEntryEdit.blocks(anchoredTo: "<m@rossi.it>", in: Self.carrySource)
        let target = Self.written(lineBreak, Self.frontmatter + "\ncorpo\n")

        let appended = PraticaEntryEdit.appending(blocks, to: target)
        let removal = PraticaEntryEdit.removing(blocks, anchoredTo: "<m@rossi.it>", from: appended)

        #expect(PraticaEntryEdit.blocks(anchoredTo: "<m@rossi.it>", in: appended) == blocks)
        #expect(removal.missing.isEmpty)
        #expect(removal.text == target, "the round trip gives the target back byte for byte")
    }

    /// The trailing-separator rule, alone: only a block that ended the file takes the blank
    /// line before it, only one, and a block with a neighbour after it takes only its own range.
    @Test(arguments: [LineBreak.lf, .crlf])
    func onlyABlockEndingTheFileTakesTheOneBlankLineBeforeIt(_ lineBreak: LineBreak) {
        let last = Self.written(lineBreak, "corpo\n\n\n" + Self.blockA + "\n")
        let middle = Self.written(lineBreak, "corpo\n\n" + Self.blockA + "\n\n" + Self.blockB + "\n")
        let adjacent = Self.written(lineBreak, "corpo\n" + Self.blockA + "\n")

        #expect(PraticaEntryEdit.removing([Self.blockA], anchoredTo: "<m@rossi.it>", from: last).text
            == Self.written(lineBreak, "corpo\n\n"))
        #expect(PraticaEntryEdit.removing([Self.blockA], anchoredTo: "<m@rossi.it>", from: middle).text
            == Self.written(lineBreak, "corpo\n\n" + Self.blockB + "\n"))
        #expect(PraticaEntryEdit.removing([Self.blockA], anchoredTo: "<m@rossi.it>", from: adjacent).text
            == Self.written(lineBreak, "corpo\n"))
        #expect(PraticaEntryEdit.removing([Self.blockA], anchoredTo: "<m@rossi.it>", from: Self.blockA + "\n").text
            == "")
    }

    // MARK: - R-01: the inspector

    @Test(arguments: [LineBreak.lf, .crlf])
    func removingAnchorLinesDropsOnlyThoseDirectlyUnderAHeading(_ lineBreak: LineBreak) {
        let source = Self.frontmatter + "\n"
            + Self.free + "\n" + Self.anchorM + "\ncorpo\n\n"
            + Self.anchored + "\ncorpo\n" + Self.anchorOther + "\n"
        let expected = Self.frontmatter + "\n"
            + Self.free + "\ncorpo\n\n"
            + Self.anchored + "\ncorpo\n" + Self.anchorOther + "\n"

        #expect(PraticaEntryEdit.removingAnchorLines(in: Self.written(lineBreak, source))
            == Self.written(lineBreak, expected))
    }
}
