import AppKit
import Testing
@testable import Pergamenum

// MARK: - The per-marker filter and the two new delegate inputs (ADR-0037 §D2/§D3; plan
// `2026-09-08-word-grained-markdown-reveal-on-caret-in`, Task 3)
//
// `EditorDecorationDelegate.collapsing(among:paragraphIsRevealed:revealedSpans:)` is
// exercised directly, as a pure static function, rather than through a full layout pass -
// the same reason the ADR itself gives for making it one: it is testable without a text
// view. The hook's own last guard calls it. R-07, which
// `theHookReturnsNilForARevealedParagraph` (in `Tests/MarkupHidingTests.swift`) pins, is
// pinned again below through the public `displayedParagraph` helper, extended with the two new, defaulted
// `spans:`/`revealsInlineSpans:` parameters rather than replaced.
@MainActor
@Suite struct MarkupHidingInlineSpans {
    // "**uno** e **due**\n" - two whole bold runs in one paragraph (R-01).
    private static let firstBoldOpen = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .emphasis)
    private static let firstBoldClose = HiddenMarker(range: NSRange(location: 5, length: 2), kind: .emphasis)
    private static let secondBoldOpen = HiddenMarker(range: NSRange(location: 10, length: 2), kind: .emphasis)
    private static let secondBoldClose = HiddenMarker(range: NSRange(location: 15, length: 2), kind: .emphasis)
    /// The first run's own whole construct, "**uno**".
    private static let firstBoldSpan = NSRange(location: 0, length: 7)

    // "[[Uno]] e [[Due]]\n" - two whole wikilink runs in one paragraph (R-02).
    private static let firstLinkOpen = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .link)
    private static let firstLinkClose = HiddenMarker(range: NSRange(location: 5, length: 2), kind: .link)
    private static let secondLinkOpen = HiddenMarker(range: NSRange(location: 10, length: 2), kind: .link)
    private static let secondLinkClose = HiddenMarker(range: NSRange(location: 15, length: 2), kind: .link)
    private static let firstLinkSpan = NSRange(location: 0, length: 7)

    // "**out *in* out**\n" - a bold run nesting an italic one, PG-084's recursive case (R-05).
    private static let outerOpen = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .emphasis)
    private static let outerClose = HiddenMarker(range: NSRange(location: 14, length: 2), kind: .emphasis)
    private static let innerOpen = HiddenMarker(range: NSRange(location: 6, length: 1), kind: .emphasis)
    private static let innerClose = HiddenMarker(range: NSRange(location: 9, length: 1), kind: .emphasis)
    private static let innerSpan = NSRange(location: 6, length: 4)

    // "# Titolo **enfasi** qui\n" - the SPEC's coexistence fixture (same offsets as
    // `MarkupHidingEmphasis.aParagraphWithAHeadingAndAnEmphasisMarkerCollapsesBothInOneSubstitution`
    // in `Tests/MarkupHidingTests.swift`): a heading marker (paragraph-grained) beside a bold
    // pair (span-grained) in the same paragraph (R-06).
    private static let headingAndBoldNote = "# Titolo **enfasi** qui\n"
    private static let headingMarker = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .heading)
    private static let boldOpen = HiddenMarker(range: NSRange(location: 9, length: 2), kind: .emphasis)
    private static let boldClose = HiddenMarker(range: NSRange(location: 17, length: 2), kind: .emphasis)

    private static let ruleMarker = HiddenMarker(range: NSRange(location: 0, length: 3), kind: .rule)

    // MARK: R-07 - the setting off leaves the hook untouched

    @Test func theHookReturnsNilWhenTheSettingIsOffEvenWithSpansSupplied() {
        let displayed = MarkupHidingFixture.displayedParagraph(
            Self.headingAndBoldNote,
            markers: [Self.headingMarker, Self.boldOpen, Self.boldClose],
            revealed: [0],
            spans: [0: [Self.firstBoldSpan]],
            revealsInlineSpans: false
        )
        #expect(displayed == nil)
    }

    // MARK: R-01 - two bold runs in one paragraph, only the untouched one collapses

    @Test func onlyTheSecondBoldRunsMarkersCollapseWhenTheFirstIsRevealed() {
        let markers = [Self.firstBoldOpen, Self.firstBoldClose, Self.secondBoldOpen, Self.secondBoldClose]
        let collapsing = EditorDecorationDelegate.collapsing(
            among: markers, paragraphIsRevealed: true, revealedSpans: [Self.firstBoldSpan]
        )

        #expect(collapsing.contains(Self.secondBoldOpen))
        #expect(collapsing.contains(Self.secondBoldClose))
        #expect(!collapsing.contains(Self.firstBoldOpen))
        #expect(!collapsing.contains(Self.firstBoldClose))
    }

    // MARK: R-02 - the same rule for a link marker pair

    @Test func onlyTheSecondLinksMarkersCollapseWhenTheFirstIsRevealed() {
        let markers = [Self.firstLinkOpen, Self.firstLinkClose, Self.secondLinkOpen, Self.secondLinkClose]
        let collapsing = EditorDecorationDelegate.collapsing(
            among: markers, paragraphIsRevealed: true, revealedSpans: [Self.firstLinkSpan]
        )

        #expect(collapsing.contains(Self.secondLinkOpen))
        #expect(collapsing.contains(Self.secondLinkClose))
        #expect(!collapsing.contains(Self.firstLinkOpen))
        #expect(!collapsing.contains(Self.firstLinkClose))
    }

    // MARK: R-03 - the caret moves out, an empty (but present) span list collapses everything again

    @Test func everyInlineMarkerCollapsesAgainOnceTheCaretLeavesEverySpan() {
        let markers = [Self.firstBoldOpen, Self.firstBoldClose, Self.secondBoldOpen, Self.secondBoldClose]
        let collapsing = EditorDecorationDelegate.collapsing(
            among: markers, paragraphIsRevealed: true, revealedSpans: []
        )

        for marker in markers {
            #expect(collapsing.contains(marker))
        }
    }

    // MARK: Regression (R-11 hand check) - a paragraph absent from the span table is not
    // the same as the setting being off

    /// Found by the R-11 hand check, not by a fixture: the caret's own paragraph is
    /// revealed (so `paragraphIsRevealed` is `true`), but no span was revealed inside it
    /// because the caret sits outside every construct. `MarkupReveal.inlineSpans` never
    /// writes a key for a paragraph with nothing to reveal, so the span table looked
    /// exactly like "the setting is off" to a bare dictionary lookup at the call site -
    /// `revealedSpans[range.location]` returning `nil` either way. `spans: [:]` here is
    /// deliberately not `spans: [0: []]`: it is the *absent-key* case that reproduced the
    /// bug, not an explicit empty span list (`everyInlineMarkerCollapsesAgainOnceTheCaretLeavesEverySpan`
    /// above already covers that one, passing `revealedSpans: []` straight into `collapsing`).
    @Test func aParagraphAbsentFromTheSpanTableStillCollapsesItsInlineMarkersDespiteBeingRevealed() {
        let note = "**uno**\n"
        let displayed = MarkupHidingFixture.displayedParagraph(
            note,
            markers: [Self.firstBoldOpen, Self.firstBoldClose],
            revealed: [0],
            spans: [:],
            revealsInlineSpans: true
        )

        #expect(displayed != nil)
        #expect(
            displayed?.attributedString.attribute(.font, at: Self.firstBoldOpen.range.location, effectiveRange: nil)
                as? NSFont == EditorDecorationDelegate.collapsedFont
        )
        #expect(
            displayed?.attributedString.attribute(.font, at: Self.firstBoldClose.range.location, effectiveRange: nil)
                as? NSFont == EditorDecorationDelegate.collapsedFont
        )
    }

    // MARK: Regression (issue #191 follow-up) - a paragraph entirely covered by a drag
    // reveals every inline marker in it, not just the ones whose own edges happen to line
    // up with the synthetic span

    /// `MarkupReveal.addSpans`'s own "entirely covered" shortcut (ADR-0037 §D5) hands back
    /// one span spanning the whole paragraph instead of parsing it for its real constructs -
    /// found hand-testing a drag from a paragraph's own start through the paragraph after
    /// it, which is exactly what makes that shortcut fire. Before the fix, `collapsing`'s
    /// edge-match (R-01/R-02 above) only revealed `firstLinkOpen`/`firstLinkClose`, since
    /// those alone happen to sit at the whole-paragraph span's own edges (0 and the
    /// paragraph's length) - `secondLinkOpen`/`secondLinkClose`, further inside the same
    /// paragraph, stayed collapsed despite the whole paragraph supposedly being revealed.
    @Test func aParagraphEntirelyCoveredRevealsEveryInlineMarkerNotJustEdgeAlignedOnes() {
        let note = "[[Uno]] e [[Due]]\n"
        let wholeParagraph = NSRange(location: 0, length: (note as NSString).length)
        let displayed = MarkupHidingFixture.displayedParagraph(
            note,
            markers: [Self.firstLinkOpen, Self.firstLinkClose, Self.secondLinkOpen, Self.secondLinkClose],
            revealed: [0],
            spans: [0: [wholeParagraph]],
            revealsInlineSpans: true
        )

        #expect(displayed == nil)
    }

    // MARK: R-05 - nested spans, innermost revealed, only the outer collapses

    @Test func onlyTheOuterRunsMarkersCollapseWhenTheInnerSpanIsRevealed() {
        let markers = [Self.outerOpen, Self.outerClose, Self.innerOpen, Self.innerClose]
        let collapsing = EditorDecorationDelegate.collapsing(
            among: markers, paragraphIsRevealed: true, revealedSpans: [Self.innerSpan]
        )

        #expect(collapsing.contains(Self.outerOpen))
        #expect(collapsing.contains(Self.outerClose))
        #expect(!collapsing.contains(Self.innerOpen))
        #expect(!collapsing.contains(Self.innerClose))
    }

    // MARK: Regression (R-11 hand check) - the reverse nesting direction: only the outer
    // span revealed, the inner delimiters must stay hidden rather than reveal by loose
    // geometric containment

    /// Found by the hand check, not by a fixture: an inner run's tiny delimiter range is
    /// geometrically inside its outer run's wider range by construction (nesting), so a
    /// "does `revealedSpans` contain this marker's range" test answers yes for the inner
    /// delimiters even when only the *outer* span is revealed - the caret sitting in
    /// "bold con dentro" but outside "corsivo" wrongly showed every asterisk, single and
    /// double alike. `onlyTheOuterRunsMarkersCollapseWhenTheInnerSpanIsRevealed` above
    /// never caught this: it only revealed the *inner* span, and an outer marker's range
    /// is never inside the inner span either way, so that direction had no chance to
    /// exercise the bug.
    @Test func onlyTheInnerRunsMarkersStayCollapsedWhenOnlyTheOuterSpanIsRevealed() {
        let markers = [Self.outerOpen, Self.outerClose, Self.innerOpen, Self.innerClose]
        let outerSpan = NSRange(
            location: Self.outerOpen.range.location,
            length: NSMaxRange(Self.outerClose.range) - Self.outerOpen.range.location
        )
        let collapsing = EditorDecorationDelegate.collapsing(
            among: markers, paragraphIsRevealed: true, revealedSpans: [outerSpan]
        )

        #expect(!collapsing.contains(Self.outerOpen))
        #expect(!collapsing.contains(Self.outerClose))
        #expect(collapsing.contains(Self.innerOpen))
        #expect(collapsing.contains(Self.innerClose))
    }

    // MARK: R-06 - which unit governs a marker is a property of its kind, not a rule someone
    // has to remember to opt into

    @Test func aHeadingMarkerStaysGovernedByTheParagraphWhileABoldPairIsSpanGrained() {
        let markers = [Self.headingMarker, Self.boldOpen, Self.boldClose]
        let collapsing = EditorDecorationDelegate.collapsing(
            among: markers, paragraphIsRevealed: true, revealedSpans: []
        )

        // Paragraph-grained: revealed, so it stays out of the collapsing set.
        #expect(!collapsing.contains(Self.headingMarker))
        // Span-grained: no span touches either delimiter, so both collapse.
        #expect(collapsing.contains(Self.boldOpen))
        #expect(collapsing.contains(Self.boldClose))
    }

    @Test func aRuleMarkerStaysGovernedByTheParagraphRegardlessOfTheSpanTable() {
        let collapsedWhenNotRevealed = EditorDecorationDelegate.collapsing(
            among: [Self.ruleMarker], paragraphIsRevealed: false, revealedSpans: []
        )
        let shownWhenRevealed = EditorDecorationDelegate.collapsing(
            among: [Self.ruleMarker], paragraphIsRevealed: true, revealedSpans: []
        )

        #expect(collapsedWhenNotRevealed.contains(Self.ruleMarker))
        #expect(shownWhenRevealed.isEmpty)
    }

    // MARK: isInline - exhaustive by kind (a compile-checked exhaustive switch: no `default`
    // case can have slipped in, or this file would not build)

    @Test func isInlineIsTrueOnlyForEmphasisStrikethroughAndLink() {
        #expect(HiddenMarker.Kind.emphasis.isInline)
        #expect(HiddenMarker.Kind.strikethrough.isInline)
        #expect(HiddenMarker.Kind.link.isInline)
    }

    @Test func isInlineIsFalseForEveryBlockKind() {
        #expect(!HiddenMarker.Kind.heading.isInline)
        #expect(!HiddenMarker.Kind.embed.isInline)
        #expect(!HiddenMarker.Kind.list.isInline)
        #expect(!HiddenMarker.Kind.checkbox.isInline)
        #expect(!HiddenMarker.Kind.blockquote.isInline)
        #expect(!HiddenMarker.Kind.rule.isInline)
        #expect(!HiddenMarker.Kind.table.isInline)
        #expect(!HiddenMarker.Kind.viewBlock.isInline)
    }

    // MARK: apply(revealedSpans:) - returns what changed, like apply(revealedParagraphs:)

    @Test func applyRevealedSpansReturnsTheChangedKeysAndSettlesToEmptyOnASecondClear() {
        let delegate = EditorDecorationDelegate()

        let firstChange = delegate.apply(
            revealedSpans: [3: [NSRange(location: 0, length: 2)], 5: [NSRange(location: 1, length: 1)]]
        )
        #expect(firstChange == Set([3, 5]))

        let cleared = delegate.apply(revealedSpans: [:])
        #expect(cleared == Set([3, 5]))

        let clearedAgain = delegate.apply(revealedSpans: [:])
        #expect(clearedAgain.isEmpty)
    }

    /// A key present on both sides of the call is not "unchanged" on its own - its value
    /// can still grow or shrink, the shape a drag-to-select produces as the selection keeps
    /// extending *inside* a paragraph already in the table (issue #191 follow-up: this
    /// paragraph never got told to redraw, and kept showing the first, smaller answer, for
    /// exactly this reason before the fix). A plain `symmetricDifference` of the two key
    /// sets would answer `[]` here, since key `3` is in both tables.
    @Test func applyRevealedSpansFlagsAKeyWhoseValueChangedEvenThoughItStaysPresent() {
        let delegate = EditorDecorationDelegate()
        _ = delegate.apply(revealedSpans: [3: [NSRange(location: 0, length: 2)]])

        let changed = delegate.apply(
            revealedSpans: [3: [NSRange(location: 0, length: 2), NSRange(location: 5, length: 3)]]
        )

        #expect(changed == Set([3]))
    }
}
