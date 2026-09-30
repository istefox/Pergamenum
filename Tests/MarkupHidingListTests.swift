import AppKit
import Testing
@testable import Pergamenum

// MARK: - The list marker (ADR-0028, plan 2026-08-29-wysiwyg-markdown-in-workspace)

/// The third kind of marker this delegate draws, and the first one that *replaces* a
/// character rather than only shrinking it: an unordered `- ` becomes a bullet, an ordered
/// `1. ` stays exactly as the file spells it, and both hang at an indentation that grows
/// with their nesting level (R-02, R-03, R-05; ADR-0028 §D2, §D4).
///
/// Every fixture below records its marker range **from the paragraph's own start,
/// indentation included** - the one place a `.list` marker differs from a `.heading` or an
/// `.emphasis` one (plan Task 3, «Ordering note»). The indent has to be inside the range
/// or it cannot be collapsed, and the nesting level is read back out of it, since
/// `HiddenMarker.Kind.list` carries no level of its own.
@MainActor
@Suite struct MarkupHidingLists {
    /// The glyph an unordered marker is drawn as. A `Character` rather than a `String` so
    /// `contains` resolves to `Sequence.contains(_:)` on the displayed text.
    private static let bullet: Character = "•"

    private static let unordered = "- primo\ncorpo\n"
    private static let unorderedMarker = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .list)

    private static let ordered = "1. uno\ncorpo\n"
    private static let orderedMarker = HiddenMarker(range: NSRange(location: 0, length: 3), kind: .list)

    /// A real parent line, then two spaces of indentation and `- `: four characters, all
    /// inside the range. PG-085: CommonMark's content-column rule measures a child against
    /// its actual parent, so an isolated indented line has no ancestor to nest under and
    /// this fixture needs one - `nestedOffset` is where the child's own paragraph starts.
    private static let nested = "- padre\n  - annidato\ncorpo\n"
    private static let nestedOffset = (("- padre\n") as NSString).length
    private static let nestedMarker = HiddenMarker(range: NSRange(location: 0, length: 4), kind: .list)

    /// A list item whose text is emphasised - the SPEC's coexistence case. `**` opens at
    /// index 2 and closes at index 13.
    private static let mixed = "- **grassetto** elemento\n"
    private static let mixedList = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .list)
    private static let mixedOpen = HiddenMarker(range: NSRange(location: 2, length: 2), kind: .emphasis)
    private static let mixedClose = HiddenMarker(range: NSRange(location: 13, length: 2), kind: .emphasis)

    private static let everyCase: [(note: String, offset: Int, markers: [HiddenMarker])] = [
        (unordered, 0, [unorderedMarker]),
        (ordered, 0, [orderedMarker]),
        (nested, nestedOffset, [nestedMarker]),
        (mixed, 0, [mixedList, mixedOpen, mixedClose])
    ]

    /// First and loudest (R-10's structural half, and the plan's highest-listed risk): the
    /// file must not gain or lose a character, whatever is drawn over it. Checked through a
    /// real layout pass, with the setting on and off and the paragraph revealed and not,
    /// because a substitution that changes length does not show up as a wrong picture - it
    /// shows up later as offsets drifting between the storage and the layout.
    @Test func theStorageNeverGainsOrLosesACharacterForAnyListCase() {
        for (note, offset, markers) in Self.everyCase {
            let source = (note as NSString).length
            for hides in [true, false] {
                for revealed in [Set<Int>(), Set([offset])] {
                    let measured = MarkupHidingFixture.frames(
                        text: note, markers: [offset: markers], hidesMarkup: hides, revealed: revealed
                    )
                    #expect(
                        measured.length == source,
                        "«\(note)» nascondi=\(hides) rivelato=\(revealed): \(measured.length) invece di \(source)"
                    )
                }
            }
        }
    }

    /// The same rule from the other side: what the hook hands back is a *displayed*
    /// paragraph of the stored paragraph's own length - `NSTextContentManager.h:120`'s
    /// constraint, which is why a bullet can only replace a marker character and never be
    /// inserted before one.
    @Test func theDisplayedParagraphKeepsItsStoredLength() {
        for (note, offset, markers) in Self.everyCase {
            let displayed = MarkupHidingFixture.displayedParagraph(note, markers: markers, at: offset)
            #expect(displayed != nil, "«\(note)»: nessuna sostituzione")
            #expect(
                displayed?.attributedString.length == MarkupHidingFixture.firstParagraphLength(of: note, at: offset),
                "«\(note)»: lunghezza \(displayed?.attributedString.length ?? -1)"
            )
        }
    }

    /// Restated for Task 4 of `2026-09-04-editor-page-typography-noteplan` (ADR-0028 §D2): this
    /// task changes `ListMarkerRendering.paragraphStyle`'s signature and, later,
    /// `listParagraph(at:storage:)`'s own call to it to compose a line-height multiple onto the
    /// indentation (ADR-0030 §D6) - the length invariant this whole substitution mechanism
    /// depends on must still hold once that composition lands. Already covered by
    /// `theDisplayedParagraphKeepsItsStoredLength` above; restated here under this task's own
    /// name so a regression introduced by the composition change fails on an assertion that
    /// names Task 4, not only on the pre-existing one.
    @Test func theDisplayedParagraphLengthInvariantHoldsForTask4sListCases() {
        for (note, offset, markers) in Self.everyCase {
            let displayed = MarkupHidingFixture.displayedParagraph(note, markers: markers, at: offset)
            #expect(
                displayed?.attributedString.length == MarkupHidingFixture.firstParagraphLength(of: note, at: offset),
                "«\(note)»"
            )
        }
    }

    @Test func anUnorderedMarkerIsDrawnAsABullet() {
        let displayed = MarkupHidingFixture.displayedParagraph(Self.unordered, markers: [Self.unorderedMarker])

        #expect(displayed != nil)
        #expect(displayed?.attributedString.string.first == Self.bullet)
        // The item's own text is untouched: exactly one character is replaced.
        #expect(displayed?.attributedString.string.hasSuffix("primo\n") == true)
        #expect(displayed?.attributedString.length == MarkupHidingFixture.firstParagraphLength(of: Self.unordered))
    }

    /// An ordered marker is displayed verbatim: the digits in the file *are* the ordinal
    /// (ADR-0028 §D4), so nothing is substituted for them and no bullet appears beside
    /// them. The paragraph is still returned - it carries the item's indentation.
    @Test func anOrderedMarkerIsDisplayedVerbatim() {
        let displayed = MarkupHidingFixture.displayedParagraph(Self.ordered, markers: [Self.orderedMarker])

        #expect(displayed != nil)
        #expect(displayed?.attributedString.string.hasPrefix("1. ") == true)
        #expect(displayed?.attributedString.string.contains(Self.bullet) == false)
        #expect(displayed?.attributedString.length == MarkupHidingFixture.firstParagraphLength(of: Self.ordered))
    }

    /// R-05: a nested item is *visibly deeper*, not merely different - and a top-level one
    /// is already indented, so the two are told apart by their step rather than by one of
    /// them being flush left.
    @Test func aNestedItemIndentsFurtherThanATopLevelOne() {
        let top = MarkupHidingFixture.displayedParagraph(Self.unordered, markers: [Self.unorderedMarker])
        let deeper = MarkupHidingFixture.displayedParagraph(
            Self.nested, markers: [Self.nestedMarker], at: Self.nestedOffset
        )
        let topStyle = top?.attributedString
            .attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let deeperStyle = deeper?.attributedString
            .attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle

        #expect(topStyle != nil)
        #expect(deeperStyle != nil)
        #expect((topStyle?.headIndent ?? 0) > 0)
        #expect((topStyle?.firstLineHeadIndent ?? 0) > 0)
        #expect((deeperStyle?.headIndent ?? 0) > (topStyle?.headIndent ?? 0))
        #expect((deeperStyle?.firstLineHeadIndent ?? 0) > (topStyle?.firstLineHeadIndent ?? 0))
    }

    /// The style covers the whole displayed paragraph, not only the marker: a wrapped item
    /// that lost its indentation on its second line would still pass every assertion above.
    @Test func theParagraphStyleCoversTheWholeDisplayedParagraph() {
        let displayed = MarkupHidingFixture.displayedParagraph(
            Self.nested, markers: [Self.nestedMarker], at: Self.nestedOffset
        )
        var effective = NSRange(location: 0, length: 0)
        // `effectiveRange:` reports the run where the WHOLE attribute dictionary is constant,
        // which the collapsed-indent font split breaks even though `.paragraphStyle` alone is
        // unchanged across it. `longestEffectiveRange:` is the call that answers this test's
        // actual question — how far this one attribute's value extends.
        _ = displayed?.attributedString.attribute(
            .paragraphStyle, at: 0, longestEffectiveRange: &effective,
            in: NSRange(location: 0, length: displayed?.attributedString.length ?? 0))

        #expect(displayed != nil)
        #expect(effective.length == displayed?.attributedString.length)
    }

    /// R-05's «no double indentation» half: the two spaces the source spells are collapsed
    /// into `collapsedFont`, so the only thing indenting the line is the paragraph style
    /// above. Left visible, they would be added to it.
    @Test func theLeadingIndentIsDrawnInTheCollapsedFont() {
        let displayed = MarkupHidingFixture.displayedParagraph(
            Self.nested, markers: [Self.nestedMarker], at: Self.nestedOffset
        )
        let first = displayed?.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let second = displayed?.attributedString.attribute(.font, at: 1, effectiveRange: nil) as? NSFont

        // The whole indent run, not only its first character.
        #expect(first == EditorDecorationDelegate.collapsedFont)
        #expect(second == EditorDecorationDelegate.collapsedFont)
    }

    /// R-03: the caret's paragraph shows its own raw prefix. Nil, so the raw source is laid
    /// out - no substitution, no paragraph style, nothing shifting under the caret.
    @Test func theHookReturnsNilForARevealedListParagraph() {
        #expect(
            MarkupHidingFixture.displayedParagraph(
                Self.unordered, markers: [Self.unorderedMarker], revealed: [0]
            ) == nil
        )
        #expect(
            MarkupHidingFixture.displayedParagraph(
                Self.nested, markers: [Self.nestedMarker], at: Self.nestedOffset, revealed: [Self.nestedOffset]
            ) == nil
        )
    }

    /// ADR-0028 §D10: the whole feature is behind `hidesMarkup`, and off means off,
    /// whatever the reveal set says.
    @Test func theListHookIsInertWhenTheSettingIsOff() {
        #expect(
            MarkupHidingFixture.displayedParagraph(
                Self.unordered, markers: [Self.unorderedMarker], hidesMarkup: false
            ) == nil
        )
        #expect(
            MarkupHidingFixture.displayedParagraph(
                Self.unordered, markers: [Self.unorderedMarker], hidesMarkup: false, revealed: [0]
            ) == nil
        )
        #expect(
            MarkupHidingFixture.displayedParagraph(
                Self.nested, markers: [Self.nestedMarker], at: Self.nestedOffset, hidesMarkup: false
            ) == nil
        )
    }

    /// The `stillSpells` re-check contract: the table is filled by the last styling pass and
    /// read by a later layout pass, and the two go stale against each other. A `.list` entry
    /// whose characters no longer spell a marker is skipped on its own account - it neither
    /// draws a bullet over prose nor cancels the other markers in the same paragraph.
    @Test func aStaleListEntryIsSkippedWhileTheOtherMarkersStillRender() {
        let note = "prosa **enfasi** qui\n"
        let stale = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .list)
        let open = HiddenMarker(range: NSRange(location: 6, length: 2), kind: .emphasis)
        let close = HiddenMarker(range: NSRange(location: 14, length: 2), kind: .emphasis)

        let displayed = MarkupHidingFixture.displayedParagraph(note, markers: [stale, open, close])

        #expect(displayed != nil)
        // «pr» never spelled a list marker: the prose is drawn exactly as written.
        #expect(displayed?.attributedString.string == note)
        #expect((displayed?.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) == nil)
        // The emphasis pair in the same paragraph still collapses.
        #expect(
            (displayed?.attributedString.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)
                == EditorDecorationDelegate.collapsedFont
        )
        #expect(
            (displayed?.attributedString.attribute(.font, at: 14, effectiveRange: nil) as? NSFont)
                == EditorDecorationDelegate.collapsedFont
        )
    }

    /// The SPEC's coexistence edge case: one paragraph, two kinds of marker, one
    /// substitution. The bullet replaces the `-`, the `**` pair collapses, and the length
    /// does not move.
    @Test func aListAndAnEmphasisMarkerRenderTogetherInOneParagraph() {
        let displayed = MarkupHidingFixture.displayedParagraph(
            Self.mixed, markers: [Self.mixedList, Self.mixedOpen, Self.mixedClose]
        )

        #expect(displayed != nil)
        #expect(displayed?.attributedString.string.first == Self.bullet)
        #expect(displayed?.attributedString.string.hasSuffix("grassetto** elemento\n") == true)
        #expect(displayed?.attributedString.length == MarkupHidingFixture.firstParagraphLength(of: Self.mixed))
        #expect(
            (displayed?.attributedString.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)
                == EditorDecorationDelegate.collapsedFont
        )
        #expect(
            (displayed?.attributedString.attribute(.font, at: 13, effectiveRange: nil) as? NSFont)
                == EditorDecorationDelegate.collapsedFont
        )
    }
}

// MARK: - ListMarkerRendering.paragraphStyle(level:font:basedOn:) composition (ADR-0030 §D6, R-07)
//
// Task 4 of `2026-09-04-editor-page-typography-noteplan`. Driven directly against
// `ListMarkerRendering`, not through `EditorDecorationDelegate`: the composition rule belongs to
// this one function, and a unit test on it is a smaller, more exact fixture than building a whole
// styled paragraph through the delegate to observe the same value - `MarkupHidingLists` above
// never sets a font on its storage at all, so `bodyFont(of:after:)`'s own fallback
// (`NSFont.systemFontSize`) is what it exercises, not a font this suite controls directly.

@Suite struct ListMarkerRenderingComposition {
    /// Formula pinned from `ListMarkerRendering.swift`'s own doc comments: `stepInEms = 1.5`,
    /// `glyphInEms = 0.75`, `depth` clamped to 1...6.
    ///
    /// PLAN DEVIATION (ADR-0073 §D2 of the retired concept-to-code workflow): the dispatch brief
    /// asks to "reuse the exact font/depth
    /// fixtures [of] the existing `ListMarkerRendering` test file" - grepped for
    /// `ListMarkerRendering` across `Tests/` before writing this suite and found no such file.
    /// The only existing coverage of this arithmetic is `MarkupHidingLists`'s relative
    /// "deeper > top-level" assertions above, which compare two computed styles to each other
    /// and never pin an exact value, over a font neither fixture sets explicitly. This test
    /// fixes a concrete font/depth pair instead, read from the file's own documented constants,
    /// so the exact multiplier survives Task 4's composition change rather than only staying
    /// "more indented than before".
    @Test func theIndentArithmeticIsUnchangedByAddingTheBasedOnParameter() {
        let font = NSFont.systemFont(ofSize: 20)
        for level in [1, 3, 6] {
            let depth = CGFloat(level)
            let style = ListMarkerRendering.paragraphStyle(level: level, font: font)
            #expect(style.firstLineHeadIndent == 20 * 1.5 * depth, "livello \(level)")
            #expect(style.headIndent == style.firstLineHeadIndent + 20 * 0.75, "livello \(level)")
        }
        // A level past the documented 1...6 clamp still steps at depth 6, never further.
        let clamped = ListMarkerRendering.paragraphStyle(level: 99, font: font)
        #expect(clamped.firstLineHeadIndent == 20 * 1.5 * 6)
    }

    /// A style already carrying `lineHeightMultiple` 1.4 - the value
    /// `ProseTypography.paragraphStyle(_:basedOn:)` would have set on the paragraph before this
    /// function ever sees it (ADR-0030 §D6) - must survive the paragraph also becoming a list
    /// item. `ProseTypography.paragraphStyle(_:basedOn:)` performs exactly this composition for
    /// its own case (`style.setParagraphStyle(basedOn)`); this is the same rule applied to the
    /// list-indent side.
    @Test func paragraphStyleComposesOntoAnIncomingLineHeightWithoutDroppingItOrTheIndent() {
        let base = NSMutableParagraphStyle()
        base.lineHeightMultiple = 1.4
        let font = NSFont.systemFont(ofSize: 20)

        let composed = ListMarkerRendering.paragraphStyle(level: 2, font: font, basedOn: base)

        #expect(composed.lineHeightMultiple == 1.4, "il moltiplicatore di interlinea in ingresso è stato perso")
        #expect(composed.firstLineHeadIndent == 20 * 1.5 * 2, "l'indentazione del livello non è cambiata")
        #expect(composed.headIndent == composed.firstLineHeadIndent + 20 * 0.75)
    }
}
