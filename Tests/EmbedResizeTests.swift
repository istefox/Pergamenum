import AppKit
import Testing
@testable import Pergamenum

// `EmbedResize` (ADR-0019: "A drawn embed is resized by dragging it, and the size is
// written into the note"). Plan
// `docs/superpowers/plans/2026-08-23-ridimensionamento-maniglie-embed-editor.md`, Task 2:
// the whole size grammar and the whole handle geometry, pure - no `NSTextView`, no
// delegate, matching `EmbedNavigationTests`'s own split from the wiring that reaches it.
//
// One fixture aspect ratio throughout the resolving and writing sections: `natural =
// CGSize(width: 200, height: 100)`, a clean 2:1 landscape thumbnail, so a proportional
// height is always exactly half the width and every clamp lands on a value with no
// floating-point remainder.

private let natural = CGSize(width: 200, height: 100)
private let column: CGFloat = 600

// MARK: - Reading (R-08)

@Test func writtenReadsAWidthOnlySuffix() {
    #expect(EmbedResize.written(inRun: "![[foto.png|300]]") == .width(300))
}

@Test func writtenReadsAWidthByHeightSuffix() {
    #expect(EmbedResize.written(inRun: "![[foto.png|300x200]]") == .both(300, 200))
}

@Test func writtenAnswersNilForAWikilinkWithNoSuffixAtAll() {
    #expect(EmbedResize.written(inRun: "![[foto.png]]") == nil)
}

@Test func writtenAnswersNilForTheCommonMarkSpelling() {
    // ADR-0019 §D7: Obsidian's verified sizing syntax only exists for the wikilink form.
    #expect(EmbedResize.written(inRun: "![alt](foto.png)") == nil)
}

@Test(arguments: [
    "![[foto.png|abc]]",       // not a number at all
    "![[foto.png|300x]]",      // a dangling separator with no height
    "![[foto.png|-5]]",        // negative, not a size
    "![[foto.png|300X200]]",   // capital X - Obsidian's own syntax is lowercase only
])
func writtenAnswersNilForAMalformedSuffix(_ run: String) {
    #expect(EmbedResize.written(inRun: run) == nil)
}

@Test func writtenTreatsLeadingIndentationTheWayEmbedRunInLineAlreadyDoes() {
    // `embedRun(inLine:)` trims leading/trailing whitespace before recognising the embed
    // (`EmbedRun.swift`); `written(inRun:)` reads the same syntax and tolerates the same
    // input shape rather than assuming every caller already trimmed it.
    #expect(EmbedResize.written(inRun: "   ![[foto.png|300]]") == .width(300))
}

// MARK: - Resolving (R-05, R-06)

@Test func resolvedWithNoWrittenSizeKeepsANaturalSizeAlreadyBelowTheColumn() {
    // R-06's starting size: an embed with no suffix draws at its own render/thumbnail
    // size, untouched, as long as that size already fits the column.
    #expect(EmbedResize.resolved(written: nil, natural: natural, column: column) == natural)
}

@Test func resolvedWithNoWrittenSizeClampsAnOversizedNaturalWidthAndScalesHeightProportionally() {
    let oversizedNatural = CGSize(width: 1000, height: 500)
    #expect(
        EmbedResize.resolved(written: nil, natural: oversizedNatural, column: column)
            == CGSize(width: 600, height: 300)
    )
}

@Test func resolvedWithAWrittenWidthWithinBoundsScalesHeightProportionally() {
    #expect(
        EmbedResize.resolved(written: .width(300), natural: natural, column: column)
            == CGSize(width: 300, height: 150)
    )
}

@Test func resolvedClampsAWrittenWidthBelowTheMinimumToEighty() {
    // The lower boundary, asserted explicitly: a request of 10 yields 80.
    #expect(
        EmbedResize.resolved(written: .width(10), natural: natural, column: column)
            == CGSize(width: 80, height: 40)
    )
}

@Test func resolvedClampsAWrittenWidthPastTheColumnToExactlyTheColumn() {
    // The upper boundary, asserted explicitly: a request of column + 500 yields exactly
    // the column, never past it.
    #expect(
        EmbedResize.resolved(written: .width(column + 500), natural: natural, column: column)
            == CGSize(width: 600, height: 300)
    )
}

@Test func resolvedWithBothDimensionsClampsWidthAndFloorsHeightIndependently() {
    #expect(
        EmbedResize.resolved(written: .both(10, 10), natural: natural, column: column)
            == CGSize(width: 80, height: 80)
    )
}

@Test func resolvedWithBothDimensionsClampsWidthButLeavesAnOversizedHeightFree() {
    // ADR-0019 §D3: `.both`'s height is clamped to `[80, .infinity)` only - free of both
    // the column and the aspect ratio, unlike the width it is paired with.
    #expect(
        EmbedResize.resolved(written: .both(column + 500, 5000), natural: natural, column: column)
            == CGSize(width: 600, height: 5000)
    )
}

@Test func resolvedWithBothDimensionsWithinBoundsIsUnchanged() {
    #expect(
        EmbedResize.resolved(written: .both(300, 200), natural: natural, column: column)
            == CGSize(width: 300, height: 200)
    )
}

// MARK: - Writing (R-03)

@Test func suffixIsWidthOnlyWhenTheHeightIsExactlyProportional() {
    #expect(EmbedResize.suffix(for: CGSize(width: 300, height: 150), natural: natural) == "300")
}

@Test func suffixIsWidthOnlyWhenTheHeightIsWithinAPointOfProportionalAfterRounding() {
    #expect(EmbedResize.suffix(for: CGSize(width: 300, height: 150.4), natural: natural) == "300")
}

@Test func suffixIsWidthAndHeightWhenTheRatioWasChanged() {
    #expect(EmbedResize.suffix(for: CGSize(width: 300, height: 200), natural: natural) == "300x200")
}

@Test func suffixRoundsFractionalDimensionsToIntegers() {
    // 305.6 x 210.4: the proportional height for 305.6 is 152.8, forty points from the
    // actual 210.4, so this is the "WxH" branch - and both numbers are rounded, not
    // truncated, to the nearest integer.
    #expect(EmbedResize.suffix(for: CGSize(width: 305.6, height: 210.4), natural: natural) == "306x210")
}

@Test func rewrittenReplacesAnExistingWidthSuffixRatherThanAppendingASecondOne() {
    #expect(
        EmbedResize.rewritten(run: "![[foto.png|300]]", to: CGSize(width: 400, height: 200), natural: natural)
            == "![[foto.png|400]]"
    )
}

@Test func rewrittenReplacesAnExistingBothSuffixWithANewOne() {
    #expect(
        EmbedResize.rewritten(run: "![[foto.png|300x200]]", to: CGSize(width: 400, height: 220), natural: natural)
            == "![[foto.png|400x220]]"
    )
}

@Test func rewrittenAddsASuffixWhereThereIsNone() {
    #expect(
        EmbedResize.rewritten(run: "![[foto.png]]", to: CGSize(width: 400, height: 200), natural: natural)
            == "![[foto.png|400]]"
    )
}

@Test func rewrittenAnswersNilForTheCommonMarkSpelling() {
    // ADR-0019 §D7: no note this app wrote is affected, and no note written elsewhere
    // gets a rewrite this app never verified the syntax for.
    #expect(
        EmbedResize.rewritten(run: "![alt](foto.png)", to: CGSize(width: 400, height: 200), natural: natural)
            == nil
    )
}

@Test func rewrittenAnswersNilWhenTheResolvedWidthOnlySizeMatchesWhatIsAlreadyWritten() {
    // ADR-0019 §D6's zero-movement case: `.began` immediately followed by `.ended` at the
    // same point writes nothing and leaves the run selected instead.
    #expect(
        EmbedResize.rewritten(run: "![[foto.png|300]]", to: CGSize(width: 300, height: 150), natural: natural)
            == nil
    )
}

@Test func rewrittenAnswersNilWhenTheResolvedBothSizeMatchesWhatIsAlreadyWritten() {
    #expect(
        EmbedResize.rewritten(run: "![[foto.png|300x200]]", to: CGSize(width: 300, height: 200), natural: natural)
            == nil
    )
}

// MARK: - The handle's geometry (ADR-0019 §D5, §D6)

private let pictureFrame = CGRect(x: 40, y: 60, width: 300, height: 150)

@Test func handleRectIsAFourteenPointSquare() {
    let rect = EmbedResize.handleRect(in: pictureFrame)
    #expect(rect.width == 14)
    #expect(rect.height == 14)
}

@Test func handleRectIsContainedInThePictureFrame() {
    // ADR-0019 §D5's load-bearing property: painted strictly inside the attachment's own
    // bounds, so `frameForTextAttachment(at:)` - and therefore the click hit-test and the
    // embed's accessibility frame - are unaffected by the handle's presence.
    let rect = EmbedResize.handleRect(in: pictureFrame)
    #expect(pictureFrame.contains(rect))
}

@Test func handleRectIsInsetThreePointsFromThePictureFramesBottomRightCorner() {
    let rect = EmbedResize.handleRect(in: pictureFrame)
    #expect(rect.maxX == pictureFrame.maxX - 3)
    #expect(rect.maxY == pictureFrame.maxY - 3)
}

@Test func handleHitRectIsATwentyTwoPointSquare() {
    let rect = EmbedResize.handleHitRect(in: pictureFrame)
    #expect(rect.width == 22)
    #expect(rect.height == 22)
}

@Test func handleHitRectContainsTheHandleRect() {
    // The ordinary allowance for a small control: the click target is bigger than the
    // paint, so a press near the corner still claims the drag.
    let paint = EmbedResize.handleRect(in: pictureFrame)
    let hit = EmbedResize.handleHitRect(in: pictureFrame)
    #expect(hit.contains(paint))
}
