import AppKit
import Testing
@testable import Pergamenum

// Regression test for a bug found while reviewing `ListMarkerRendering.swift` +
// `EditorDecorationDelegate+ListRendering.swift` on branch `feat/editor-page-typography-noteplan`.
//
// BUG: `ListMarkerRendering.paragraphStyle(level:font:basedOn:)` computes
// `em = max(font.pointSize, 1)` and derives `firstLineHeadIndent`/`headIndent` from it. The
// caller, `EditorDecorationDelegate.listParagraph(at:storage:)`, resolves that `font` argument
// through `bodyFont(of:after:)`, which reads the `.font` attribute of the single character right
// after the list marker (`EditorDecorationDelegate+ListRendering.swift:86-92`). When a list item's
// text *starts* with a styled run at a different point size than the paragraph's real body font
// (`font.prose`, 16pt via `ProseTypography`) - e.g. a bold run at 17pt (`ProseTypography.bolded`
// preserves point size, but a heading-sized or otherwise-resized leading run does not), or any
// inline code/heading-fold badge font at a different size - the indent step for that one item is
// computed from the wrong font size. This produces a visibly inconsistent indent at a given
// nesting level compared to sibling items at the same level whose first character is plain body
// text.
//
// INVARIANT THE CODER MUST IMPLEMENT (signature is the coder's choice of internal fix, this test
// pins the observable behaviour): for a fixed `level` and a fixed `basedOn`, the indent computed
// by `ListMarkerRendering.paragraphStyle(level:font:basedOn:)` — or whatever replaces the value
// `EditorDecorationDelegate` passes as `font` at its one call site — must be the SAME regardless
// of the point size of the trailing run's font. The indent step must be derived from the page's
// own body font size (`font.prose`, i.e. `ProseTypography.prose(theme)` / the value pushed into
// `EditorDecorationDelegate.proseFont`), never from whatever font happens to sit on the character
// right after the marker.
//
// Two acceptable shapes for the fix, either is fine as long as the assertions below pass:
//   1. `ListMarkerRendering.paragraphStyle(level:font:basedOn:)` keeps its signature, and
//      `EditorDecorationDelegate.bodyFont(of:after:)` (or its call site) is changed to stop
//      resolving `font` from the trailing run and instead pass `Self.proseFont` (or an
//      unconditional fallback that ignores the run's own size).
//   2. `ListMarkerRendering.paragraphStyle` gains an explicit reference-size parameter (e.g.
//      `referenceFont: NSFont` or `emSize: CGFloat`) that indent arithmetic uses instead of
//      `font.pointSize`, decoupling the em unit from whatever `font` is passed for other purposes.
// Either way, this file's two tests must both pass without being rewritten.

@Suite struct ListIndentFontInvariantTests {
    /// Direct unit test on `ListMarkerRendering.paragraphStyle` itself: two calls at the same
    /// level and `basedOn`, differing only in the passed font's point size, must produce the
    /// same indent. This currently FAILS because `em` is `max(font.pointSize, 1)`.
    @Test func indentAtAGivenLevelDoesNotDependOnTheTrailingRunsFontSize() {
        // font.prose's own default size (ProseTypography.swift / TokenKeys.swift, 16pt).
        let plainBodyFont = NSFont.systemFont(ofSize: 16)
        // A bold run at a different point size than the body - the failure mode described above
        // (e.g. a heading-fold badge font, or any styled run that does not preserve point size).
        let styledLeadingRunFont = NSFont.boldSystemFont(ofSize: 20)

        let plainStyle = ListMarkerRendering.paragraphStyle(level: 3, font: plainBodyFont)
        let styledStyle = ListMarkerRendering.paragraphStyle(level: 3, font: styledLeadingRunFont)

        #expect(
            plainStyle.firstLineHeadIndent == styledStyle.firstLineHeadIndent,
            "level 3 firstLineHeadIndent must not depend on the trailing run's font size: plain(16pt)=\(plainStyle.firstLineHeadIndent) styled(20pt)=\(styledStyle.firstLineHeadIndent)"
        )
        #expect(
            plainStyle.headIndent == styledStyle.headIndent,
            "level 3 headIndent must not depend on the trailing run's font size: plain(16pt)=\(plainStyle.headIndent) styled(20pt)=\(styledStyle.headIndent)"
        )
    }

    /// Integration-style test through the real substitution path: a level-3 list item whose text
    /// starts with a bold run at a different point size than the paragraph's own body font must
    /// still indent identically to a sibling item at the same level whose text is plain. Exercises
    /// `EditorDecorationDelegate.listParagraph(at:storage:)` end to end, the same call `bodyFont(of:after:)`
    /// makes today from the character right after the marker.
    @MainActor
    @Test func aBoldLeadingListItemIndentsTheSameAsAPlainSiblingAtTheSameLevel() {
        // Two level-3 items (six leading spaces, ADR-0028's own two-space-per-level convention),
        // one plain, one starting with a bold run rendered at a larger point size than the body.
        let plainNote = "      - piano\n"
        let boldNote = "      - **grassetto**\n"

        let plainMarker = HiddenMarker(range: NSRange(location: 6, length: 2), kind: .list)
        let boldListMarker = HiddenMarker(range: NSRange(location: 6, length: 2), kind: .list)
        let boldEmphasisOpen = HiddenMarker(range: NSRange(location: 8, length: 2), kind: .emphasis)
        let boldEmphasisClose = HiddenMarker(range: NSRange(location: 20, length: 2), kind: .emphasis)

        let plainStyle = Self.listParagraphStyle(
            plainNote, markers: [plainMarker], bodyFontSize: 16, boldRunRange: nil
        )
        let boldStyle = Self.listParagraphStyle(
            boldNote, markers: [boldListMarker, boldEmphasisOpen, boldEmphasisClose],
            bodyFontSize: 16,
            // The bold run starts right after the marker (offset 8) and is deliberately given a
            // larger point size than the body font, reproducing the bug: `bodyFont(of:after:)`
            // reads the font attribute at the character right after the marker, which is inside
            // this run.
            boldRunRange: NSRange(location: 8, length: 10)
        )

        #expect(plainStyle != nil, "no paragraph style produced for the plain sibling")
        #expect(boldStyle != nil, "no paragraph style produced for the bold-leading item")
        #expect(
            plainStyle?.firstLineHeadIndent == boldStyle?.firstLineHeadIndent,
            "a level-3 item starting with a differently-sized bold run must indent identically to its plain sibling: plain=\(String(describing: plainStyle?.firstLineHeadIndent)) bold=\(String(describing: boldStyle?.firstLineHeadIndent))"
        )
        #expect(plainStyle?.headIndent == boldStyle?.headIndent)
    }

    /// Drives `EditorDecorationDelegate.textContentStorage(_:textParagraphWith:)` by hand over
    /// the first paragraph of `note`, the same pattern `MarkupHidingTests.swift`'s own
    /// `substitutedParagraph`/`displayedParagraph` helpers use - real `EditorDecorationDelegate`,
    /// real `NSTextContentStorage`, no layout manager needed since the hook only reads the
    /// storage's attributed string.
    @MainActor
    private static func listParagraphStyle(
        _ note: String, markers: [HiddenMarker], bodyFontSize: CGFloat, boldRunRange: NSRange?
    ) -> NSParagraphStyle? {
        let storage = NSMutableAttributedString(string: note)
        storage.addAttribute(
            .font, value: NSFont.systemFont(ofSize: bodyFontSize),
            range: NSRange(location: 0, length: (note as NSString).length)
        )
        if let boldRunRange {
            storage.addAttribute(
                .font, value: NSFont.boldSystemFont(ofSize: bodyFontSize + 4), range: boldRunRange
            )
        }

        let content = NSTextContentStorage()
        content.textStorage?.setAttributedString(storage)

        let delegate = EditorDecorationDelegate()
        delegate.apply(hiddenMarkers: [0: markers], hidingMarkup: true)

        let range = (note as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        guard let paragraph = delegate.textContentStorage(content, textParagraphWith: range) else { return nil }

        return paragraph.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    }
}
