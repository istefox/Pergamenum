import AppKit
import Testing
@testable import Pergamenum

/// Bugfix red test: `FoldedHeadingFragment.badgeFrame(at:)` centers the badge on the line's
/// FULL `typographicBounds.height`:
///
/// ```
/// y: point.y + line.typographicBounds.minY
///     + (line.typographicBounds.height - size.height - Self.padding.height * 2) / 2,
/// ```
///
/// That height is not the height of the heading's own glyphs. Since ADR-0030,
/// `ProseTypography` composes a `lineHeightMultiple` scaled up to the *heading's* larger font
/// size (e.g. a level-2 heading at 22pt gets a multiple around 1.9 - nearly double the font's
/// natural single-line height). TextKit adds that inflation BELOW the glyphs, not split
/// symmetrically above/below - the same asymmetric-slack assumption already relied on by
/// `TranscludedLineFragment.swift` (lines ~106, ~157), which treats `typographicBounds.maxY`
/// as "below the text" rather than as the box's true geometric center line. Centering the
/// badge on the *whole* inflated box therefore pulls it down into the slack, well below the
/// heading text it is supposed to sit beside - confirmed by hand-check screenshot.
///
/// INVARIANT THE CODER MUST IMPLEMENT (mechanism is the coder's choice - `glyphOrigin`, the
/// real font's ascent/descent, or `typographicBounds.minY` alone without the inflated-height
/// term are all acceptable shapes, this test pins only the observable result): the badge's
/// vertical center must track the heading's actual GLYPH box, not the inflated line box. With
/// a large `lineHeightMultiple` in play, `badgeFrame(at:).midY` must land close to the real
/// text's own vertical center (within its font's own ascent+descent), not close to the
/// midpoint of the full, inflated `typographicBounds.height`.
///
/// Built the way `TranscludedLineFragmentWidthTests.swift` builds its fixtures: a real
/// `NSTextContentStorage` + `NSTextLayoutManager` + `NSTextContainer`, offscreen, no
/// `NoteTextView` involved. `FoldedHeadingFragment` is handed back from the layout manager's
/// own `textLayoutFragmentFor:in:` delegate hook - the only supported way to get a custom
/// `NSTextLayoutFragment` subclass into a real layout pass (see
/// `EditorDecorationDelegate.textLayoutManager(_:textLayoutFragmentFor:in:)`,
/// `EditorDecorationDelegate.swift` ~293-300, which assigns `hiddenLines`/`headingOffset`/
/// `badgeColor`/`badgeBackground`/`badgeFont` on exactly this fragment type).
@MainActor
@Suite struct FoldedHeadingBadgeVerticalCenterTests {
    /// A short heading line - what matters for this bug is the font/paragraph-style
    /// inflation, not the text's own width or content.
    private static let headingLine = "# Titolo"

    /// The heading's own face: large enough that a lineHeightMultiple scaled to it produces
    /// meaningfully more slack than a body-sized line would (ADR-0030's own level-2 heading
    /// example, ~22pt).
    private static let headingFontSize: CGFloat = 22
    private static let headingFont = NSFont.systemFont(ofSize: headingFontSize, weight: .bold)

    /// Deliberately large - `ProseTypography`'s real composed multiple for a heading this
    /// size is around 1.9 (`1.4 * 22/16`); using that same order of magnitude here reproduces
    /// the bug at the same scale production code hits it at, not a synthetic extreme.
    private static let lineHeightMultiple: CGFloat = 1.9

    private static let badgeFontSize: CGFloat = 10
    private static let containerWidth: CGFloat = 600

    /// Hands back a `FoldedHeadingFragment`, the same hook production wiring uses.
    private final class FragmentDelegate: NSObject, NSTextLayoutManagerDelegate, @unchecked Sendable {
        nonisolated(unsafe) var made: FoldedHeadingFragment?

        func textLayoutManager(
            _ textLayoutManager: NSTextLayoutManager,
            textLayoutFragmentFor location: NSTextLocation,
            in textElement: NSTextElement
        ) -> NSTextLayoutFragment {
            let fragment = FoldedHeadingFragment(textElement: textElement, range: textElement.elementRange)
            made = fragment
            return fragment
        }
    }

    /// Also returns the content storage, layout manager and delegate: all are weak/unowned on
    /// AppKit's side (`NSTextLayoutManager.delegate`, `.textContainer`, the content storage's
    /// layout-manager list), so the caller must keep every piece alive for as long as it reads
    /// the fragment's line-fragment geometry - see the sibling `TranscludedLineFragmentWidthTests`
    /// for the same note on why the tuple, not just the fragment, is returned.
    private static func fragment() -> (
        fragment: FoldedHeadingFragment, content: NSTextContentStorage,
        layout: NSTextLayoutManager, delegate: FragmentDelegate
    ) {
        let content = NSTextContentStorage()
        let layout = NSTextLayoutManager()
        content.addTextLayoutManager(layout)
        let container = NSTextContainer(
            size: CGSize(width: containerWidth, height: .greatestFiniteMagnitude)
        )
        layout.textContainer = container

        let delegate = FragmentDelegate()
        layout.delegate = delegate

        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple

        content.textStorage?.setAttributedString(
            NSAttributedString(
                string: headingLine,
                attributes: [
                    .font: headingFont,
                    .paragraphStyle: style,
                ]
            )
        )
        layout.ensureLayout(for: layout.documentRange)

        guard let made = delegate.made else {
            fatalError("layout never asked the delegate for a fragment")
        }
        return (made, content, layout, delegate)
    }

    @Test func theBadgeCentersOnTheHeadingsGlyphsNotOnTheInflatedLineHeight() {
        let built = Self.fragment()
        let fragment = built.fragment
        fragment.hiddenLines = 3
        fragment.badgeFont = .systemFont(ofSize: Self.badgeFontSize, weight: .regular)

        guard let line = fragment.textLineFragments.first else {
            Issue.record("fragment produced no line fragment - fixture is broken")
            return
        }

        // Fixture invariant: the composed line-height multiple must actually have inflated
        // the box well past the font's own natural single-line height, or this test would
        // stop exercising the bug (a nearly-uninflated box centers correctly either way).
        let naturalLineHeight = Self.headingFont.ascender - Self.headingFont.descender + Self.headingFont.leading
        #expect(
            line.typographicBounds.height > naturalLineHeight * 1.3,
            "fixture invariant broke: the paragraph style's lineHeightMultiple is no longer producing meaningful slack below the glyphs, so this test would no longer exercise the bug"
        )

        // The real anchor: the heading glyphs' own vertical center, derived from the font's
        // ascent/descent rather than from the inflated line box. `glyphOrigin.y` (baseline
        // offset within the line fragment) plus half the descent minus half the ascent gives
        // the glyph box's own midpoint - this is the target the badge must track, independent
        // of whichever slack TextKit adds below it.
        let glyphBoxMinY = line.typographicBounds.minY
            + line.glyphOrigin.y - Self.headingFont.ascender
        let glyphBoxHeight = Self.headingFont.ascender - Self.headingFont.descender
        let glyphBoxMidY = glyphBoxMinY + glyphBoxHeight / 2

        let box = fragment.badgeFrame(at: .zero)
        #expect(!box.isNull, "no badge frame produced with hiddenLines > 0")

        // The invariant: the badge's own vertical center must be close to the glyph box's
        // center (within the font's own ascent+descent - a generous tolerance for whatever
        // exact anchor point the fix lands on), never close to the inflated box's center,
        // which for this fixture sits meaningfully lower.
        let tolerance = glyphBoxHeight
        #expect(
            abs(box.midY - glyphBoxMidY) <= tolerance,
            "badge vertical center \(box.midY) is not anchored to the heading's own glyph box (center \(glyphBoxMidY), tolerance \(tolerance)) - it is being pulled toward the inflated typographicBounds instead"
        )

        // Sharper framing of the same bug: the badge's center must be measurably CLOSER to
        // the glyph box's center than to the inflated box's center. Centering on the full
        // `typographicBounds.height` (today's production formula) necessarily lands closer
        // to the inflated midpoint than to the glyph midpoint whenever the multiple has
        // produced real slack, which the fixture invariant above just confirmed it has.
        let inflatedBoxMidY = line.typographicBounds.minY + line.typographicBounds.height / 2
        #expect(
            abs(box.midY - glyphBoxMidY) < abs(box.midY - inflatedBoxMidY),
            "badge center \(box.midY) is closer to the inflated line box's midpoint (\(inflatedBoxMidY)) than to the heading glyphs' own midpoint (\(glyphBoxMidY)) - this is exactly the bug: centering divides by the full lineHeightMultiple-inflated typographicBounds.height instead of the real glyph box"
        )
    }
}
