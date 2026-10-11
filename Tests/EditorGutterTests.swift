import AppKit
import Testing
@testable import Pergamenum

// ADR-0081 §D1, §D2, §D3, §D4 and §D7, plan `docs/plans/pg-385-n2-page.md`, Task 6 (PG-385).
//
// The gutter's arithmetic, pure: no window, no layout. The hosted half is
// `GutterRevealGeometryTests.swift`. G is 48 pt (`spacing.xl + spacing.s`) and the quote step is
// 0.75 em per level, the answers to G1 (2026-10-07).
//
// The tests that pin the pre-gutter arithmetic with the new parameters defaulted are here on
// purpose: a call that passes no `gutter:` or `hanging:` lays out exactly as before ADR-0081.

private let gutter: CGFloat = 48

private func near(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
    abs(lhs - rhs) <= tolerance
}

private func width(of run: String, in font: NSFont) -> CGFloat {
    (run as NSString).size(withAttributes: [.font: font]).width
}

/// A bundled theme read from the app bundle, falling back to `.emergency` for every token it
/// lacks - `DesignSystemTests.bundledThemesDefineEveryToken`'s own load.
private func bundledTheme(_ id: String) throws -> Theme {
    let url = try #require(Bundle.pergamenumResources.tokenFileURL(named: id), "\(id).json is not in the bundle")
    let document = try DesignTokenDocument(data: try Data(contentsOf: url), fallbackName: id)
    return Theme(document: document, id: id, inheriting: .emergency)
}

// MARK: - containerInset (§D1)

@Suite struct EditorGutterContainerInset {
    private struct InsetRow {
        let label: String
        let width: CGFloat
        let isOn: Bool
        let inset: CGFloat

        init(_ label: String, _ width: CGFloat, _ isOn: Bool, _ inset: CGFloat) {
            self.label = label
            self.width = width
            self.isOn = isOn
            self.inset = inset
        }
    }

    private static func readableInset(width: CGFloat, isOn: Bool = true) -> CGFloat {
        NoteTextView.Coordinator.horizontalInset(
            viewWidth: width, cap: 720, minimum: 24, isOn: isOn
        )
    }

    /// The table of §D1 at G = 48, row by row. `inset` is what the text container gets; the
    /// content column is `inset + G` in every row.
    @Test func theContainerInsetFollowsTheTableOfSection1() { // (n2-page R-13)
        let rows = [
            InsetRow("1200 pt, readable on", 1200, true, 192),
            InsetRow("2000 pt, readable on", 2000, true, 592),
            InsetRow("816 pt, readable on (the boundary)", 816, true, 0),
            InsetRow("800 pt, readable on", 800, true, 0),
            InsetRow("768 pt, readable on", 768, true, 0),
            InsetRow("600 pt, readable on", 600, true, 0),
            InsetRow("1200 pt, readable off", 1200, false, 0),
            InsetRow("600 pt, readable off", 600, false, 0)
        ]
        for row in rows {
            let readable = Self.readableInset(width: row.width, isOn: row.isOn)
            let inset = EditorGutter.containerInset(readableInset: readable, gutter: gutter)
            #expect(near(inset, row.inset), "\(row.label): inset \(inset) invece di \(row.inset)")
        }
    }

    /// At 816 pt and above the content column is exactly where it is today, `(W - 720) / 2`, so
    /// nothing a person can see moves for concealed text; below 816 pt, or with the setting off,
    /// it is the gutter itself.
    @Test func theContentColumnIsTodaysAtReadableWidthAndTheGutterBelowIt() { // (n2-page R-13)
        for viewWidth: CGFloat in [816, 900, 1200, 2000] {
            let readable = Self.readableInset(width: viewWidth)
            let inset = EditorGutter.containerInset(readableInset: readable, gutter: gutter)
            #expect(near(inset + gutter, (viewWidth - 720) / 2), "\(viewWidth) pt")
            #expect(near(inset + gutter, readable), "\(viewWidth) pt: la colonna non e quella di oggi")
        }
        for viewWidth: CGFloat in [0, 600, 700, 768, 800] {
            let readable = Self.readableInset(width: viewWidth)
            let inset = EditorGutter.containerInset(readableInset: readable, gutter: gutter)
            #expect(near(inset + gutter, gutter), "\(viewWidth) pt")
        }
        let off = Self.readableInset(width: 2000, isOn: false)
        #expect(near(EditorGutter.containerInset(readableInset: off, gutter: gutter) + gutter, gutter))
    }

    @Test func theContainerInsetIsNeverNegative() { // (n2-page R-13)
        for readable: CGFloat in [0, 1, 24, 47.9, 48, 48.1, 100] {
            #expect(EditorGutter.containerInset(readableInset: readable, gutter: gutter) >= 0, "\(readable)")
        }
    }

    /// No gutter, no change: a surface that never pushes a gutter keeps its inset.
    @Test func withNoGutterTheInsetIsTheReadableInset() { // (n2-page R-13)
        for readable: CGFloat in [24, 100, 240] {
            #expect(near(EditorGutter.containerInset(readableInset: readable, gutter: 0), readable))
        }
    }
}

// MARK: - columnSpan (§D7)

@Suite struct EditorGutterColumnSpan {
    private static func bodyStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = gutter
        style.headIndent = gutter
        style.tailIndent = -gutter
        return style
    }

    /// A body paragraph: the column starts `padding + G` in and is the container less padding
    /// and the gutter on both sides.
    @Test func aBodyStyleSpansTheColumnBetweenItsIndents() { // (n2-page R-14)
        let span = EditorGutter.columnSpan(containerWidth: 600, padding: 5, style: Self.bodyStyle())
        #expect(near(span.leading, 5 + gutter))
        #expect(near(span.width, 600 - 2 * 5 - 2 * gutter))
    }

    /// No style in force: the whole container less its padding, which is today's definition at all
    /// four sites before ADR-0081, and still the card's.
    @Test func noStyleSpansTheContainerLessItsPadding() { // (n2-page R-14)
        let span = EditorGutter.columnSpan(containerWidth: 600, padding: 5, style: nil)
        #expect(near(span.leading, 5))
        #expect(near(span.width, 590))
    }

    /// A style with no indent at all reads like no style.
    @Test func aStyleWithNoIndentSpansTheContainerLessItsPadding() { // (n2-page R-14)
        let span = EditorGutter.columnSpan(
            containerWidth: 600, padding: 5, style: NSParagraphStyle.default
        )
        #expect(near(span.leading, 5))
        #expect(near(span.width, 590))
    }

    /// The column is the one between `headIndent` and `-tailIndent`, not between the first line's
    /// indent and the tail: a hanging list item's wrapped lines define where its column starts.
    @Test func theColumnStartsAtTheHeadIndentNotAtTheFirstLines() { // (n2-page R-14)
        let style = Self.bodyStyle()
        style.firstLineHeadIndent = 10
        style.headIndent = 90
        let span = EditorGutter.columnSpan(containerWidth: 600, padding: 5, style: style)
        #expect(near(span.leading, 5 + 90))
        #expect(near(span.width, 600 - 2 * 5 - 90 - gutter))
    }
}

// MARK: - The list column (§D2)

@Suite struct EditorGutterListColumn {
    private static var font: NSFont { .systemFont(ofSize: 20) }

    /// `C(L) = G + 1.5 em * L + 0.75 em`, and the first line starts at `max(0, C(L) - w)`; wrapped
    /// lines sit at `C(L)` itself.
    @Test func aHangingItemPutsItsContentAtTheColumnForEveryLevel() { // (n2-page R-13)
        let hanging: CGFloat = 12.5
        for level in 1...6 {
            let column = gutter + 20 * 1.5 * CGFloat(level) + 20 * 0.75
            let style = ListMarkerRendering.paragraphStyle(
                level: level, font: Self.font, gutter: gutter, hanging: hanging
            )
            #expect(near(style.headIndent, column), "livello \(level): headIndent \(style.headIndent)")
            #expect(
                near(style.firstLineHeadIndent, max(0, column - hanging)),
                "livello \(level): firstLineHeadIndent \(style.firstLineHeadIndent)"
            )
        }
    }

    /// A run wider than the column clamps the first line to zero: the content then moves by the
    /// overflow only (§D6), never to a negative indent the SDK refuses.
    @Test func aHangingRunWiderThanTheColumnClampsTheFirstLineToZero() { // (n2-page R-13)
        let style = ListMarkerRendering.paragraphStyle(
            level: 1, font: Self.font, gutter: 0, hanging: 1000
        )
        #expect(style.firstLineHeadIndent == 0)
        #expect(near(style.headIndent, 20 * 1.5 + 20 * 0.75))
    }

    /// The Workspace card has no gutter and its lists still hang (§D6): the measured run is
    /// subtracted from the column of gutter 0.
    @Test func aCardsListHangsAtGutterZero() { // (n2-page R-13)
        let style = ListMarkerRendering.paragraphStyle(level: 1, font: Self.font, gutter: 0, hanging: 12.5)
        #expect(near(style.headIndent, 45))
        #expect(near(style.firstLineHeadIndent, 32.5))
    }

    /// With a gutter and no measurement the 0.75 em constant stays the hanging default (§D2), so
    /// the first line starts `0.75 em` before the column: today's arithmetic plus G.
    @Test func withAGutterAndNoMeasurementTheGlyphWidthDefaultStays() { // (n2-page R-13)
        for level in [1, 3, 6] {
            let style = ListMarkerRendering.paragraphStyle(level: level, font: Self.font, gutter: gutter)
            #expect(near(style.firstLineHeadIndent, gutter + 20 * 1.5 * CGFloat(level)), "livello \(level)")
            #expect(near(style.headIndent, style.firstLineHeadIndent + 20 * 0.75), "livello \(level)")
        }
    }

    /// With both parameters defaulted, or given as their zero values, today's arithmetic is
    /// unchanged (`MarkupHidingListTests` pins the same numbers). Green already, on purpose.
    @Test func withBothParametersDefaultedTheArithmeticIsToday() { // (n2-page R-13)
        for level in [1, 2, 6] {
            let plain = ListMarkerRendering.paragraphStyle(level: level, font: Self.font)
            let zero = ListMarkerRendering.paragraphStyle(level: level, font: Self.font, gutter: 0, hanging: nil)
            #expect(near(plain.firstLineHeadIndent, 20 * 1.5 * CGFloat(level)))
            #expect(near(plain.headIndent, plain.firstLineHeadIndent + 20 * 0.75))
            #expect(near(zero.firstLineHeadIndent, plain.firstLineHeadIndent))
            #expect(near(zero.headIndent, plain.headIndent))
        }
    }

    /// Composition stays composition: the base style's line height and its tail indent survive the
    /// item's own two indents (ADR-0030 §D6, ADR-0081 §D1: every style composed with `basedOn:`
    /// inherits the indents).
    @Test func theBaseStylesLineHeightAndTailIndentSurviveTheHangingStyle() { // (n2-page R-13)
        let base = NSMutableParagraphStyle()
        base.lineHeightMultiple = 1.4
        base.firstLineHeadIndent = gutter
        base.headIndent = gutter
        base.tailIndent = -gutter

        let style = ListMarkerRendering.paragraphStyle(
            level: 2, font: Self.font, basedOn: base, gutter: gutter, hanging: 12.5
        )

        #expect(style.lineHeightMultiple == 1.4)
        #expect(style.tailIndent == -gutter)
        #expect(near(style.headIndent, gutter + 20 * 1.5 * 2 + 20 * 0.75))
    }

    /// `contentColumn` is `C(L)` as a function of its own, the number the geometry tests compare
    /// the measured content origin against; it is the same number `paragraphStyle` hangs to.
    @Test func contentColumnIsTheColumnTheStyleHangsTo() { // (n2-page R-13)
        for level in 1...6 {
            let column = ListMarkerRendering.contentColumn(level: level, font: Self.font, gutter: gutter)
            #expect(near(column, gutter + 20 * 1.5 * CGFloat(level) + 20 * 0.75), "livello \(level)")
            let style = ListMarkerRendering.paragraphStyle(
                level: level, font: Self.font, gutter: gutter, hanging: 12.5
            )
            #expect(near(column, style.headIndent), "livello \(level)")
        }
        // The level clamp of `paragraphStyle` (1...6) applies here too.
        #expect(near(
            ListMarkerRendering.contentColumn(level: 99, font: Self.font, gutter: gutter),
            ListMarkerRendering.contentColumn(level: 6, font: Self.font, gutter: gutter)
        ))
    }
}

// MARK: - The quote column (§D3)

@Suite struct EditorGutterQuoteColumn {
    private static var font: NSFont { .systemFont(ofSize: 20) }

    /// G1 (2026-10-07): 0.75 em per level.
    @Test func theQuoteStepIsThreeQuartersOfAnEm() { // (n2-page R-14)
        #expect(EditorGutter.quoteStepInEms == 0.75)
    }

    /// `C_q(Q) = G + 0.75 em * Q`.
    @Test func aQuoteColumnIsTheGutterPlusOneStepPerLevel() { // (n2-page R-14)
        for level in 1...4 {
            let column = EditorGutter.quoteColumn(level: level, font: Self.font, gutter: gutter)
            #expect(near(column, gutter + 0.75 * 20 * CGFloat(level)), "livello \(level): \(column)")
        }
    }

    @Test func aQuoteColumnWithoutAGutterIsTheStepAlone() { // (n2-page R-14)
        #expect(near(EditorGutter.quoteColumn(level: 2, font: Self.font, gutter: 0), 0.75 * 20 * 2))
    }

    /// The step is in ems of the page's face, so a bigger face steps further.
    @Test func theStepScalesWithTheFace() { // (n2-page R-14)
        let small = EditorGutter.quoteColumn(level: 1, font: .systemFont(ofSize: 10), gutter: gutter)
        let large = EditorGutter.quoteColumn(level: 1, font: .systemFont(ofSize: 30), gutter: gutter)
        #expect(near(small, gutter + 7.5))
        #expect(near(large, gutter + 22.5))
    }
}

// MARK: - The heading marker face (§D4)

@Suite struct EditorGutterMarkerFace {
    private static func themes() throws -> [(id: String, theme: Theme)] {
        [
            ("emergency", Theme.emergency),
            ("pergamenum-light", try bundledTheme("pergamenum-light")),
            ("pergamenum-dark", try bundledTheme("pergamenum-dark"))
        ]
    }

    /// ADR-0081 §D4's loud failure: `###### ` drawn in the marker face is narrower than the
    /// gutter, for `.emergency` and both bundled themes, so a theme that enlarges the face or
    /// shrinks the gutter fails here instead of shifting headings again.
    @Test func sixHashesAndASpaceFitInTheGutterInTheMarkerFace() throws { // (n2-page R-14)
        for (id, theme) in try Self.themes() {
            let face = ProseTypography.gutterMarker(theme)
            let measured = width(of: "###### ", in: face)
            let gutterWidth = theme.spacing(.gutter)
            #expect(
                measured < gutterWidth,
                """
                \(id): «###### » misura \(measured) pt in \(face.fontName) \(face.pointSize) pt, \
                grondaia \(gutterWidth) pt
                """
            )
        }
    }

    /// G1 (2026-10-07): the revealed `#` run is in the caption face.
    @Test func theMarkerFaceIsTheCaptionFace() throws { // (n2-page R-14)
        for (id, theme) in try Self.themes() {
            #expect(ProseTypography.gutterMarker(theme) == theme.nsFont(.caption), "\(id)")
        }
    }
}

// MARK: - The base style and the transcluded picture (§D1)

@Suite struct EditorGutterBaseStyle {
    private static func style(_ attributes: [NSAttributedString.Key: Any]) -> NSParagraphStyle? {
        attributes[.paragraphStyle] as? NSParagraphStyle
    }

    /// `base(theme:gutter:)` with a gutter puts both head indents at G and the tail at `-G`.
    @Test func theBaseStyleCarriesTheGutterAsItsIndents() { // (n2-page R-13)
        let style = Self.style(MarkdownAttributedText.base(theme: .emergency, gutter: gutter))
        #expect(style?.firstLineHeadIndent == gutter)
        #expect(style?.headIndent == gutter)
        #expect(style?.tailIndent == -gutter)
        // Composed, not replaced: the page's line height is still there.
        #expect(style?.lineHeightMultiple == ProseTypography.paragraphStyle(.emergency).lineHeightMultiple)
    }

    /// Every other surface shares `base` with the default: no indents at all. Green already.
    @Test func theDefaultBaseStyleCarriesNoIndent() { // (n2-page R-13)
        let style = Self.style(MarkdownAttributedText.base(theme: .emergency))
        #expect(style?.firstLineHeadIndent == 0)
        #expect(style?.headIndent == 0)
        #expect(style?.tailIndent == 0)
    }

    /// `StyleContext` hands the gutter to `base`, and a heading's style, composed onto the base,
    /// inherits the indents "for free" (§D1).
    @Test func theStyleContextPassesTheGutterToItsBaseAndToHeadings() { // (n2-page R-13)
        var context = MarkdownAttributedText.StyleContext(theme: .emergency, links: true, gutter: gutter)
        let base = Self.style(context.base)
        #expect(base?.headIndent == gutter)
        #expect(base?.tailIndent == -gutter)

        let heading = Self.style(context.attributes(for: .heading(level: 2)))
        #expect(heading?.firstLineHeadIndent == gutter)
        #expect(heading?.headIndent == gutter)
        #expect(heading?.tailIndent == -gutter)
    }

    @Test func aStyleContextWithoutAGutterIsToday() { // (n2-page R-13)
        let context = MarkdownAttributedText.StyleContext(theme: .emergency, links: true)
        let base = Self.style(context.base)
        #expect(base?.headIndent == 0)
        #expect(base?.tailIndent == 0)
    }

    /// ADR-0081 §D1, last sentence: a transcluded note's drawn copy keeps `gutter: 0`.
    @Test func theTranscludedPictureKeepsNoGutter() { // (n2-page R-14)
        let picture = MarkdownAttributedText.attributed("# Titolo\n\ncorpo\n", theme: .emergency)
        for offset in [0, 10] {
            let style = picture.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
            #expect(style?.headIndent == 0, "offset \(offset)")
            #expect(style?.firstLineHeadIndent == 0, "offset \(offset)")
            #expect(style?.tailIndent == 0, "offset \(offset)")
        }
    }
}
