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

private struct Frame {
    let offset: Int
    let frame: CGRect
}

@MainActor
private func frames(
    text: String,
    markers: [Int: [HiddenMarker]],
    hidesMarkup: Bool,
    revealed: Set<Int> = []
) -> (frames: [Frame], length: Int) {
    let content = NSTextContentStorage()
    let layout = NSTextLayoutManager()
    content.addTextLayoutManager(layout)
    let container = NSTextContainer(size: CGSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    layout.textContainer = container

    let delegate = EditorDecorationDelegate()
    delegate.apply(hiddenMarkers: markers, hidingMarkup: hidesMarkup)
    _ = delegate.apply(revealedParagraphs: revealed)
    content.delegate = delegate

    content.textStorage?.setAttributedString(
        NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]
        )
    )
    layout.ensureLayout(for: layout.documentRange)

    var collected: [Frame] = []
    layout.enumerateTextLayoutFragments(from: layout.documentRange.location, options: [.ensuresLayout]) { fragment in
        let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        collected.append(Frame(offset: offset, frame: fragment.layoutFragmentFrame))
        return true
    }
    // The length is the whole point: the file must not gain or lose a character.
    return (collected, content.textStorage?.length ?? -1)
}

/// Drives the hook by hand over the first paragraph of `note`, the way AppKit itself
/// would when laying it out - for the tests that check the hook's return value directly
/// rather than a measured frame.
@MainActor
private func substitutedParagraph(
    _ delegate: EditorDecorationDelegate, note: String, at location: Int = 0
) -> NSTextParagraph? {
    let storage = NSTextContentStorage()
    storage.textStorage?.setAttributedString(NSAttributedString(string: note))
    let range = (note as NSString).paragraphRange(for: NSRange(location: location, length: 0))
    return delegate.textContentStorage(storage, textParagraphWith: range)
}

/// `substitutedParagraph` above with the delegate built in - the whole configuration a
/// list case needs is the marker table, the setting and the reveal set, so a test that
/// spells out three lines of setup per assertion is a test whose fixture is harder to read
/// than the rule it pins (ADR-0028; plan `2026-08-29-wysiwyg-markdown-in-workspace`,
/// Task 3).
@MainActor
private func displayedParagraph(
    _ note: String,
    markers: [HiddenMarker],
    at location: Int = 0,
    hidesMarkup: Bool = true,
    revealed: Set<Int> = [],
    spans: [Int: [NSRange]] = [:],
    revealsInlineSpans: Bool = false
) -> NSTextParagraph? {
    let delegate = EditorDecorationDelegate()
    delegate.apply(hiddenMarkers: [location: markers], hidingMarkup: hidesMarkup)
    _ = delegate.apply(revealedParagraphs: revealed)
    _ = delegate.apply(revealedSpans: spans)
    delegate.apply(revealsInlineSpans: revealsInlineSpans)
    return substitutedParagraph(delegate, note: note, at: location)
}

/// The length of `note`'s paragraph starting at `location` (the first paragraph by
/// default), the number a substitution of it must return unchanged.
private func firstParagraphLength(of note: String, at location: Int = 0) -> Int {
    (note as NSString).paragraphRange(for: NSRange(location: location, length: 0)).length
}

@MainActor
@Suite struct MarkupHiding {
    private static let note = "# Titolo\ncorpo\n"
    private static let headingOffset = 0
    /// "# " - the hash and the one space after it, relative to the paragraph's own start.
    private static let marker = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .heading)

    @Test func aCollapsedMarkerCostsNoWidth() {
        let base = frames(text: Self.note, markers: [:], hidesMarkup: false)
        let collapsed = frames(
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
        let base = frames(text: Self.note, markers: [:], hidesMarkup: false)
        let collapsed = frames(
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

        #expect(substitutedParagraph(delegate, note: Self.note) == nil)
    }

    @Test func aStaleTableEntryDoesNotCollapseProse() {
        // The table still says a heading marker sits at offset 0, but the text there has
        // since become plain prose - the last styling pass has not caught up with this
        // layout pass yet.
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [0: [Self.marker]], hidingMarkup: true)

        #expect(substitutedParagraph(delegate, note: "corpo\ndopo\n") == nil)
    }

    @Test func theHookIsInertWhenTheSettingIsOff() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [Self.headingOffset: [Self.marker]], hidingMarkup: false)

        #expect(substitutedParagraph(delegate, note: Self.note) == nil)
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
        let base = frames(text: Self.note, markers: [:], hidesMarkup: false)
        let collapsed = frames(
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
        let base = frames(text: Self.note, markers: [:], hidesMarkup: false)
        let collapsed = frames(
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

        let paragraph = substitutedParagraph(delegate, note: note)
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

        #expect(substitutedParagraph(delegate, note: "corpo\ndopo\n") == nil)
    }

    @Test func theHookIsInertForEmphasisWhenTheSettingIsOff() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(
            hiddenMarkers: [Self.paragraphOffset: [Self.openMarker, Self.closeMarker]],
            hidingMarkup: false
        )

        #expect(substitutedParagraph(delegate, note: Self.note) == nil)
    }
}

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
                    let measured = frames(
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
            let displayed = displayedParagraph(note, markers: markers, at: offset)
            #expect(displayed != nil, "«\(note)»: nessuna sostituzione")
            #expect(
                displayed?.attributedString.length == firstParagraphLength(of: note, at: offset),
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
            let displayed = displayedParagraph(note, markers: markers, at: offset)
            #expect(
                displayed?.attributedString.length == firstParagraphLength(of: note, at: offset),
                "«\(note)»"
            )
        }
    }

    @Test func anUnorderedMarkerIsDrawnAsABullet() {
        let displayed = displayedParagraph(Self.unordered, markers: [Self.unorderedMarker])

        #expect(displayed != nil)
        #expect(displayed?.attributedString.string.first == Self.bullet)
        // The item's own text is untouched: exactly one character is replaced.
        #expect(displayed?.attributedString.string.hasSuffix("primo\n") == true)
        #expect(displayed?.attributedString.length == firstParagraphLength(of: Self.unordered))
    }

    /// An ordered marker is displayed verbatim: the digits in the file *are* the ordinal
    /// (ADR-0028 §D4), so nothing is substituted for them and no bullet appears beside
    /// them. The paragraph is still returned - it carries the item's indentation.
    @Test func anOrderedMarkerIsDisplayedVerbatim() {
        let displayed = displayedParagraph(Self.ordered, markers: [Self.orderedMarker])

        #expect(displayed != nil)
        #expect(displayed?.attributedString.string.hasPrefix("1. ") == true)
        #expect(displayed?.attributedString.string.contains(Self.bullet) == false)
        #expect(displayed?.attributedString.length == firstParagraphLength(of: Self.ordered))
    }

    /// R-05: a nested item is *visibly deeper*, not merely different - and a top-level one
    /// is already indented, so the two are told apart by their step rather than by one of
    /// them being flush left.
    @Test func aNestedItemIndentsFurtherThanATopLevelOne() {
        let top = displayedParagraph(Self.unordered, markers: [Self.unorderedMarker])
        let deeper = displayedParagraph(Self.nested, markers: [Self.nestedMarker], at: Self.nestedOffset)
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
        let displayed = displayedParagraph(Self.nested, markers: [Self.nestedMarker], at: Self.nestedOffset)
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
        let displayed = displayedParagraph(Self.nested, markers: [Self.nestedMarker], at: Self.nestedOffset)
        let first = displayed?.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let second = displayed?.attributedString.attribute(.font, at: 1, effectiveRange: nil) as? NSFont

        // The whole indent run, not only its first character.
        #expect(first == EditorDecorationDelegate.collapsedFont)
        #expect(second == EditorDecorationDelegate.collapsedFont)
    }

    /// R-03: the caret's paragraph shows its own raw prefix. Nil, so the raw source is laid
    /// out - no substitution, no paragraph style, nothing shifting under the caret.
    @Test func theHookReturnsNilForARevealedListParagraph() {
        #expect(displayedParagraph(Self.unordered, markers: [Self.unorderedMarker], revealed: [0]) == nil)
        #expect(
            displayedParagraph(
                Self.nested, markers: [Self.nestedMarker], at: Self.nestedOffset, revealed: [Self.nestedOffset]
            ) == nil
        )
    }

    /// ADR-0028 §D10: the whole feature is behind `hidesMarkup`, and off means off,
    /// whatever the reveal set says.
    @Test func theListHookIsInertWhenTheSettingIsOff() {
        #expect(
            displayedParagraph(Self.unordered, markers: [Self.unorderedMarker], hidesMarkup: false) == nil
        )
        #expect(
            displayedParagraph(
                Self.unordered, markers: [Self.unorderedMarker], hidesMarkup: false, revealed: [0]
            ) == nil
        )
        #expect(
            displayedParagraph(
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

        let displayed = displayedParagraph(note, markers: [stale, open, close])

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
        let displayed = displayedParagraph(
            Self.mixed, markers: [Self.mixedList, Self.mixedOpen, Self.mixedClose]
        )

        #expect(displayed != nil)
        #expect(displayed?.attributedString.string.first == Self.bullet)
        #expect(displayed?.attributedString.string.hasSuffix("grassetto** elemento\n") == true)
        #expect(displayed?.attributedString.length == firstParagraphLength(of: Self.mixed))
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
    /// PLAN DEVIATION (ADR-0073 §D2): the dispatch brief asks to "reuse the exact font/depth
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

    /// **Red on purpose.** The Task 4 stub (`ListMarkerRendering.swift`) accepts `basedOn` but
    /// does not yet compose it, so a style already carrying `lineHeightMultiple` 1.4 - the value
    /// `ProseTypography.paragraphStyle(_:basedOn:)` would have set on the paragraph before this
    /// function ever sees it (ADR-0030 §D6) - is dropped the moment the paragraph also becomes a
    /// list item. `ProseTypography.paragraphStyle(_:basedOn:)` already performs exactly this
    /// composition for its own case (`style.setParagraphStyle(basedOn)`); this is the same rule
    /// applied to the list-indent side, which the coder's job for this task is to add.
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

// MARK: - Faces pushed onto the decoration delegate and the fold badge (ADR-0030 §D1/§D5)
//
// Task 4 of `2026-09-04-editor-page-typography-noteplan`. Both properties are declared as plain
// stored values with system-face defaults (tester stubs, ADR-0155 §D1): the coder wires
// `applyStyling`/`textLayoutManager(_:textLayoutFragmentFor:in:)` to push `ProseTypography`
// values into them next. What is asserted here is the interface itself - default and settable -
// not a drawn pixel, which is out of reach without a pixel-level harness this repo does not have
// for either type.

@Suite struct EditorDecorationDelegateProseFaces {
    @Test func proseFontDefaultsToASystemFaceAndIsSettable() {
        let delegate = EditorDecorationDelegate()
        #expect(delegate.proseFont.pointSize == NSFont.systemFontSize)

        let pushed = NSFont(name: "Avenir Next", size: 16) ?? NSFont.systemFont(ofSize: 16)
        delegate.proseFont = pushed
        #expect(delegate.proseFont == pushed)
    }

    @Test func badgeFontDefaultsToATenPointSystemFaceAndIsSettable() {
        let delegate = EditorDecorationDelegate()
        #expect(delegate.badgeFont.pointSize == 10)

        let pushed = NSFont.systemFont(ofSize: 9)
        delegate.badgeFont = pushed
        #expect(delegate.badgeFont == pushed)
    }
}

@Suite struct FoldedHeadingFragmentBadgeFont {
    /// `NSTextLayoutFragment` has no niladic initialiser - `EditorDecorationDelegate` always
    /// builds one from a real `textElement` (`EditorDecorationDelegate.swift:293`). A bare
    /// `NSTextParagraph` is enough of one for a property-only test that never lays anything out.
    private static func fragment() -> FoldedHeadingFragment {
        FoldedHeadingFragment(textElement: NSTextParagraph(attributedString: NSAttributedString(string: "x")), range: nil)
    }

    @Test func badgeFontDefaultsToATenPointSystemFaceAndIsSettable() {
        let fragment = Self.fragment()
        #expect(fragment.badgeFont.pointSize == 10)

        let pushed = NSFont.systemFont(ofSize: 12, weight: .semibold)
        fragment.badgeFont = pushed
        #expect(fragment.badgeFont == pushed)
    }
}

// MARK: - The checkbox marker (PG-086; plan 2026-08-31-pg-074-give-the-to-do-tool-an-interactiv)

/// The fourth kind of marker this delegate draws, and like `.list` a replacement rather than a
/// shrink: the state character at offset 3 of the five-character `- [x]` marker becomes a real
/// checkbox glyph (`TaskGlyphRendering.glyph(for:)`), and the other four characters (`- [`, `]`)
/// collapse into `collapsedFont` exactly as a list marker's own non-glyph characters do.
@MainActor
@Suite struct MarkupHidingCheckboxes {
    private static let open = "- [ ] fai\ncorpo\n"
    private static let openMarker = HiddenMarker(range: NSRange(location: 0, length: 5), kind: .checkbox)

    private static let done = "- [x] fatto\ncorpo\n"
    private static let doneMarker = HiddenMarker(range: NSRange(location: 0, length: 5), kind: .checkbox)

    private static let rescheduled = "- [>] rimandato\ncorpo\n"
    private static let rescheduledMarker = HiddenMarker(range: NSRange(location: 0, length: 5), kind: .checkbox)

    private static let cancelled = "- [-] annullato\ncorpo\n"
    private static let cancelledMarker = HiddenMarker(range: NSRange(location: 0, length: 5), kind: .checkbox)

    private static let everyState:
        [(note: String, marker: HiddenMarker, glyph: Character)] = [
            (open, openMarker, "\u{2610}"),
            (done, doneMarker, "\u{2611}"),
            (rescheduled, rescheduledMarker, "\u{21C4}"),
            (cancelled, cancelledMarker, "\u{2612}"),
        ]

    /// The structural half, exactly as `theStorageNeverGainsOrLosesACharacterForAnyListCase`
    /// checks it for `.list`: whatever is drawn over a checkbox line, the file itself does not
    /// move a single character (R-10, `NSTextContentManager.h:120`).
    @Test func theStorageNeverGainsOrLosesACharacterForAnyCheckboxState() {
        for (note, marker, _) in Self.everyState {
            let source = (note as NSString).length
            for hides in [true, false] {
                for revealed in [Set<Int>(), Set([0])] {
                    let measured = frames(
                        text: note, markers: [0: [marker]], hidesMarkup: hides, revealed: revealed
                    )
                    #expect(
                        measured.length == source,
                        "«\(note)» nascondi=\(hides) rivelato=\(revealed): \(measured.length) invece di \(source)"
                    )
                }
            }
        }
    }

    /// One character out, one character in: the displayed paragraph's length matches the
    /// stored paragraph's, for all four states.
    @Test func theDisplayedParagraphKeepsItsStoredLengthForEveryState() {
        for (note, marker, _) in Self.everyState {
            let displayed = displayedParagraph(note, markers: [marker])
            #expect(displayed != nil, "«\(note)»: nessuna sostituzione")
            #expect(
                displayed?.attributedString.length == firstParagraphLength(of: note),
                "«\(note)»: lunghezza \(displayed?.attributedString.length ?? -1)"
            )
        }
    }

    /// The glyph drawn matches the state the marker's fourth character names, for all four
    /// §7.1 states - the one fact `TaskGlyphRendering.glyph(for:)` and this substitution must
    /// never disagree on. Drawn at offset 3 of the five-character marker, where the state
    /// character sat (`- [x]`: dash, space, bracket, state, bracket) - a substitution, not a
    /// prefix, so the marker's other four characters stay in the string too, only collapsed.
    @Test func theGlyphDrawnMatchesTheState() {
        for (note, marker, glyph) in Self.everyState {
            let displayed = displayedParagraph(note, markers: [marker])
            #expect(displayed != nil, "«\(note)»: nessuna sostituzione")
            let string = displayed?.attributedString.string
            let stateIndex = string?.index(string!.startIndex, offsetBy: 3)
            #expect(
                stateIndex.flatMap { string?[$0] } == glyph,
                "«\(note)»: carattere all'offset 3 \(stateIndex.flatMap { string?[$0] }.map(String.init) ?? "nil") invece di \(glyph)"
            )
            // The item's own text is untouched beyond the five-character marker - compared
            // against the first paragraph alone, since `displayed` is only ever that much
            // (`note` itself carries a second "corpo\n" line the substitution never sees).
            let firstParagraph = String((note as NSString).substring(to: firstParagraphLength(of: note)))
            #expect(displayed?.attributedString.string.dropFirst(5) == firstParagraph.dropFirst(5))
        }
    }

    /// The four non-glyph characters of the marker (`- [`, `]`) collapse into `collapsedFont`,
    /// leaving only the glyph itself undecorated.
    @Test func theNonGlyphCharactersOfTheMarkerAreCollapsed() {
        let displayed = displayedParagraph(Self.open, markers: [Self.openMarker])
        let string = displayed?.attributedString

        for offset in [0, 1, 2, 4] {
            #expect(
                (string?.attribute(.font, at: offset, effectiveRange: nil) as? NSFont)
                    == EditorDecorationDelegate.collapsedFont,
                "offset \(offset) non è nel font collassato"
            )
        }
        #expect((string?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont) != EditorDecorationDelegate.collapsedFont)
    }

    /// Deliberately not R-03's checkbox counterpart: unlike a list item or a blockquote, the
    /// checkbox glyph keeps drawing even when the caret sits in its own paragraph - typing the
    /// task's own text would otherwise make the glyph flicker back to raw `- [ ]` on every
    /// keystroke. The click-to-toggle (`NoteTextView+CheckboxClick.swift`) is what removed the
    /// need to ever hand-edit the marker with the caret sitting inside it.
    @Test func theHookStillDrawsTheGlyphForARevealedCheckboxParagraph() {
        #expect(displayedParagraph(Self.open, markers: [Self.openMarker], revealed: [0]) != nil)
        #expect(displayedParagraph(Self.done, markers: [Self.doneMarker], revealed: [0]) != nil)
    }

    /// ADR-0028 §D10's switch governs this marker kind too: off means off, whatever the reveal
    /// set says.
    @Test func theCheckboxHookIsInertWhenTheSettingIsOff() {
        #expect(displayedParagraph(Self.open, markers: [Self.openMarker], hidesMarkup: false) == nil)
        #expect(
            displayedParagraph(Self.open, markers: [Self.openMarker], hidesMarkup: false, revealed: [0]) == nil
        )
    }

    /// The re-validation contract: a `.checkbox` entry whose characters no longer spell one of
    /// the four recognised states (malformed, or edited since the last styling pass) is skipped
    /// on its own account, the same as a stale `.list` entry.
    @Test func aStaleCheckboxEntryIsSkipped() {
        let note = "- [z] non è uno stato\n"
        let stale = HiddenMarker(range: NSRange(location: 0, length: 5), kind: .checkbox)

        let displayed = displayedParagraph(note, markers: [stale])

        #expect(displayed == nil)
    }

    /// The SPEC's coexistence case for a task line: a checkbox and an emphasis pair drawn
    /// together in one paragraph, one substitution.
    @Test func aCheckboxAndAnEmphasisMarkerRenderTogetherInOneParagraph() {
        let note = "- [ ] **grassetto**\n"
        let checkbox = HiddenMarker(range: NSRange(location: 0, length: 5), kind: .checkbox)
        let openMark = HiddenMarker(range: NSRange(location: 6, length: 2), kind: .emphasis)
        let closeMark = HiddenMarker(range: NSRange(location: 17, length: 2), kind: .emphasis)

        let displayed = displayedParagraph(note, markers: [checkbox, openMark, closeMark])

        #expect(displayed != nil)
        let string = displayed?.attributedString.string
        let stateIndex = string?.index(string!.startIndex, offsetBy: 3)
        #expect(stateIndex.flatMap { string?[$0] } == "\u{2610}")
        #expect(displayed?.attributedString.string.hasSuffix("grassetto**\n") == true)
        #expect(displayed?.attributedString.length == firstParagraphLength(of: note))
        #expect(
            (displayed?.attributedString.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)
                == EditorDecorationDelegate.collapsedFont
        )
        #expect(
            (displayed?.attributedString.attribute(.font, at: 17, effectiveRange: nil) as? NSFont)
                == EditorDecorationDelegate.collapsedFont
        )
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
        let base = frames(text: Self.note, markers: [:], hidesMarkup: false)
        let collapsed = frames(
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

        #expect(substitutedParagraph(delegate, note: Self.note) == nil)
    }

    @Test func aStaleStrikethroughEntryDoesNotCollapseProse() {
        let delegate = EditorDecorationDelegate()
        let stale = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .strikethrough)
        delegate.apply(hiddenMarkers: [0: [stale]], hidingMarkup: true)

        #expect(substitutedParagraph(delegate, note: "corpo\ndopo\n") == nil)
    }

    @Test func theHookIsInertForStrikethroughWhenTheSettingIsOff() {
        let delegate = EditorDecorationDelegate()
        delegate.apply(
            hiddenMarkers: [Self.paragraphOffset: [Self.openMarker, Self.closeMarker]], hidingMarkup: false
        )

        #expect(substitutedParagraph(delegate, note: Self.note) == nil)
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
        let base = frames(text: Self.wikilink, markers: [:], hidesMarkup: false)
        let collapsed = frames(
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
        let displayed = displayedParagraph(
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
        let displayed = displayedParagraph(
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
            displayedParagraph(
                Self.wikilink, markers: [Self.wikilinkOpen, Self.wikilinkClose], revealed: [0]
            ) == nil
        )
    }

    @Test func aStaleLinkEntryDoesNotCollapseProse() {
        let stale = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .link)
        #expect(displayedParagraph("corpo\ndopo\n", markers: [stale]) == nil)
    }

    @Test func theHookIsInertForLinkWhenTheSettingIsOff() {
        #expect(
            displayedParagraph(
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
        let displayed = displayedParagraph(Self.note, markers: [Self.marker])
        #expect(displayed != nil, "nessuna sostituzione")
        #expect(displayed?.attributedString.length == firstParagraphLength(of: Self.note))
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
        #expect(displayedParagraph(Self.note, markers: [Self.marker], revealed: [0]) == nil)
    }

    @Test func aStaleRuleEntryDoesNotCollapseProse() {
        let stale = HiddenMarker(range: NSRange(location: 0, length: 3), kind: .rule)
        #expect(displayedParagraph("corpo\ndopo\n", markers: [stale]) == nil)
    }

    @Test func theRuleHookIsInertWhenTheSettingIsOff() {
        #expect(displayedParagraph(Self.note, markers: [Self.marker], hidesMarkup: false) == nil)
    }
}

// MARK: - Coordinator-level (ADR-0018)

/// Driven through a real `NSTextView` offscreen, like `SpellCheckTests`'s
/// `spellingState(over:in:)` and `FoldBadgeClickTests`'s `editor(folded:onToggleFold:)`:
/// `applyStyling` and `applyReveal` are methods of `NoteTextView.Coordinator`, and the
/// fastest way to lie to a test is to reimplement the thing it is checking.
@MainActor
@Suite struct MarkupCoordinator {
    private static let threeHeadingNote = "# Uno\ncorpo **uno**\n# Due\ncorpo due\n# Tre\ncorpo tre\n"

    private static func editor(hidesMarkup: Bool) -> (NSTextView, NoteTextView.Coordinator) {
        let view = NoteTextView(
            text: .constant(threeHeadingNote), theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: hidesMarkup, onFollowLink: { _ in }
        )
        let coordinator = view.makeCoordinator()
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.delegate = coordinator
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.string = threeHeadingNote
        coordinator.applyStyling(to: textView, theme: .emergency)
        // `applyStyling` rewrites every attribute in the storage, and on a headless text
        // view with no window that leaves the selection at the very end of the text
        // rather than at the start - a harness artifact, not something the running app
        // does (its own call sites manage the selection separately). Pinned here so the
        // reveal tests below start from a known caret.
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        return (textView, coordinator)
    }

    /// "# Due"'s own paragraph start, for tests that need a genuine selection change.
    /// "# Uno\n" (6) + "corpo **uno**\n" (14).
    private static let headingDue = 20

    @Test func stylingAThreeHeadingNotePopulatesAllDelegateEntries() {
        let (_, coordinator) = Self.editor(hidesMarkup: true)
        // Three heading markers plus the two `**` delimiters of "**uno**".
        #expect(coordinator.decorations.hiddenMarkerCount == 5)
    }

    @Test func callingApplyRevealTwiceWithoutASelectionChangeDoesNotReinvalidateTheSecondTime() throws {
        let (textView, coordinator) = Self.editor(hidesMarkup: true)
        let storage = try #require(textView.textStorage)

        // `NSTextStorageDidProcessEditing` is what `storage.edited(…)` plus `endEditing()`
        // fires - the observable half of "did this actually touch the layout", the same
        // way `SpellCheckTests` reads the layout manager's rendering attribute rather than
        // trusting the delegate's own return value.
        let counter = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil
        ) { _ in counter.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }

        // A genuine change first, so what follows tests a real transition rather than two
        // no-ops in a row. `setSelectedRange` fires `textViewDidChangeSelection` - the same
        // path a real arrow key takes - which is wired to call `applyReveal` itself.
        textView.setSelectedRange(NSRange(location: Self.headingDue, length: 0))
        let afterTheChange = counter.count
        #expect(afterTheChange > 0)

        // The same selection again: nothing moved, so the second call must be a no-op.
        coordinator.applyReveal(to: textView)
        #expect(counter.count == afterTheChange)
    }

    /// Principle 1, checked at the coordinator level rather than only in
    /// `MarkdownStylerTests` and `MarkupHidingTests`: styling and revealing a note must
    /// never touch `textView.string`, whatever else they change about how it is drawn.
    @Test func theStringIsByteIdenticalAfterStylingAndReveal() {
        let (textView, coordinator) = Self.editor(hidesMarkup: true)
        coordinator.applyReveal(to: textView)
        #expect(textView.string == Self.threeHeadingNote)
    }
}

/// `NotificationCenter`'s handler closure is `@Sendable`, and every call in this file
/// happens synchronously on the main actor anyway - the observer fires from inside
/// `storage.endEditing()`, called directly by `applyReveal` above. `@unchecked Sendable`
/// says so, rather than fighting the compiler over a `var` a `@Sendable` closure cannot
/// capture.
private final class NotificationCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}

// MARK: - The per-marker filter and the two new delegate inputs (ADR-0037 §D2/§D3; plan
// `2026-09-08-word-grained-markdown-reveal-on-caret-in`, Task 3)
//
// `EditorDecorationDelegate.collapsing(among:paragraphIsRevealed:revealedSpans:)` is
// exercised directly, as a pure static function, rather than through a full layout pass -
// the same reason the ADR itself gives for making it one: it is testable without a text
// view. The hook's own last guard is not yet wired to call it (tester half of Task 3; the
// coder half rewires it per the TODO left beside that guard), so
// `theHookReturnsNilForARevealedParagraph` above stays green **unedited**, and R-07 is
// pinned again below through the public `displayedParagraph` helper, extended with the two
// new, defaulted `spans:`/`revealsInlineSpans:` parameters rather than replaced.
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
    // above): a heading marker (paragraph-grained) beside a bold pair (span-grained) in the
    // same paragraph (R-06).
    private static let headingAndBoldNote = "# Titolo **enfasi** qui\n"
    private static let headingMarker = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .heading)
    private static let boldOpen = HiddenMarker(range: NSRange(location: 9, length: 2), kind: .emphasis)
    private static let boldClose = HiddenMarker(range: NSRange(location: 17, length: 2), kind: .emphasis)

    private static let ruleMarker = HiddenMarker(range: NSRange(location: 0, length: 3), kind: .rule)

    // MARK: R-07 - the setting off leaves the hook untouched

    @Test func theHookReturnsNilWhenTheSettingIsOffEvenWithSpansSupplied() {
        let displayed = displayedParagraph(
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
        let displayed = displayedParagraph(
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
}

// MARK: - The note editor's own wiring (ADR-0037 §D6/§D7; plan
// `2026-09-08-word-grained-markdown-reveal-on-caret-in`, Task 5)
//
// Drives a real `NoteTextView.Coordinator` + `NSTextView`, the shape `MarkupCoordinator`
// above already uses. `EditorDecorationDelegate.revealedSpans` has no test accessor - that
// file is out of this task's budget (ADR-0049) - so "the span table names exactly one
// paragraph key with exactly one range" is read back through `coordinator.lastRevealedSpans`
// instead: it is assigned the very value handed to `decorations.apply(revealedSpans:)` right
// before that call, in `NoteTextView+Reveal.swift`, so the two can never disagree.
@MainActor
@Suite struct MarkupCoordinatorInlineSpans {
    /// Two bold runs, neither touching the note's very first character - unlike
    /// `MarkupHidingInlineSpans`'s "**uno** e **due**\n" fixture, whose first run starts at
    /// offset 0 and would already be (adjacency-)revealed by the harness's own baseline
    /// caret placement (ADR §D5's closed interval), leaving a test that moves the caret
    /// *into* that run unable to observe a real transition.
    private static let note = "inizio **uno** e **due** fine\n"
    /// Inside "uno", well within the first run's whole construct `[7, 14)`.
    private static let insideFirstRun = 10
    /// "e" between the two runs: 15 > `NSMaxRange(firstBoldSpan)` (14) and 15 < the second
    /// run's own start (17).
    private static let outsideBothRuns = 15
    private static let firstBoldSpan = NSRange(location: 7, length: 7)

    private static func editor(revealsInlineSpans: Bool) -> (NSTextView, NoteTextView.Coordinator) {
        let view = NoteTextView(
            text: .constant(Self.note), theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: true, revealsInlineSpans: revealsInlineSpans, onFollowLink: { _ in }
        )
        let coordinator = view.makeCoordinator()
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.delegate = coordinator
        textView.textContentStorage?.delegate = coordinator.decorations
        textView.string = Self.note
        coordinator.applyStyling(to: textView, theme: .emergency)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        return (textView, coordinator)
    }

    @Test func aCaretInsideOneBoldRunNamesExactlyThatParagraphAndSpan() {
        let (textView, coordinator) = Self.editor(revealsInlineSpans: true)
        textView.setSelectedRange(NSRange(location: Self.insideFirstRun, length: 0))

        #expect(coordinator.lastRevealedSpans.count == 1)
        #expect(coordinator.lastRevealedSpans[0] == [Self.firstBoldSpan])
    }

    @Test func movingTheCaretOutOfBothRunsEmptiesTheTable() {
        let (textView, coordinator) = Self.editor(revealsInlineSpans: true)
        textView.setSelectedRange(NSRange(location: Self.insideFirstRun, length: 0))
        #expect(!coordinator.lastRevealedSpans.isEmpty)

        textView.setSelectedRange(NSRange(location: Self.outsideBothRuns, length: 0))
        #expect(coordinator.lastRevealedSpans.isEmpty)
    }

    @Test func flippingTheSettingOffWithTheCaretStillInsideARunEmptiesTheTable() {
        let (textView, coordinator) = Self.editor(revealsInlineSpans: true)
        textView.setSelectedRange(NSRange(location: Self.insideFirstRun, length: 0))
        #expect(!coordinator.lastRevealedSpans.isEmpty)

        // The caret never moves - only the setting does, so nothing but the flag flip can
        // be what empties the table.
        coordinator.parent.revealsInlineSpans = false
        coordinator.applyReveal(to: textView)
        #expect(coordinator.lastRevealedSpans.isEmpty)
    }

    @Test func callingApplyRevealTwiceWithoutASelectionChangeInvalidatesNothingTheSecondTime() throws {
        let (textView, coordinator) = Self.editor(revealsInlineSpans: true)
        let storage = try #require(textView.textStorage)

        // Same mechanism as `MarkupCoordinator`'s own test above: the notification is what
        // `storage.edited(…)` plus `endEditing()` fires, the observable half of "did this
        // actually touch the layout".
        let counter = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil
        ) { _ in counter.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }

        // A genuine change first - moving into the first run touches the span table, unlike
        // `MarkupCoordinator`'s heading-only fixture.
        textView.setSelectedRange(NSRange(location: Self.insideFirstRun, length: 0))
        let afterTheChange = counter.count
        #expect(afterTheChange > 0)

        // The same selection again, with the setting also unchanged: both `lastRevealed`
        // and `lastRevealedSpans` must already match, so this call is a no-op.
        coordinator.applyReveal(to: textView)
        #expect(counter.count == afterTheChange)
    }
}
