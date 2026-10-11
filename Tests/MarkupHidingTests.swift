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

    // MARK: ADR-0081 §D4: a revealed heading hangs its `#` run in the gutter (n2-page R-14)

    /// The displayed paragraph for `note`'s heading at offset 0, over a storage that carries the
    /// base style the editor gives every paragraph at a gutter (`headIndent = G`, `tailIndent = -G`).
    private static func gutteredHeading(
        _ note: String, marker: HiddenMarker, revealed: Bool, gutter: CGFloat, markerFont: NSFont?
    ) -> NSTextParagraph? {
        let delegate = EditorDecorationDelegate()
        delegate.gutter = gutter
        delegate.markerFont = markerFont
        delegate.apply(hiddenMarkers: [0: [marker]], hidingMarkup: true)
        _ = delegate.apply(revealedParagraphs: revealed ? [0] : [])

        let base = NSMutableParagraphStyle()
        base.firstLineHeadIndent = gutter
        base.headIndent = gutter
        base.tailIndent = -gutter
        let storage = NSTextContentStorage()
        storage.textStorage?.setAttributedString(
            NSAttributedString(string: note, attributes: [.paragraphStyle: base])
        )
        let range = (note as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        return delegate.textContentStorage(storage, textParagraphWith: range)
    }

    /// The sibling of `theHookReturnsNilForARevealedParagraph` for `gutter > 0`, which stays as it is
    /// at gutter 0 (§D6, a card keeps today's revealed shift). Revealed, the heading is no longer
    /// the raw source with no style: the paragraph is returned with its string unchanged, its first
    /// line starting `w` before the gutter (`w` = `## ` measured in the marker face), and the `#`
    /// run, and only it, in the marker face. The length is the stored length.
    @Test func aRevealedHeadingAtAGutterHangsItsHashRunInTheMarkerFace() {
        let note = "## Titolo\ncorpo\n"
        let marker = HiddenMarker(range: NSRange(location: 0, length: 3), kind: .heading)
        let face = NSFont.systemFont(ofSize: 11)

        let displayed = Self.gutteredHeading(note, marker: marker, revealed: true, gutter: 48, markerFont: face)
        let style = displayed?.attributedString
            .attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let run = ("## " as NSString).size(withAttributes: [.font: face]).width

        #expect(displayed != nil, "il titolo rivelato non porta uno stile")
        #expect(displayed?.attributedString.string == "## Titolo\n")
        #expect(displayed?.attributedString.length == MarkupHidingFixture.firstParagraphLength(of: note))
        #expect(
            abs((style?.firstLineHeadIndent ?? -1) - max(0, 48 - run)) <= 0.5,
            "firstLineHeadIndent \(style?.firstLineHeadIndent ?? -1) invece di \(max(0, 48 - run))"
        )
        // The column and the tail are the base style's, untouched.
        #expect(style?.headIndent == 48)
        #expect(style?.tailIndent == -48)
        for index in 0..<3 {
            #expect(
                (displayed?.attributedString.attribute(.font, at: index, effectiveRange: nil) as? NSFont) == face,
                "il carattere \(index) del marcatore non ha la faccia del marcatore"
            )
        }
        // The title keeps the face the styling pass gave it (none here), not the marker's.
        #expect((displayed?.attributedString.attribute(.font, at: 4, effectiveRange: nil) as? NSFont) == nil)
    }

    /// A marker run wider than the gutter clamps the first line to zero (§D6 on overflow).
    @Test func aRevealedHeadingWiderThanTheGutterClampsItsFirstLineToZero() {
        let note = "###### Titolo\n"
        let marker = HiddenMarker(range: NSRange(location: 0, length: 7), kind: .heading)
        let displayed = Self.gutteredHeading(
            note, marker: marker, revealed: true, gutter: 10, markerFont: .systemFont(ofSize: 20)
        )
        let style = displayed?.attributedString
            .attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(displayed != nil)
        #expect(style?.firstLineHeadIndent == 0)
    }

    /// Concealed, nothing hangs: the marker is collapsed, so the title already starts at the gutter
    /// the base style gave it. The style is the storage's own and the marker is the collapsed font.
    /// Green already, on purpose: the generic path is the concealed state.
    @Test func aConcealedHeadingAtAGutterKeepsTheBaseStyleAndCollapsesTheMarker() {
        let note = "## Titolo\ncorpo\n"
        let marker = HiddenMarker(range: NSRange(location: 0, length: 3), kind: .heading)
        let displayed = Self.gutteredHeading(
            note, marker: marker, revealed: false, gutter: 48, markerFont: .systemFont(ofSize: 11)
        )
        let style = displayed?.attributedString
            .attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(displayed != nil)
        #expect(style?.firstLineHeadIndent == 48)
        #expect(
            (displayed?.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
                == EditorDecorationDelegate.collapsedFont
        )
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
        let laidOut = MarkupHidingFixture.fragments(text: Self.note, markers: [0: [Self.marker]], hidesMarkup: true)
        #expect(laidOut[0] is HorizontalRuleFragment)
    }

    @Test func theHookReturnsNilForARevealedRuleParagraph() {
        #expect(MarkupHidingFixture.displayedParagraph(Self.note, markers: [Self.marker], revealed: [0]) == nil)
    }

    @Test func aStaleRuleEntryDoesNotCollapseProse() {
        let stale = HiddenMarker(range: NSRange(location: 0, length: 3), kind: .rule)
        #expect(MarkupHidingFixture.displayedParagraph("corpo\ndopo\n", markers: [stale]) == nil)
    }

    /// ADR-0082 corpus S53: the styler marks a tab-indented `\t---` as a rule over the whole line,
    /// so the generic path must collapse it and the layout must draw the rule, together.
    @Test func aTabIndentedRuleCollapsesAndIsLaidOutAsAHorizontalRuleFragment() {
        let note = "\t---\ncorpo\n"
        let tabbed = HiddenMarker(range: NSRange(location: 0, length: 4), kind: .rule)
        let displayed = MarkupHidingFixture.displayedParagraph(note, markers: [tabbed])
        #expect(displayed != nil, "the tab-indented rule's characters were not collapsed")
        for offset in 0..<4 {
            #expect(
                (displayed?.attributedString.attribute(.font, at: offset, effectiveRange: nil) as? NSFont)
                    == EditorDecorationDelegate.collapsedFont,
                "offset \(offset) non è nel font collassato"
            )
        }
        let laidOut = MarkupHidingFixture.fragments(text: note, markers: [0: [tabbed]], hidesMarkup: true)
        #expect(laidOut[0] is HorizontalRuleFragment)
    }

    /// The trim above takes the blanks around the line only: a tab between the dashes is no rule
    /// for `isRule`, so `\t-\t-\t-` is never collapsed, whatever entry the styler left on it.
    @Test func aRuleSpelledWithInteriorTabsIsNotCollapsed() {
        let note = "\t-\t-\t-\ncorpo\n"
        let entry = HiddenMarker(range: NSRange(location: 0, length: 6), kind: .rule)
        #expect(MarkupHidingFixture.displayedParagraph(note, markers: [entry]) == nil)
    }

    @Test func theRuleHookIsInertWhenTheSettingIsOff() {
        #expect(MarkupHidingFixture.displayedParagraph(Self.note, markers: [Self.marker], hidesMarkup: false) == nil)
    }
}
