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
    revealed: Set<Int> = []
) -> NSTextParagraph? {
    let delegate = EditorDecorationDelegate()
    delegate.apply(hiddenMarkers: [location: markers], hidingMarkup: hidesMarkup)
    _ = delegate.apply(revealedParagraphs: revealed)

    let content = NSTextContentStorage()
    content.textStorage?.setAttributedString(NSAttributedString(string: note))
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
}
