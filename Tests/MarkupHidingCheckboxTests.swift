import AppKit
import Testing
@testable import Pergamenum

// MARK: - Faces pushed onto the decoration delegate and the fold badge (ADR-0030 §D1/§D5)
//
// Task 4 of `2026-09-04-editor-page-typography-noteplan`. Both properties are plain stored
// values with system-face defaults. What is asserted here is the interface itself - default
// and settable - not a drawn pixel, which is out of reach without a pixel-level harness this repo does not have
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
                    let measured = MarkupHidingFixture.frames(
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
            let displayed = MarkupHidingFixture.displayedParagraph(note, markers: [marker])
            #expect(displayed != nil, "«\(note)»: nessuna sostituzione")
            #expect(
                displayed?.attributedString.length == MarkupHidingFixture.firstParagraphLength(of: note),
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
            let displayed = MarkupHidingFixture.displayedParagraph(note, markers: [marker])
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
            let firstParagraph = String(
                (note as NSString).substring(to: MarkupHidingFixture.firstParagraphLength(of: note))
            )
            #expect(displayed?.attributedString.string.dropFirst(5) == firstParagraph.dropFirst(5))
        }
    }

    /// The four non-glyph characters of the marker (`- [`, `]`) collapse into `collapsedFont`,
    /// leaving only the glyph itself undecorated.
    @Test func theNonGlyphCharactersOfTheMarkerAreCollapsed() {
        let displayed = MarkupHidingFixture.displayedParagraph(Self.open, markers: [Self.openMarker])
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
        #expect(MarkupHidingFixture.displayedParagraph(Self.open, markers: [Self.openMarker], revealed: [0]) != nil)
        #expect(MarkupHidingFixture.displayedParagraph(Self.done, markers: [Self.doneMarker], revealed: [0]) != nil)
    }

    /// ADR-0028 §D10's switch governs this marker kind too: off means off, whatever the reveal
    /// set says.
    @Test func theCheckboxHookIsInertWhenTheSettingIsOff() {
        #expect(
            MarkupHidingFixture.displayedParagraph(Self.open, markers: [Self.openMarker], hidesMarkup: false) == nil
        )
        #expect(
            MarkupHidingFixture.displayedParagraph(
                Self.open, markers: [Self.openMarker], hidesMarkup: false, revealed: [0]
            ) == nil
        )
    }

    /// The re-validation contract: a `.checkbox` entry whose characters no longer spell one of
    /// the four recognised states (malformed, or edited since the last styling pass) is skipped
    /// on its own account, the same as a stale `.list` entry.
    @Test func aStaleCheckboxEntryIsSkipped() {
        let note = "- [z] non è uno stato\n"
        let stale = HiddenMarker(range: NSRange(location: 0, length: 5), kind: .checkbox)

        let displayed = MarkupHidingFixture.displayedParagraph(note, markers: [stale])

        #expect(displayed == nil)
    }

    /// The SPEC's coexistence case for a task line: a checkbox and an emphasis pair drawn
    /// together in one paragraph, one substitution.
    @Test func aCheckboxAndAnEmphasisMarkerRenderTogetherInOneParagraph() {
        let note = "- [ ] **grassetto**\n"
        let checkbox = HiddenMarker(range: NSRange(location: 0, length: 5), kind: .checkbox)
        let openMark = HiddenMarker(range: NSRange(location: 6, length: 2), kind: .emphasis)
        let closeMark = HiddenMarker(range: NSRange(location: 17, length: 2), kind: .emphasis)

        let displayed = MarkupHidingFixture.displayedParagraph(note, markers: [checkbox, openMark, closeMark])

        #expect(displayed != nil)
        let string = displayed?.attributedString.string
        let stateIndex = string?.index(string!.startIndex, offsetBy: 3)
        #expect(stateIndex.flatMap { string?[$0] } == "\u{2610}")
        #expect(displayed?.attributedString.string.hasSuffix("grassetto**\n") == true)
        #expect(displayed?.attributedString.length == MarkupHidingFixture.firstParagraphLength(of: note))
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
