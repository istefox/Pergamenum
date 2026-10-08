import AppKit
import Testing
@testable import Pergamenum

// (coverage) tests, second half (the first is `GutterColumnSiteTests.swift`, split for the
// 400-line file limit): the memo the marker widths come from, and the inline-span reveal inside a
// revealed list, quote or heading (ADR-0081 §D2-§D4). Each asserts what the code's own
// documentation, the plan or an existing caller already states. The pin is `(n2-page coverage)`.

// MARK: - MarkerRunWidths (ADR-0081 §D2, ADR-0035's lock-guarded box shape)

@Suite struct GutterMarkerRunWidths {
    private static func measured(_ run: String, _ size: CGFloat) -> CGFloat {
        (run as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size)]).width
    }

    @Test func aRunIsMeasuredInTheFaceItIsDrawnIn() {
        // (n2-page coverage)
        let widths = MarkerRunWidths()
        let font = NSFont.systemFont(ofSize: 20)
        #expect(widths.width(of: "- ", in: font) == Self.measured("- ", 20))
        #expect(widths.width(of: "12) ", in: font) == Self.measured("12) ", 20))
    }

    @Test func theSameRunInADifferentFaceIsMeasuredAgain() {
        // (n2-page coverage) The memo is keyed on (run, face), not on the run alone.
        let widths = MarkerRunWidths()
        let small = widths.width(of: "## ", in: NSFont.systemFont(ofSize: 11))
        let large = widths.width(of: "## ", in: NSFont.systemFont(ofSize: 28))
        #expect(small == Self.measured("## ", 11))
        #expect(large == Self.measured("## ", 28))
        #expect(large > small)
    }

    @Test func aSecondAskForTheSameRunAnswersTheSameNumber() {
        // (n2-page coverage)
        let widths = MarkerRunWidths()
        let font = NSFont.systemFont(ofSize: 17)
        let first = widths.width(of: "> > ", in: font)
        #expect(widths.width(of: "> > ", in: font) == first)
    }

    /// One run per ordinal of a long ordered list must not grow the memo for the view's lifetime:
    /// past its capacity it starts over, and still answers the measured width.
    @Test func aLongOrderedListDoesNotGrowTheMemoPastItsCapacity() {
        // (n2-page coverage)
        let widths = MarkerRunWidths()
        let font = NSFont.systemFont(ofSize: 17)
        for ordinal in 1...(MarkerRunWidths.capacity * 3) {
            _ = widths.width(of: "\(ordinal). ", in: font)
        }
        #expect(widths.count <= MarkerRunWidths.capacity)
        #expect(widths.width(of: "1. ", in: font) == Self.measured("1. ", 17))
    }

    /// TextKit calls the delegate from its layout pass, off the main actor, so the box must give
    /// the right number to many readers at once (a bare dictionary would be a race the compiler
    /// cannot see).
    @Test func manyThreadsAskingAtOnceAllGetTheMeasuredWidth() {
        // (n2-page coverage)
        final class Tally: @unchecked Sendable {
            private let lock = NSLock()
            private var wrong = 0
            func record(_ ok: Bool) { if !ok { lock.withLock { wrong += 1 } } }
            var failures: Int { lock.withLock { wrong } }
        }
        let widths = MarkerRunWidths()
        let tally = Tally()
        let runs = ["- ", "1. ", "## ", "> ", "10) "]
        let expected = runs.map { Self.measured($0, 18) }
        DispatchQueue.concurrentPerform(iterations: 500) { index in
            let font = NSFont.systemFont(ofSize: 18)
            let slot = index % runs.count
            tally.record(widths.width(of: runs[slot], in: font) == expected[slot])
        }
        #expect(tally.failures == 0)
    }
}

// MARK: - A revealed list, quote or heading keeps the inline-span reveal (ADR-0081 §D2-§D4, ADR-0037)

@MainActor
@Suite struct GutterRevealedParagraphInlineSpans {
    private struct Block {
        let name: String
        let note: String
        let marker: HiddenMarker
        let strong: [NSRange]
    }

    /// `**b**` sits at 5..<10 in the heading and at 4..<9 in the list item and the quote.
    private static let blocks: [Block] = [
        Block(
            name: "titolo", note: "## a **b** c\n",
            marker: HiddenMarker(range: NSRange(location: 0, length: 3), kind: .heading),
            strong: [NSRange(location: 5, length: 2), NSRange(location: 8, length: 2)]
        ),
        Block(
            name: "elenco", note: "- a **b** c\n",
            marker: HiddenMarker(range: NSRange(location: 0, length: 2), kind: .list),
            strong: [NSRange(location: 4, length: 2), NSRange(location: 7, length: 2)]
        ),
        Block(
            name: "citazione", note: "> a **b** c\n",
            marker: HiddenMarker(range: NSRange(location: 0, length: 2), kind: .blockquote),
            strong: [NSRange(location: 4, length: 2), NSRange(location: 7, length: 2)]
        )
    ]

    private static func displayed(_ block: Block, revealedSpan: NSRange?) -> NSAttributedString? {
        let delegate = EditorDecorationDelegate()
        delegate.gutter = 48
        delegate.markerFont = .systemFont(ofSize: 11)
        let markers = [block.marker] + block.strong.map { HiddenMarker(range: $0, kind: .emphasis) }
        delegate.apply(hiddenMarkers: [0: markers], hidingMarkup: true)
        _ = delegate.apply(revealedParagraphs: [0])
        _ = delegate.apply(revealedSpans: [0: revealedSpan.map { [$0] } ?? []])
        delegate.apply(revealsInlineSpans: true)
        return MarkupHidingFixture.substitutedParagraph(delegate, note: block.note)?.attributedString
    }

    private static func font(_ text: NSAttributedString?, at index: Int) -> NSFont? {
        text?.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }

    /// The caret is in the paragraph and outside the span: the block marker shows, the strong
    /// delimiters stay collapsed (ADR-0037 §D3), exactly as when these paragraphs fell through to
    /// the generic path.
    @Test func aSpanTheCaretIsNotInStaysCollapsedInARevealedBlock() {
        // (n2-page coverage)
        for block in Self.blocks {
            let text = Self.displayed(block, revealedSpan: nil)
            #expect(text != nil, "«\(block.name)»: nessun paragrafo")
            #expect(text?.string == block.note, "«\(block.name)»: il testo cambia")
            for delimiter in block.strong {
                for index in delimiter.location..<NSMaxRange(delimiter) {
                    #expect(
                        Self.font(text, at: index) == EditorDecorationDelegate.collapsedFont,
                        "«\(block.name)»: il delimitatore \(index) non e compresso"
                    )
                }
            }
        }
    }

    /// The caret is inside the span: its delimiters show.
    @Test func aSpanTheCaretIsInShowsItsDelimitersInARevealedBlock() {
        // (n2-page coverage)
        for block in Self.blocks {
            let span = NSRange(
                location: block.strong[0].location,
                length: NSMaxRange(block.strong[1]) - block.strong[0].location
            )
            let text = Self.displayed(block, revealedSpan: span)
            #expect(text != nil, "«\(block.name)»: nessun paragrafo")
            for delimiter in block.strong {
                #expect(
                    Self.font(text, at: delimiter.location) != EditorDecorationDelegate.collapsedFont,
                    "«\(block.name)»: il delimitatore resta compresso con il cursore nello span"
                )
            }
        }
    }

    /// The heading's own `#` run is in the marker face either way, and the paragraph keeps its
    /// stored length (`NSTextContentManager.h:120`) in every case.
    @Test func theBlockMarkerAndTheStoredLengthSurviveTheSpanReveal() {
        // (n2-page coverage)
        for block in Self.blocks {
            let text = Self.displayed(block, revealedSpan: nil)
            #expect(text?.length == MarkupHidingFixture.firstParagraphLength(of: block.note), "«\(block.name)»")
        }
        let heading = Self.displayed(Self.blocks[0], revealedSpan: nil)
        #expect(Self.font(heading, at: 0) == NSFont.systemFont(ofSize: 11))
    }
}
