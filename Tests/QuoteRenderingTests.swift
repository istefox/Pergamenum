import AppKit
import Testing
@testable import Pergamenum

/// ADR-0029 §D1 (plan `2026-09-02-editor-wysiwyg-unification`, Task 2): a blockquote's `>`
/// run is substituted one `▏` per nesting level, character for character - unbounded, since
/// the file's own `>` count is the depth (R-03).
///
/// Driven against `EditorDecorationDelegate.quoteParagraph(at:storage:)` directly, the way
/// `Tests/MarkupHidingTests.swift`'s own suites drive the delegate's other branches - a
/// `HiddenMarker` fixture built by hand, never through the real `MarkdownStyler`/Coordinator
/// pipeline, which is a separate (coordinator-level) concern this batch does not test.

/// The length of `note`'s paragraph starting at `location` (the first paragraph by
/// default) - the number a substitution of it must return unchanged.
private func firstParagraphLength(of note: String, at location: Int = 0) -> Int {
    (note as NSString).paragraphRange(for: NSRange(location: location, length: 0)).length
}

@MainActor
private func quoteParagraph(
    _ note: String,
    markers: [HiddenMarker],
    at location: Int = 0,
    hidesMarkup: Bool = true,
    revealed: Set<Int> = [],
    gutter: CGFloat = 0,
    proseFont: NSFont? = nil,
    baseStyle: NSParagraphStyle? = nil
) -> NSTextParagraph? {
    let delegate = EditorDecorationDelegate()
    delegate.gutter = gutter
    if let proseFont { delegate.proseFont = proseFont }
    delegate.apply(hiddenMarkers: [location: markers], hidingMarkup: hidesMarkup)
    _ = delegate.apply(revealedParagraphs: revealed)

    let content = NSTextContentStorage()
    var attributes: [NSAttributedString.Key: Any] = [:]
    if let baseStyle { attributes[.paragraphStyle] = baseStyle }
    content.textStorage?.setAttributedString(NSAttributedString(string: note, attributes: attributes))
    guard let storage = content.textStorage else { return nil }
    let range = (note as NSString).paragraphRange(for: NSRange(location: location, length: 0))
    return delegate.quoteParagraph(at: range, storage: storage)
}

@MainActor
@Suite struct QuoteRendering {
    private static let twoLevels = ">> due\ncorpo\n"
    /// ">> " - the two `>` and the trailing space, relative to the paragraph's own start.
    private static let twoLevelMarker = HiddenMarker(range: NSRange(location: 0, length: 3), kind: .blockquote)

    @Test func aTwoLevelQuoteDisplaysOneBarPerLevelWithTheParagraphLengthUnmoved() {
        let displayed = quoteParagraph(Self.twoLevels, markers: [Self.twoLevelMarker])

        #expect(displayed != nil)
        // One `▏` per level, character for character - the space and "due\n" untouched.
        #expect(displayed?.attributedString.string == "▏▏ due\n")
        #expect(displayed?.attributedString.length == firstParagraphLength(of: Self.twoLevels))
    }

    /// The SPEC's coexistence case, restated for blockquote the way
    /// `aListAndAnEmphasisMarkerRenderTogetherInOneParagraph` restates it for `.list`: one
    /// paragraph, two kinds of marker, one substitution - the bar(s) drawn and the `**`
    /// pair collapsed via `Self.survivors(among:of:in:)`, the reuse this bullet names.
    @Test func aBlockquoteContainingBoldTextRendersBothItsBarAndTheCollapsedEmphasisMarkers() {
        let note = "> **grassetto**\n"
        // "> " - one `>` and its trailing space.
        let quoteMarker = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .blockquote)
        // The two `**` delimiters of "**grassetto**", which opens right after "> ".
        let openMarker = HiddenMarker(range: NSRange(location: 2, length: 2), kind: .emphasis)
        let closeMarker = HiddenMarker(range: NSRange(location: 13, length: 2), kind: .emphasis)

        let displayed = quoteParagraph(note, markers: [quoteMarker, openMarker, closeMarker])

        #expect(displayed != nil)
        #expect(displayed?.attributedString.string.first == "▏")
        // The `**` characters are still in the string - a font collapse, never a removal -
        // the same shape `aListAndAnEmphasisMarkerRenderTogetherInOneParagraph` asserts.
        #expect(displayed?.attributedString.string.hasSuffix("grassetto**\n") == true)
        #expect(displayed?.attributedString.length == firstParagraphLength(of: note))
        #expect(
            (displayed?.attributedString.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)
                == EditorDecorationDelegate.collapsedFont
        )
        #expect(
            (displayed?.attributedString.attribute(.font, at: 13, effectiveRange: nil) as? NSFont)
                == EditorDecorationDelegate.collapsedFont
        )
    }

    /// R-03/ADR-0018 §D2: the caret's own paragraph shows its raw `>` source, not the bars -
    /// asserted through `apply(revealedParagraphs:)` exactly as `MarkupHiding`'s own
    /// `theHookReturnsNilForARevealedParagraph` does for the heading marker.
    @Test func theHookReturnsNilForARevealedBlockquoteParagraph() {
        let displayed = quoteParagraph(Self.twoLevels, markers: [Self.twoLevelMarker], revealed: [0])
        #expect(displayed == nil)
    }

    /// ADR-0018 §D10's switch governs this marker kind too: off means off, whatever the
    /// reveal set says.
    @Test func theQuoteHookIsInertWhenTheSettingIsOff() {
        let displayed = quoteParagraph(Self.twoLevels, markers: [Self.twoLevelMarker], hidesMarkup: false)
        #expect(displayed == nil)
    }

    /// The `stillSpells` re-check contract, restated for blockquote: the table is filled by
    /// the last styling pass and read by a later layout pass, and the two can go stale
    /// against each other. A `.blockquote` entry whose characters no longer spell a `>` run
    /// is skipped on its own account rather than collapsing plain prose.
    @Test func aStaleBlockquoteEntryDoesNotCollapseProse() {
        let stale = HiddenMarker(range: NSRange(location: 0, length: 3), kind: .blockquote)
        let displayed = quoteParagraph("corpo\ndopo\n", markers: [stale])
        #expect(displayed == nil)
    }

    /// G2 H4 (ADR-0074): the quote branch returns early, so a link inside a quoted line has to
    /// get its tooltip from that branch itself - the non-quote twin is
    /// `MarkupHiding.aConcealedWikilinkCarriesATooltipWithTheResolvedTitle`.
    @Test func aConcealedWikilinkInsideAQuoteStillCarriesItsTooltip() {
        let note = "> vedi [[Curva]] qui\n"
        let markers = [
            HiddenMarker(range: NSRange(location: 0, length: 2), kind: .blockquote),
            HiddenMarker(range: NSRange(location: 7, length: 2), kind: .link),
            HiddenMarker(range: NSRange(location: 14, length: 2), kind: .link)
        ]

        let displayed = quoteParagraph(note, markers: markers)

        #expect(displayed?.attributedString.string.first == "▏")
        var found = false
        displayed?.attributedString.enumerateAttribute(
            .toolTip, in: NSRange(location: 0, length: displayed?.attributedString.length ?? 0)
        ) { value, _, _ in
            if let title = value as? String, title == "Curva" { found = true }
        }
        #expect(found, "nessun .toolTip \"Curva\" trovato nel paragrafo di citazione")
    }

    @Test func aConcealedCommonMarkLinkInsideAQuoteCarriesTheURLAsItsTooltip() {
        let note = "> vedi [testo](https://x.it) qui\n"
        let markers = [
            HiddenMarker(range: NSRange(location: 0, length: 2), kind: .blockquote),
            HiddenMarker(range: NSRange(location: 7, length: 1), kind: .link),
            HiddenMarker(range: NSRange(location: 13, length: 15), kind: .link)
        ]

        let displayed = quoteParagraph(note, markers: markers)

        var found = false
        displayed?.attributedString.enumerateAttribute(
            .toolTip, in: NSRange(location: 0, length: displayed?.attributedString.length ?? 0)
        ) { value, _, _ in
            if let url = value as? String, url == "https://x.it" { found = true }
        }
        #expect(found, "nessun .toolTip \"https://x.it\" trovato nel paragrafo di citazione")
    }

    // MARK: - ADR-0081 §D3: a quote hangs its bars, and its revealed run, at a gutter (n2-page R-14)

    private static let font = NSFont.systemFont(ofSize: 20)

    private static func style(_ displayed: NSTextParagraph?) -> NSParagraphStyle? {
        displayed?.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    }

    /// The sibling of `theHookReturnsNilForARevealedBlockquoteParagraph` for `gutter > 0`: the caret's
    /// quote is no longer the raw source with no style but a displayed paragraph, whose string is the
    /// source, hanging its `>> ` run to `C_q(2)`. That test stays as it is, at gutter 0 (§D6).
    @Test func aRevealedQuoteAtAGutterReturnsAHangingStyle() { // (n2-page R-14)
        let displayed = quoteParagraph(
            Self.twoLevels, markers: [Self.twoLevelMarker], revealed: [0], gutter: 48, proseFont: Self.font
        )
        let style = Self.style(displayed)
        let column = EditorGutter.quoteColumn(level: 2, font: Self.font, gutter: 48)
        let run = (">> " as NSString).size(withAttributes: [.font: Self.font]).width

        #expect(displayed != nil, "la citazione rivelata non porta uno stile")
        #expect(displayed?.attributedString.string == ">> due\n", "la citazione rivelata mostra il sorgente")
        #expect(
            abs((style?.headIndent ?? -1) - column) <= 0.5,
            "headIndent \(style?.headIndent ?? -1) invece di \(column)"
        )
        #expect(
            abs((style?.firstLineHeadIndent ?? -1) - max(0, column - run)) <= 0.5,
            "firstLineHeadIndent \(style?.firstLineHeadIndent ?? -1) invece di \(max(0, column - run))"
        )
        #expect(displayed?.attributedString.length == firstParagraphLength(of: Self.twoLevels))
    }

    /// Concealed, the bars hang the same way: the column is the same, the run is the bars.
    @Test func aConcealedQuoteAtAGutterHangsItsBarsFromTheSameColumn() { // (n2-page R-14)
        let displayed = quoteParagraph(
            Self.twoLevels, markers: [Self.twoLevelMarker], gutter: 48, proseFont: Self.font
        )
        let style = Self.style(displayed)
        let column = EditorGutter.quoteColumn(level: 2, font: Self.font, gutter: 48)
        let bars = ("\u{258F}\u{258F}" as NSString).size(withAttributes: [.font: Self.font]).width

        #expect(displayed?.attributedString.string == "▏▏ due\n")
        #expect(
            abs((style?.headIndent ?? -1) - column) <= 0.5,
            "headIndent \(style?.headIndent ?? -1) invece di \(column)"
        )
        #expect(
            abs((style?.firstLineHeadIndent ?? -1) - max(0, column - bars)) <= 0.5,
            "firstLineHeadIndent \(style?.firstLineHeadIndent ?? -1) invece di \(max(0, column - bars))"
        )
    }

    /// The quote composes on the style the paragraph already carries (§D3, Task 7's "composes on
    /// `bodyParagraphStyle(of:)`"): the page's line height and the gutter's tail indent survive.
    @Test func aQuoteAtAGutterComposesOntoTheBaseStyle() { // (n2-page R-14)
        let base = NSMutableParagraphStyle()
        base.lineHeightMultiple = 1.4
        base.firstLineHeadIndent = 48
        base.headIndent = 48
        base.tailIndent = -48

        for revealed: Set<Int> in [[], [0]] {
            let displayed = quoteParagraph(
                Self.twoLevels, markers: [Self.twoLevelMarker], revealed: revealed,
                gutter: 48, proseFont: Self.font, baseStyle: base
            )
            let style = Self.style(displayed)
            #expect(style?.lineHeightMultiple == 1.4, "rivelato=\(!revealed.isEmpty): interlinea persa")
            #expect(style?.tailIndent == -48, "rivelato=\(!revealed.isEmpty): tailIndent perso")
        }
    }

    /// ADR-0081 §D6 and the plan's "Unchanged, at gutter 0": with no gutter the concealed quote sets
    /// no paragraph style at all, so a card gains nothing it did not have. Green already.
    @Test func aConcealedQuoteAtGutterZeroSetsNoParagraphStyle() { // (n2-page R-14)
        let displayed = quoteParagraph(Self.twoLevels, markers: [Self.twoLevelMarker])
        #expect(displayed != nil)
        #expect(Self.style(displayed) == nil)
    }
}
