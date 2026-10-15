import AppKit
import Testing
@testable import Pergamenum

// ADR-0087 §D7, plan docs/plans/note-workflow-n5.md, Task 3 (R-39).
//
// A quoted paragraph reads as an indent per nesting level in the secondary text colour beside a
// full-height bar. `QuoteGeometry` is not a second geometry: it is the part of ADR-0081 §D3's
// `EditorGutter.quoteColumn` that the gutter does not own (Realignment 2).
//
// Per Realignment 2 the fragment is chosen for a quote paragraph that is not revealed; the revealed
// state keeps the raw `>` run hung in the gutter and draws no bar, and what is equal in both states is
// where the content starts.

@Suite struct QuoteGeometryArithmetic {
    @Test func theIndentIsTheLevelTimesTheStep() { // R-39
        #expect(QuoteGeometry.indent(level: 2, step: 12) == 24)
        #expect(QuoteGeometry.indent(level: 1, step: 12) == 12)
        #expect(QuoteGeometry.indent(level: 0, step: 12) == 0)
    }

    @Test func theBarsOfALevelThreeQuoteAreThreeIncreasingOffsetsInsideTheIndent() { // R-39
        let step: CGFloat = 12
        let offsets = QuoteGeometry.barOffsets(level: 3, step: step)
        #expect(offsets.count == 3)
        #expect(offsets == offsets.sorted() && Set(offsets).count == 3, "\(offsets)")
        #expect(offsets.allSatisfy { $0 >= 0 && $0 < QuoteGeometry.indent(level: 3, step: step) }, "\(offsets)")
    }
}

@MainActor
@Suite struct QuoteBarDrawing {
    private static let paragraph = 7
    private static let words = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron"
    private static let nested = "intro\n\n>> \(words)\n"

    private static func headIndent(_ built: N5Editor.Built, at offset: Int) -> CGFloat? {
        let shown = N5Editor.displayed(built, at: paragraph)
        let style = shown?.attribute(.paragraphStyle, at: offset - paragraph, effectiveRange: nil) as? NSParagraphStyle
        return style?.headIndent
    }

    @Test func aWrappedTwoLevelQuoteIsLaidOutAsALevelTwoQuoteBarFragment() throws { // R-39
        let built = N5Editor.build(Self.nested, width: 200, caret: 0)
        let fragment = try #require(N5Editor.fragments(built)[Self.paragraph] as? QuoteBarFragment)
        #expect(fragment.level == 2)
        #expect(fragment.callout == nil)
        #expect(fragment.textLineFragments.count >= 2, "the fixture must wrap")
    }

    @Test func itsTextIsInTheSecondaryColour() { // R-39
        let built = N5Editor.build(Self.nested, width: 200, caret: 0)
        let color = built.textView.textStorage?.attribute(.foregroundColor, at: 11, effectiveRange: nil) as? NSColor
        #expect(color == NSColor(built.theme.color(.textSecondary)))
    }

    @Test func itsContentStartsAtTheQuoteIndentConcealedAndRevealedAlike() { // R-39, R-14's invariant
        let concealed = N5Editor.build(Self.nested, width: 200, caret: 0)
        let revealed = N5Editor.build(Self.nested, width: 200, caret: 12)
        let decorations = concealed.coordinator.decorations
        let step = EditorGutter.quoteStepInEms * decorations.proseFont.pointSize
        let expected = decorations.gutter + QuoteGeometry.indent(level: 2, step: step)

        #expect(Self.headIndent(concealed, at: 11) == expected)
        #expect(Self.headIndent(revealed, at: 11) == expected)
        #expect(!(N5Editor.fragments(revealed)[Self.paragraph] is QuoteBarFragment))
    }

    @Test func theDisplayedQuoteKeepsItsStoredLengthConcealedAndRevealed() { // R-39
        for caret in [0, 12] {
            let built = N5Editor.build(Self.nested, width: 200, caret: caret)
            let lengths = N5Editor.lengths(built, at: Self.paragraph)
            #expect(lengths.displayed == lengths.stored, "caret \(caret): \(lengths)")
        }
    }

    /// Two consecutive quoted paragraphs: each bar spans its fragment's full height and the fragments
    /// touch, so the union of the bars is one contiguous rule.
    @Test func theBarsOfConsecutiveQuotedParagraphsLeaveNoGap() throws { // R-39
        let built = N5Editor.build("intro\n\n> uno\n> due\n> tre\n", caret: 0)
        let fragments = N5Editor.fragments(built)
        let bars = try [7, 13, 19].map { offset in
            try #require(fragments[offset] as? QuoteBarFragment, "nessuna QuoteBarFragment a \(offset)")
        }
        for (upper, lower) in zip(bars, bars.dropFirst()) {
            #expect(abs(upper.layoutFragmentFrame.maxY - lower.layoutFragmentFrame.minY) < 0.5)
        }
        for bar in bars {
            #expect(bar.renderingSurfaceBounds.height >= bar.layoutFragmentFrame.height - 0.5)
        }
    }
}
