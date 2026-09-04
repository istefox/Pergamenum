import AppKit
import Testing
@testable import Pergamenum

/// Bugfix red test: `TranscludedLineFragment.draw(at:in:)` lays its body out at
/// `layoutFragmentFrame.width`, which in TextKit 2 is the width of the *source line's own
/// text* (the short `![[Nota]]` wikilink), not the text container's column width. This makes
/// the transcluded body wrap as if the container were a few dozen points wide, while
/// `NoteTextView+Transclusion.swift`'s `reserveSpace`/`rendition(for:width:theme:)` correctly
/// measure `reservedHeight` against `textContainer?.size.width` - so the reserved height and
/// the drawn content are computed at two different widths and the content clips.
///
/// `HorizontalRuleFragment.ruleWidth` (`HorizontalRuleFragment.swift:31-34`) already documents
/// and fixes exactly this class of mistake for a different fragment: it reads
/// `textLayoutManager?.textContainer.size.width`, never `layoutFragmentFrame.width`.
/// `TranscludedLineFragment.containerWidth` is the same fix, declared here as the interface
/// the coder must wire into `draw(at:in:)` (currently still reading the wrong value, so this
/// test is red against the *production* stub, not a build failure).
///
/// Built the way `TransclusionLayoutTests.swift` builds its fixtures: a real
/// `NSTextContentStorage` + `NSTextLayoutManager` + `NSTextContainer`, offscreen, no
/// `NoteTextView` involved - `TranscludedLineFragment.containerWidth` only needs
/// `textLayoutManager`, which a bare `NSTextLayoutFragment` subclass gets from being attached
/// to a layout manager, not from anything AppKit-view-shaped.
@MainActor
@Suite struct TranscludedLineFragmentWidth {
    /// A source line short enough that `layoutFragmentFrame.width` (the text's own width) is
    /// nowhere near the container's width below - reproducing "one word per line" at the bug's
    /// root cause rather than asserting on drawn pixels.
    private static let shortSourceLine = "![[N]]"

    /// Wide enough that no honest column-width read could coincide with the short line's own
    /// text width by accident.
    private static let containerWidth: CGFloat = 600
    private static let padding: CGFloat = 5

    /// Hands back a `TranscludedLineFragment` for every element, the same hook production
    /// wiring uses (`EditorDecorationDelegate.textLayoutManager(_:textLayoutFragmentFor:in:)`,
    /// `EditorDecorationDelegate.swift:255-270`) - the only supported way to get a custom
    /// `NSTextLayoutFragment` subclass into a real layout pass, so this mirrors it exactly
    /// rather than trying to splice a fragment in after the fact.
    private final class FragmentDelegate: NSObject, NSTextLayoutManagerDelegate, @unchecked Sendable {
        nonisolated(unsafe) var made: TranscludedLineFragment?

        func textLayoutManager(
            _ textLayoutManager: NSTextLayoutManager,
            textLayoutFragmentFor location: NSTextLocation,
            in textElement: NSTextElement
        ) -> NSTextLayoutFragment {
            let fragment = TranscludedLineFragment(textElement: textElement, range: textElement.elementRange)
            made = fragment
            return fragment
        }
    }

    /// Also returns the content storage and layout manager: `NSTextLayoutManager.delegate`,
    /// `.textContainer` and the content storage's own layout-manager list are all weak/unowned
    /// on AppKit's side, so the caller must keep every piece alive for as long as it reads
    /// `containerWidth` off the fragment - a fragment detached from a deallocated layout
    /// manager answers `textLayoutManager == nil` and the property under test would read as
    /// though the fix were never applied, for the wrong reason.
    private static func fragment() -> (
        fragment: TranscludedLineFragment, content: NSTextContentStorage,
        layout: NSTextLayoutManager, delegate: FragmentDelegate
    ) {
        let content = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        content.addTextLayoutManager(layout)
        let container = NSTextContainer(
            size: CGSize(width: containerWidth, height: .greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = padding
        layout.textContainer = container

        let delegate = FragmentDelegate()
        layout.delegate = delegate

        content.textStorage?.setAttributedString(
            NSAttributedString(
                string: shortSourceLine,
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]
            )
        )
        layout.ensureLayout(for: layout.documentRange)

        guard let made = delegate.made else {
            fatalError("layout never asked the delegate for a fragment")
        }
        return (made, content, layout, delegate)
    }

    @Test func theBodyWidthTracksTheContainerNotTheSourceLinesOwnTinyFrame() {
        let built = Self.fragment()
        let fragment = built.fragment

        // The bug, pinned down directly: `layoutFragmentFrame.width` for a six-character
        // wikilink is nowhere near the container's 600pt column.
        #expect(
            fragment.layoutFragmentFrame.width < 100,
            "fixture invariant broke: the short source line's own frame is no longer tiny, so this test would stop exercising the bug"
        )

        // What `containerWidth` must answer once the coder wires it up: the container's own
        // width minus its line-fragment padding on each side, exactly `HorizontalRuleFragment
        // .ruleWidth`'s formula - not the source line's own text width.
        let expected = Self.containerWidth - Self.padding * 2
        #expect(
            fragment.containerWidth == expected,
            "TranscludedLineFragment.containerWidth must read the text container's width (HorizontalRuleFragment.ruleWidth's formula), not layoutFragmentFrame.width"
        )
    }

    @Test func theBodyWidthMatchesWhatReserveSpaceMeasuredTheHeightAgainst() {
        // The other half of the bug: NoteTextView+Transclusion.swift's reservation measures
        // TranscludedRendition.height(of:width:) against textContainer?.size.width
        // (NoteTextView+Transclusion.swift:22-23). Whatever draw(at:in:) lays the body out at
        // must be the same number, or the reserved height and the drawn content disagree and
        // the content clips.
        let built = Self.fragment()
        let reservedAgainst = TranscludedRendition.bodyWidth(inContainerOf: Self.containerWidth)
        let drawnAgainst = TranscludedRendition.bodyWidth(inContainerOf: built.fragment.containerWidth)
        #expect(drawnAgainst == reservedAgainst)
    }
}
