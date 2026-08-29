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
private func substitutedParagraph(_ delegate: EditorDecorationDelegate, note: String) -> NSTextParagraph? {
    let storage = NSTextContentStorage()
    storage.textStorage?.setAttributedString(NSAttributedString(string: note))
    let range = (note as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
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
    hidesMarkup: Bool = true,
    revealed: Set<Int> = []
) -> NSTextParagraph? {
    let delegate = EditorDecorationDelegate()
    delegate.apply(hiddenMarkers: [0: markers], hidingMarkup: hidesMarkup)
    _ = delegate.apply(revealedParagraphs: revealed)
    return substitutedParagraph(delegate, note: note)
}

/// The length of `note`'s first paragraph, the number a substitution of it must return
/// unchanged.
private func firstParagraphLength(of note: String) -> Int {
    (note as NSString).paragraphRange(for: NSRange(location: 0, length: 0)).length
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

    /// Two spaces of indentation and then `- `: four characters, all inside the range.
    private static let nested = "  - annidato\ncorpo\n"
    private static let nestedMarker = HiddenMarker(range: NSRange(location: 0, length: 4), kind: .list)

    /// A list item whose text is emphasised - the SPEC's coexistence case. `**` opens at
    /// index 2 and closes at index 13.
    private static let mixed = "- **grassetto** elemento\n"
    private static let mixedList = HiddenMarker(range: NSRange(location: 0, length: 2), kind: .list)
    private static let mixedOpen = HiddenMarker(range: NSRange(location: 2, length: 2), kind: .emphasis)
    private static let mixedClose = HiddenMarker(range: NSRange(location: 13, length: 2), kind: .emphasis)

    private static let everyCase: [(note: String, markers: [HiddenMarker])] = [
        (unordered, [unorderedMarker]),
        (ordered, [orderedMarker]),
        (nested, [nestedMarker]),
        (mixed, [mixedList, mixedOpen, mixedClose])
    ]

    /// First and loudest (R-10's structural half, and the plan's highest-listed risk): the
    /// file must not gain or lose a character, whatever is drawn over it. Checked through a
    /// real layout pass, with the setting on and off and the paragraph revealed and not,
    /// because a substitution that changes length does not show up as a wrong picture - it
    /// shows up later as offsets drifting between the storage and the layout.
    @Test func theStorageNeverGainsOrLosesACharacterForAnyListCase() {
        for (note, markers) in Self.everyCase {
            let source = (note as NSString).length
            for hides in [true, false] {
                for revealed in [Set<Int>(), Set([0])] {
                    let measured = frames(
                        text: note, markers: [0: markers], hidesMarkup: hides, revealed: revealed
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
        for (note, markers) in Self.everyCase {
            let displayed = displayedParagraph(note, markers: markers)
            #expect(displayed != nil, "«\(note)»: nessuna sostituzione")
            #expect(
                displayed?.attributedString.length == firstParagraphLength(of: note),
                "«\(note)»: lunghezza \(displayed?.attributedString.length ?? -1)"
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
        let deeper = displayedParagraph(Self.nested, markers: [Self.nestedMarker])
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
        let displayed = displayedParagraph(Self.nested, markers: [Self.nestedMarker])
        var effective = NSRange(location: 0, length: 0)
        _ = displayed?.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: &effective)

        #expect(displayed != nil)
        #expect(effective.length == displayed?.attributedString.length)
    }

    /// R-05's «no double indentation» half: the two spaces the source spells are collapsed
    /// into `collapsedFont`, so the only thing indenting the line is the paragraph style
    /// above. Left visible, they would be added to it.
    @Test func theLeadingIndentIsDrawnInTheCollapsedFont() {
        let displayed = displayedParagraph(Self.nested, markers: [Self.nestedMarker])
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
        #expect(displayedParagraph(Self.nested, markers: [Self.nestedMarker], revealed: [0]) == nil)
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
            displayedParagraph(Self.nested, markers: [Self.nestedMarker], hidesMarkup: false) == nil
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
