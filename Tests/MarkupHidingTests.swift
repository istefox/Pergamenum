import AppKit
import Testing
@testable import Pergamenum

/// ADR-0018 §D1's mechanism, offscreen: hiding a heading's `#` marker (and the space
/// after it) costs no width and leaves the line height unchanged - the same kind of fact
/// `TransclusionLayoutTests` measured for the sibling mechanism that reserves space
/// instead of removing it, and the one `docs/20260817_TextKit2_live_editing.md` first
/// measured (32.12pt recovered over 4 hidden characters via a 0.01pt font).
///
/// Driven against the real `EditorDecorationDelegate`, not a test double: unlike
/// `TransclusionLayoutTests`'s `SpacingDelegate`, this hook carries logic worth testing on
/// its own account - the setting's on/off switch, the reveal set, and the re-check that
/// keeps a stale table from collapsing prose.

@MainActor
@Suite struct MarkupHiding {
    private static let note = "# Titolo\ncorpo\n"
    private static let headingOffset = 0
    /// "# " - the hash and the one space after it, relative to the paragraph's own start.
    private static let marker = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .heading)

    @Test func aCollapsedMarkerCostsNoWidth() {
        let base = MarkupHidingFixture.frames(text: Self.note, markers: [:], hidesMarkup: false)
        let collapsed = MarkupHidingFixture.frames(
            text: Self.note, markers: [Self.headingOffset: [Self.marker]], hidesMarkup: true
        )

        let baseHeading = base.frames.first { $0.offset == Self.headingOffset }?.frame
        let collapsedHeading = collapsed.frames.first { $0.offset == Self.headingOffset }?.frame
        #expect(baseHeading != nil)
        #expect(collapsedHeading != nil)
        #expect((collapsedHeading?.width ?? 0) < (baseHeading?.width ?? 0))
        // Never a character added or removed, whatever is drawn.
        #expect(base.length == collapsed.length)
    }

    @Test func lineHeightIsUnchangedByTheCollapse() {
        let base = MarkupHidingFixture.frames(text: Self.note, markers: [:], hidesMarkup: false)
        let collapsed = MarkupHidingFixture.frames(
            text: Self.note, markers: [Self.headingOffset: [Self.marker]], hidesMarkup: true
        )

        let baseHeading = base.frames.first { $0.offset == Self.headingOffset }?.frame
        let collapsedHeading = collapsed.frames.first { $0.offset == Self.headingOffset }?.frame
        #expect(collapsedHeading?.height == baseHeading?.height)
    }

    @Test func theHookReturnsNilForARevealedParagraph() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [Self.headingOffset: [Self.marker]], hidingMarkup: true)
        _ = delegate.apply(revealedParagraphs: [Self.headingOffset])

        #expect(MarkupHidingFixture.substitutedParagraph(delegate, note: Self.note) == nil)
    }

    @Test func aStaleTableEntryDoesNotCollapseProse() {
        // The table still says a heading marker sits at offset 0, but the text there has
        // since become plain prose - the last styling pass has not caught up with this
        // layout pass yet.
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [0: [Self.marker]], hidingMarkup: true)

        #expect(MarkupHidingFixture.substitutedParagraph(delegate, note: "corpo\ndopo\n") == nil)
    }

    @Test func theHookIsInertWhenTheSettingIsOff() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [Self.headingOffset: [Self.marker]], hidingMarkup: false)

        #expect(MarkupHidingFixture.substitutedParagraph(delegate, note: Self.note) == nil)
    }
}

// MARK: - The emphasis marker (ADR-0018 §D1, slice 2)

@MainActor
@Suite struct MarkupHidingEmphasis {
    private static let note = "testo **grassetto** qui\ncorpo\n"
    private static let paragraphOffset = 0
    /// The two `**` delimiters of "**grassetto**", relative to the paragraph's own start.
    private static let openMarker = HiddenMarker(range: NSRange(location: 6, length: 2), kind: .emphasis)
    private static let closeMarker = HiddenMarker(range: NSRange(location: 17, length: 2), kind: .emphasis)

    @Test func aCollapsedEmphasisPairCostsWidthAndKeepsTheLengthIdentical() {
        let base = MarkupHidingFixture.frames(text: Self.note, markers: [:], hidesMarkup: false)
        let collapsed = MarkupHidingFixture.frames(
            text: Self.note,
            markers: [Self.paragraphOffset: [Self.openMarker, Self.closeMarker]],
            hidesMarkup: true
        )

        let baseParagraph = base.frames.first { $0.offset == Self.paragraphOffset }?.frame
        let collapsedParagraph = collapsed.frames.first { $0.offset == Self.paragraphOffset }?.frame
        #expect(baseParagraph != nil)
        #expect(collapsedParagraph != nil)
        #expect((collapsedParagraph?.width ?? 0) < (baseParagraph?.width ?? 0))
        #expect(base.length == collapsed.length)
    }

    @Test func lineHeightIsUnchangedByAnEmphasisCollapse() {
        let base = MarkupHidingFixture.frames(text: Self.note, markers: [:], hidesMarkup: false)
        let collapsed = MarkupHidingFixture.frames(
            text: Self.note,
            markers: [Self.paragraphOffset: [Self.openMarker, Self.closeMarker]],
            hidesMarkup: true
        )

        let baseParagraph = base.frames.first { $0.offset == Self.paragraphOffset }?.frame
        let collapsedParagraph = collapsed.frames.first { $0.offset == Self.paragraphOffset }?.frame
        #expect(collapsedParagraph?.height == baseParagraph?.height)
    }

    @Test func aParagraphWithAHeadingAndAnEmphasisMarkerCollapsesBothInOneSubstitution() {
        let note = "# Titolo **enfasi** qui\n"
        let headingMarker = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .heading)
        // "**enfasi**" starts right after "# Titolo " (9 characters).
        let open = HiddenMarker(range: NSRange(location: 9, length: 2), kind: .emphasis)
        let close = HiddenMarker(range: NSRange(location: 17, length: 2), kind: .emphasis)

        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [0: [headingMarker, open, close]], hidingMarkup: true)

        let paragraph = MarkupHidingFixture.substitutedParagraph(delegate, note: note)
        #expect(paragraph != nil)
        // Never a character added or removed by the substitution.
        #expect(paragraph?.attributedString.length == (note as NSString).paragraphRange(
            for: NSRange(location: 0, length: 0)
        ).length)
    }

    @Test func aStaleEmphasisEntryDoesNotCollapseProse() {
        // The table still says a pair of `*` sits at this range, but the text there has
        // since become plain prose.
        let delegate = EditorDecorationDelegate()
        let stale = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .emphasis)
        delegate.apply(hiddenMarkers: [0: [stale]], hidingMarkup: true)

        #expect(MarkupHidingFixture.substitutedParagraph(delegate, note: "corpo\ndopo\n") == nil)
    }

    @Test func theHookIsInertForEmphasisWhenTheSettingIsOff() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(
            hiddenMarkers: [Self.paragraphOffset: [Self.openMarker, Self.closeMarker]],
            hidingMarkup: false
        )

        #expect(MarkupHidingFixture.substitutedParagraph(delegate, note: Self.note) == nil)
    }
}

// MARK: - The strikethrough marker (ADR-0029 §D1; plan 2026-09-02-editor-wysiwyg-unification, Task 2)

/// The exact twin of `MarkupHidingEmphasis` above, for `.strikethrough` instead of
/// `.emphasis` - the ADR's own description of the construct.
@MainActor
@Suite struct MarkupHidingStrikethrough {
    private static let note = "testo ~~cancellato~~ qui\ncorpo\n"
    private static let paragraphOffset = 0
    /// The two `~~` delimiters of "~~cancellato~~", relative to the paragraph's own start.
    private static let openMarker = HiddenMarker(range: NSRange(location: 6, length: 2), kind: .strikethrough)
    private static let closeMarker = HiddenMarker(range: NSRange(location: 18, length: 2), kind: .strikethrough)

    @Test func aCollapsedStrikethroughPairCostsWidthAndKeepsTheLengthIdentical() {
        let base = MarkupHidingFixture.frames(text: Self.note, markers: [:], hidesMarkup: false)
        let collapsed = MarkupHidingFixture.frames(
            text: Self.note,
            markers: [Self.paragraphOffset: [Self.openMarker, Self.closeMarker]],
            hidesMarkup: true
        )

        let baseParagraph = base.frames.first { $0.offset == Self.paragraphOffset }?.frame
        let collapsedParagraph = collapsed.frames.first { $0.offset == Self.paragraphOffset }?.frame
        #expect(baseParagraph != nil)
        #expect(collapsedParagraph != nil)
        #expect((collapsedParagraph?.width ?? 0) < (baseParagraph?.width ?? 0))
        #expect(base.length == collapsed.length)
    }

    @Test func theHookReturnsNilForARevealedStrikethroughParagraph() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(
            hiddenMarkers: [Self.paragraphOffset: [Self.openMarker, Self.closeMarker]], hidingMarkup: true
        )
        _ = delegate.apply(revealedParagraphs: [Self.paragraphOffset])

        #expect(MarkupHidingFixture.substitutedParagraph(delegate, note: Self.note) == nil)
    }

    @Test func aStaleStrikethroughEntryDoesNotCollapseProse() {
        let delegate = EditorDecorationDelegate()
        let stale = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .strikethrough)
        delegate.apply(hiddenMarkers: [0: [stale]], hidingMarkup: true)

        #expect(MarkupHidingFixture.substitutedParagraph(delegate, note: "corpo\ndopo\n") == nil)
    }

    @Test func theHookIsInertForStrikethroughWhenTheSettingIsOff() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(
            hiddenMarkers: [Self.paragraphOffset: [Self.openMarker, Self.closeMarker]], hidingMarkup: false
        )

        #expect(MarkupHidingFixture.substitutedParagraph(delegate, note: Self.note) == nil)
    }
}

// MARK: - The link/wikilink bracket marker and its tooltip (ADR-0029 §D1, R-04; Task 2)

/// A wikilink's `[[`/`]]` or a CommonMark link's `[`/`](url)` gets the same character-for-
/// character hiding as a heading or emphasis marker, plus a `.toolTip` naming where the
/// concealed link goes - a hook this repo had never called before this chain.
///
/// Each fixture constructs its own `HiddenMarker(kind: .link)` pair by hand, at the bracket
/// positions only - never over the label/target text between them - independent of how
/// `MarkdownStyler`/`NoteTextView+Coordinator` eventually produce them, the same way every
/// other suite in this file is independent of the real styling pipeline.
@MainActor
@Suite struct MarkupHidingLink {
    // "vedi [[Curva]] qui\n" - "[[" at (5,2), "]]" at (12,2).
    private static let wikilink = "vedi [[Curva]] qui\n"
    private static let wikilinkOpen = HiddenMarker(range: NSRange(location: 5, length: 2), kind: .link)
    private static let wikilinkClose = HiddenMarker(range: NSRange(location: 12, length: 2), kind: .link)

    // "vedi [testo](https://x.it) qui\n" - "[" at (5,1), "](https://x.it)" at (11,15).
    private static let commonMarkLink = "vedi [testo](https://x.it) qui\n"
    private static let commonMarkOpen = HiddenMarker(range: NSRange(location: 5, length: 1), kind: .link)
    private static let commonMarkClose = HiddenMarker(range: NSRange(location: 11, length: 15), kind: .link)

    @Test func aCollapsedWikilinkBracketPairCostsWidthAndKeepsTheLengthIdentical() {
        let base = MarkupHidingFixture.frames(text: Self.wikilink, markers: [:], hidesMarkup: false)
        let collapsed = MarkupHidingFixture.frames(
            text: Self.wikilink, markers: [0: [Self.wikilinkOpen, Self.wikilinkClose]], hidesMarkup: true
        )

        let baseParagraph = base.frames.first { $0.offset == 0 }?.frame
        let collapsedParagraph = collapsed.frames.first { $0.offset == 0 }?.frame
        #expect(baseParagraph != nil)
        #expect(collapsedParagraph != nil)
        #expect((collapsedParagraph?.width ?? 0) < (baseParagraph?.width ?? 0))
        #expect(base.length == collapsed.length)
    }

    @Test func aConcealedWikilinkCarriesATooltipWithTheResolvedTitle() {
        let displayed = MarkupHidingFixture.displayedParagraph(
            Self.wikilink, markers: [Self.wikilinkOpen, Self.wikilinkClose]
        )
        #expect(displayed != nil)

        var found = false
        displayed?.attributedString.enumerateAttribute(
            .toolTip, in: NSRange(location: 0, length: displayed?.attributedString.length ?? 0)
        ) { value, _, _ in
            if let title = value as? String, title == "Curva" { found = true }
        }
        #expect(found, "nessun .toolTip \"Curva\" trovato nel paragrafo sostituito")
    }

    @Test func aConcealedCommonMarkLinkCarriesTheURLAsItsTooltip() {
        let displayed = MarkupHidingFixture.displayedParagraph(
            Self.commonMarkLink, markers: [Self.commonMarkOpen, Self.commonMarkClose]
        )
        #expect(displayed != nil)

        var found = false
        displayed?.attributedString.enumerateAttribute(
            .toolTip, in: NSRange(location: 0, length: displayed?.attributedString.length ?? 0)
        ) { value, _, _ in
            if let url = value as? String, url == "https://x.it" { found = true }
        }
        #expect(found, "nessun .toolTip \"https://x.it\" trovato nel paragrafo sostituito")
    }

    @Test func theHookReturnsNilForARevealedLinkParagraph() {
        #expect(
            MarkupHidingFixture.displayedParagraph(
                Self.wikilink, markers: [Self.wikilinkOpen, Self.wikilinkClose], revealed: [0]
            ) == nil
        )
    }

    @Test func aStaleLinkEntryDoesNotCollapseProse() {
        let stale = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .link)
        #expect(MarkupHidingFixture.displayedParagraph("corpo\ndopo\n", markers: [stale]) == nil)
    }

    @Test func theHookIsInertForLinkWhenTheSettingIsOff() {
        #expect(
            MarkupHidingFixture.displayedParagraph(
                Self.wikilink, markers: [Self.wikilinkOpen, Self.wikilinkClose], hidesMarkup: false
            ) == nil
        )
    }
}

// MARK: - The horizontal rule (ADR-0029 §D1; Task 2)

/// A whole thematic-break line collapses into `EditorDecorationDelegate.collapsedFont`, the
/// same generic substitution `MarkupHiding`'s own heading suite exercises, and is laid out
/// through a `HorizontalRuleFragment` rather than the standard fragment.
@MainActor
private func fragments(
    text: String, markers: [Int: [HiddenMarker]], hidesMarkup: Bool
) -> [Int: NSTextLayoutFragment] {
    let content = NSTextContentStorage()
    let layout = NSTextLayoutManager()
    content.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    layout.textContainer = container

    let delegate = EditorDecorationDelegate()
    delegate.apply(hiddenMarkers: markers, hidingMarkup: hidesMarkup)
    content.delegate = delegate
    layout.delegate = delegate

    content.textStorage?.setAttributedString(
        NSAttributedString(
            string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]
        )
    )
    layout.ensureLayout(for: layout.documentRange)

    var byOffset: [Int: NSTextLayoutFragment] = [:]
    layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
        let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        byOffset[offset] = fragment
        return true
    }
    return byOffset
}

@MainActor
@Suite struct MarkupHidingRule {
    private static let note = "---\ncorpo\n"
    private static let marker = HiddenMarker(range: NSRange(location: 0, length: 3), kind: .rule)

    @Test func aRuleParagraphCollapsesEntirelyIntoTheCollapsedFontAndKeepsItsLength() {
        let displayed = MarkupHidingFixture.displayedParagraph(Self.note, markers: [Self.marker])
        #expect(displayed != nil, "nessuna sostituzione")
        #expect(displayed?.attributedString.length == MarkupHidingFixture.firstParagraphLength(of: Self.note))
        for offset in 0..<3 {
            #expect(
                (displayed?.attributedString.attribute(.font, at: offset, effectiveRange: nil) as? NSFont)
                    == EditorDecorationDelegate.collapsedFont,
                "offset \(offset) non è nel font collassato"
            )
        }
    }

    @Test func aRuleParagraphIsLaidOutAsAHorizontalRuleFragment() {
        let laidOut = fragments(text: Self.note, markers: [0: [Self.marker]], hidesMarkup: true)
        #expect(laidOut[0] is HorizontalRuleFragment)
    }

    @Test func theHookReturnsNilForARevealedRuleParagraph() {
        #expect(MarkupHidingFixture.displayedParagraph(Self.note, markers: [Self.marker], revealed: [0]) == nil)
    }

    @Test func aStaleRuleEntryDoesNotCollapseProse() {
        let stale = HiddenMarker(range: NSRange(location: 0, length: 3), kind: .rule)
        #expect(MarkupHidingFixture.displayedParagraph("corpo\ndopo\n", markers: [stale]) == nil)
    }

    @Test func theRuleHookIsInertWhenTheSettingIsOff() {
        #expect(MarkupHidingFixture.displayedParagraph(Self.note, markers: [Self.marker], hidesMarkup: false) == nil)
    }
}
