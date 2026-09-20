import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0037 (word-grained markdown reveal-on-caret in the editor), plan
// `2026-09-08-word-grained-markdown-reveal-on-caret-in`, Task 7 (R-06, R-07, R-09).
//
// No production code in this task ("no production code unless a fence fails"): every assertion
// here is a global invariant or a regression fence over Tasks 1-6, already merged and green.
// If any assertion below genuinely fails against today's code, that is reported, not fixed here.

// MARK: - 1. The invariant (constraint 3): every `inlineSpans` key is a `paragraphs` member

@Suite struct InlineSpansKeysAreAlwaysParagraphMembers {
    private struct Fixture {
        let name: String
        let text: String
        let selection: NSRange
        let markedRange: NSRange
        let currentMatch: NSRange?
    }

    private static let notFound = NSRange(location: NSNotFound, length: 0)

    private static let fixtures: [Fixture] = [
        Fixture(
            name: "caret inside a bold run, single paragraph",
            text: "**uno** e basta\n", selection: NSRange(location: 3, length: 0),
            markedRange: notFound, currentMatch: nil
        ),
        Fixture(
            name: "no inline construct anywhere",
            text: "prosa senza nulla da rivelare\n", selection: NSRange(location: 5, length: 0),
            markedRange: notFound, currentMatch: nil
        ),
        Fixture(
            name: "selection spanning two paragraphs, one with emphasis",
            text: "**uno** qui\ndue righe dopo\n",
            selection: NSRange(location: 2, length: 15), markedRange: notFound, currentMatch: nil
        ),
        Fixture(
            name: "a wikilink under an active IME composition, no selection",
            text: "vedi [[Nota]] per favore\n",
            selection: NSRange(location: 0, length: 0),
            markedRange: NSRange(location: 5, length: 8), currentMatch: nil
        ),
        Fixture(
            name: "a CommonMark link under the find bar's current match",
            text: "primo paragrafo\n[testo](https://x.y) secondo\n",
            selection: notFound,
            markedRange: notFound,
            currentMatch: NSRange(location: 17, length: 20)
        ),
        Fixture(
            name: "a selection covering a whole paragraph entirely",
            text: "**tutto coperto**\ndopo\n",
            selection: NSRange(location: 0, length: 18), markedRange: notFound, currentMatch: nil
        ),
    ]

    @Test func everyInlineSpanKeyIsAlsoAParagraphKeyAcrossEveryFixture() {
        for fixture in Self.fixtures {
            let paragraphs = MarkupReveal.paragraphs(
                in: fixture.text, selection: fixture.selection,
                markedRange: fixture.markedRange, currentMatch: fixture.currentMatch
            )
            let spans = MarkupReveal.inlineSpans(
                in: fixture.text, selection: fixture.selection,
                markedRange: fixture.markedRange, currentMatch: fixture.currentMatch
            )
            #expect(
                Set(spans.keys).isSubset(of: paragraphs),
                "«\(fixture.name)»: inlineSpans keys \(Set(spans.keys)) are not all in paragraphs \(paragraphs) - this is what licenses leaving the list/checkbox/blockquote delegate branches unedited"
            )
        }
    }
}

// MARK: - 2. R-06 by construct, end to end: six constructs, identical whether the flag is on or off

@MainActor
private func laidOutOffsets(of delegate: EditorDecorationDelegate, text: String) -> Set<Int> {
    let content = NSTextContentStorage()
    let layout = NSTextLayoutManager()
    content.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    layout.textContainer = container
    content.delegate = delegate
    content.textStorage?.setAttributedString(
        NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)])
    )
    layout.ensureLayout(for: layout.documentRange)
    var offsets: Set<Int> = []
    layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
        offsets.insert(content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location))
        return true
    }
    return offsets
}

private func collapsedFontRanges(in attributed: NSAttributedString) -> [NSRange] {
    var ranges: [NSRange] = []
    attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
        if (value as? NSFont) == EditorDecorationDelegate.collapsedFont { ranges.append(range) }
    }
    return ranges
}

/// A note with one paragraph per non-inline `HiddenMarker.Kind`: heading, list, checkbox,
/// blockquote, table (header line) and view-block (opening fence line) - the six constructs
/// R-06 names. No table grid and no view-block host are registered, so `tableParagraph`/
/// `viewBlockParagraph` fall through to the generic per-marker path (both guard on
/// `tableViews[...]`/`viewBlockHosts[...]` before ever re-parsing the live characters) - which is
/// exactly the path this test needs, since `collapsing` decides a non-inline kind purely from
/// `paragraphIsRevealed`, never from `revealedSpans`.
@MainActor
private enum SixConstructFixture {
    static let heading = "# Titolo\n"
    static let list = "- voce\n"
    static let checkbox = "- [ ] fai\n"
    static let blockquote = "> nota\n"
    static let tableHeader = "| a | b |\n"
    static let viewBlockOpen = "```pergamenum-view\n"
    static let tableDelimiter = "|---|---|\n"
    static let viewBlockBody = "render: table\n"
    static let viewBlockClose = "```\n"
    static let after = "dopo\n"

    static let text = heading + list + checkbox + blockquote + tableHeader + viewBlockOpen
        + tableDelimiter + viewBlockBody + viewBlockClose + after

    static let headingOffset = 0
    static let listOffset = headingOffset + (heading as NSString).length
    static let checkboxOffset = listOffset + (list as NSString).length
    static let blockquoteOffset = checkboxOffset + (checkbox as NSString).length
    static let tableOffset = blockquoteOffset + (blockquote as NSString).length
    static let viewBlockOffset = tableOffset + (tableHeader as NSString).length
    static let tableDelimiterOffset = viewBlockOffset + (viewBlockOpen as NSString).length
    static let viewBlockBodyOffset = tableDelimiterOffset + (tableDelimiter as NSString).length
    static let viewBlockCloseOffset = viewBlockBodyOffset + (viewBlockBody as NSString).length
    static let afterOffset = viewBlockCloseOffset + (viewBlockClose as NSString).length

    static let constructOffsets = [
        headingOffset, listOffset, checkboxOffset, blockquoteOffset, tableOffset, viewBlockOffset,
    ]

    static let markers: [Int: [HiddenMarker]] = [
        headingOffset: [HiddenMarker(range: NSRange(location: 0, length: 2), kind: .heading)],
        listOffset: [HiddenMarker(range: NSRange(location: 0, length: 2), kind: .list)],
        checkboxOffset: [HiddenMarker(range: NSRange(location: 0, length: 5), kind: .checkbox)],
        blockquoteOffset: [HiddenMarker(range: NSRange(location: 0, length: 2), kind: .blockquote)],
        tableOffset: [HiddenMarker(range: NSRange(location: 0, length: 9), kind: .table)],
        viewBlockOffset: [HiddenMarker(range: NSRange(location: 0, length: 18), kind: .viewBlock)],
    ]

    /// A span table with entries at two of the six (non-inline) offsets, to prove those entries
    /// are inert for them - `collapsing` never consults `revealedSpans` for a kind whose
    /// `isInline` is `false`.
    static let revealedSpansWhenOn: [Int: [NSRange]] = [
        headingOffset: [NSRange(location: 0, length: 2)],
        tableOffset: [NSRange(location: 0, length: 9)],
    ]

    static func makeDelegate(revealsInlineSpans: Bool) -> EditorDecorationDelegate {
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: markers, hidingMarkup: true)
        _ = delegate.apply(revealedParagraphs: [])
        _ = delegate.apply(revealedSpans: revealsInlineSpans ? revealedSpansWhenOn : [:])
        delegate.apply(revealsInlineSpans: revealsInlineSpans)
        delegate.apply(tableRows: [tableDelimiterOffset])
        delegate.apply(viewBlockLines: [viewBlockBodyOffset, viewBlockCloseOffset])
        return delegate
    }

    static func substitutedParagraph(_ delegate: EditorDecorationDelegate, at offset: Int) -> NSTextParagraph? {
        let content = NSTextContentStorage()
        content.textStorage?.setAttributedString(NSAttributedString(string: text))
        let range = (text as NSString).paragraphRange(for: NSRange(location: offset, length: 0))
        return delegate.textContentStorage(content, textParagraphWith: range)
    }
}

@MainActor
@Suite struct R06IdenticalAcrossTheSettingByConstruct {
    @Test func substitutedParagraphLengthsAndCollapsedFontRangesAreIdenticalOnAndOff() {
        let off = SixConstructFixture.makeDelegate(revealsInlineSpans: false)
        let on = SixConstructFixture.makeDelegate(revealsInlineSpans: true)

        for offset in SixConstructFixture.constructOffsets {
            let offParagraph = SixConstructFixture.substitutedParagraph(off, at: offset)
            let onParagraph = SixConstructFixture.substitutedParagraph(on, at: offset)

            #expect(
                offParagraph?.attributedString.length == onParagraph?.attributedString.length,
                "offset \(offset): length differs between the setting off and on (R-06)"
            )
            #expect(
                offParagraph?.attributedString.string == onParagraph?.attributedString.string,
                "offset \(offset): displayed characters differ between the setting off and on (R-06)"
            )
            let offRanges = offParagraph.map { collapsedFontRanges(in: $0.attributedString) } ?? []
            let onRanges = onParagraph.map { collapsedFontRanges(in: $0.attributedString) } ?? []
            #expect(
                offRanges == onRanges,
                "offset \(offset): collapsedFont ranges differ between the setting off and on (R-06): \(offRanges) vs \(onRanges)"
            )
        }
    }

    @Test func hiddenLineSetsAreIdenticalOnAndOff() {
        let off = SixConstructFixture.makeDelegate(revealsInlineSpans: false)
        let on = SixConstructFixture.makeDelegate(revealsInlineSpans: true)

        let offLaidOut = laidOutOffsets(of: off, text: SixConstructFixture.text)
        let onLaidOut = laidOutOffsets(of: on, text: SixConstructFixture.text)

        #expect(offLaidOut == onLaidOut, "the set of laid-out paragraphs differs between the setting off and on (R-06)")
        // Sanity check that the hiding mechanism is actually engaged, not vacuously equal because
        // nothing was ever hidden.
        for delegate in [off, on] {
            let laidOut = laidOutOffsets(of: delegate, text: SixConstructFixture.text)
            #expect(!laidOut.contains(SixConstructFixture.tableDelimiterOffset))
            #expect(!laidOut.contains(SixConstructFixture.viewBlockBodyOffset))
            #expect(!laidOut.contains(SixConstructFixture.viewBlockCloseOffset))
            #expect(laidOut.contains(SixConstructFixture.afterOffset))
        }
    }
}

// MARK: - 3. R-07 as a whole-file property: "off" is indistinguishable from "never heard of it"

@MainActor
private func substitutedParagraph(
    _ delegate: EditorDecorationDelegate, note: String, at location: Int
) -> NSTextParagraph? {
    let content = NSTextContentStorage()
    content.textStorage?.setAttributedString(NSAttributedString(string: note))
    let range = (note as NSString).paragraphRange(for: NSRange(location: location, length: 0))
    return delegate.textContentStorage(content, textParagraphWith: range)
}

@MainActor
@Suite struct R07OffIsIndistinguishableFromNeverToldAboutTheSpanTable {
    private struct Fixture {
        let name: String
        let note: String
        let markers: [HiddenMarker]
    }

    private static let corpus: [Fixture] = [
        Fixture(
            name: "a heading",
            note: "# Titolo\ncorpo\n",
            markers: [HiddenMarker(range: NSRange(location: 0, length: 2), kind: .heading)]
        ),
        Fixture(
            name: "an emphasis pair",
            note: "testo **grassetto** qui\ncorpo\n",
            markers: [
                HiddenMarker(range: NSRange(location: 6, length: 2), kind: .emphasis),
                HiddenMarker(range: NSRange(location: 17, length: 2), kind: .emphasis),
            ]
        ),
        Fixture(
            name: "an unordered list item",
            note: "- primo\ncorpo\n",
            markers: [HiddenMarker(range: NSRange(location: 0, length: 2), kind: .list)]
        ),
        Fixture(
            name: "a checkbox line",
            note: "- [ ] fai\ncorpo\n",
            markers: [HiddenMarker(range: NSRange(location: 0, length: 5), kind: .checkbox)]
        ),
        Fixture(
            name: "list and emphasis together in one paragraph",
            note: "- **grassetto** elemento\n",
            markers: [
                HiddenMarker(range: NSRange(location: 0, length: 2), kind: .list),
                HiddenMarker(range: NSRange(location: 2, length: 2), kind: .emphasis),
                HiddenMarker(range: NSRange(location: 13, length: 2), kind: .emphasis),
            ]
        ),
    ]

    @Test func aDelegateExplicitlySetToOffAgreesWithOneThatNeverHeardOfTheSettingOrTheSpanTable() {
        for fixture in Self.corpus {
            // Explicitly told "off", and explicitly handed an empty span table.
            let told = EditorDecorationDelegate()
            told.apply(hiddenMarkers: [0: fixture.markers], hidingMarkup: true)
            _ = told.apply(revealedParagraphs: [])
            _ = told.apply(revealedSpans: [:])
            told.apply(revealsInlineSpans: false)

            // Never told anything about `revealedSpans`/`revealsInlineSpans` at all - left at
            // their declared defaults.
            let untold = EditorDecorationDelegate()
            untold.apply(hiddenMarkers: [0: fixture.markers], hidingMarkup: true)
            _ = untold.apply(revealedParagraphs: [])

            let toldParagraph = substitutedParagraph(told, note: fixture.note, at: 0)
            let untoldParagraph = substitutedParagraph(untold, note: fixture.note, at: 0)

            #expect(
                toldParagraph?.attributedString.length == untoldParagraph?.attributedString.length,
                "«\(fixture.name)»: length differs between explicit-off and never-told (R-07)"
            )
            #expect(
                toldParagraph?.attributedString.string == untoldParagraph?.attributedString.string,
                "«\(fixture.name)»: displayed characters differ between explicit-off and never-told (R-07)"
            )
            let toldRanges = toldParagraph.map { collapsedFontRanges(in: $0.attributedString) } ?? []
            let untoldRanges = untoldParagraph.map { collapsedFontRanges(in: $0.attributedString) } ?? []
            #expect(
                toldRanges == untoldRanges,
                "«\(fixture.name)»: collapsedFont ranges differ between explicit-off and never-told (R-07)"
            )
        }
    }
}

// MARK: - 4. ADR-0037 §D8 amendment (2026-09-09 hand check): CardTextView's hiddenKind switch
// now maps seven kinds, not five - F1's original boundary is reversed by explicit instruction,
// this fence now guards the widened boundary instead of the narrower one.

@Suite struct CardTextViewHiddenKindSwitchMapsExactlySevenKinds {
    @Test func theSwitchMapsExactlySevenNonNilKinds() throws {
        let repoRoot = try resolvedRepoRoot()
        let url = repoRoot.appendingPathComponent("Sources/Features/Workspace/CardTextView.swift")
        let contents = try String(contentsOf: url, encoding: .utf8)

        let opener = "let kind: HiddenMarker.Kind? = switch styled.span {"
        let openRange = try #require(
            contents.range(of: opener),
            "CardTextView.swift no longer contains its hiddenKind switch opener - has it moved or been renamed?"
        )
        let closeRange = try #require(
            contents.range(of: "}", range: openRange.upperBound..<contents.endIndex),
            "no closing brace found after the hiddenKind switch opener"
        )
        let block = contents[openRange.upperBound..<closeRange.lowerBound]

        let mappedCases = block
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("case .") }

        #expect(
            mappedCases.count == 7,
            "CardTextView's hiddenKind switch maps \(mappedCases.count) kinds, expected exactly 7 (ADR-0037 §D8 amendment, 2026-09-09): \(mappedCases) - strikethrough and link/wikilink syntax now conceal in the card identically to the note editor, by explicit instruction reversing F1's original boundary"
        )
    }
}

// MARK: - 5. Out-of-scope diff fence: removed 2026-09-09.
//
// This suite compared `git diff --stat <plan-commit> HEAD` against a fixed list of files, to
// verify - once, during Task 7 - that ADR-0037's own implementation had not touched anything
// outside its stated scope. That check ran clean and is recorded in PROJECT_BRIEF.md.
//
// It could not survive as a standing regression test: the base SHA is frozen in the past, so
// once this chain merged into `main`, ANY later legitimate commit to one of the fenced shared
// files (e.g. ADR-0039's checkbox-click feature touching
// `EditorDecorationDelegate+CheckboxRendering.swift`) trips it forever, with no way to clear it
// short of deleting the suite. A point-in-time scope check has no business becoming a permanent
// build gate keyed to a commit that predates every future contributor's work.
