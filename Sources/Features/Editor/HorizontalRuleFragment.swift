import AppKit

/// Draws a `.rule` paragraph (`---`/`***`/`___`) as a real full-width line rather than as
/// three collapsed, invisible characters (ADR-0029 §D1) - the one ADR-0029 construct that
/// cannot length-preserve into a drawn line the way a blockquote bar or a strikethrough
/// delimiter can, so it needs its own `NSTextLayoutFragment` the way `FoldedHeadingFragment`
/// draws its badge and `TranscludedLineFragment` draws its card.
///
/// **Declared by the tester** (plan `2026-09-02-editor-wysiwyg-unification`, Task 2); the
/// coder fills `draw(at:in:)` and the branch in
/// `EditorDecorationDelegate.textLayoutManager(_:textLayoutFragmentFor:in:)` that hands one
/// back for a paragraph carrying a still-valid `.rule` marker, the same way that method
/// already branches on `renditions[start]` and `foldedHeadings[start]`.
final class HorizontalRuleFragment: NSTextLayoutFragment {
    /// The line's own colour, pushed in from a theme token the way
    /// `FoldedHeadingFragment.badgeColor` and `EmbedAttachment.handleColor` already are -
    /// never hardcoded (CLAUDE.md's design-system rule: "no hardcoded colour in a view").
    nonisolated(unsafe) var ruleColor: NSColor = .separatorColor

    private static let thickness: CGFloat = 1

    /// The width to draw across: the text container's, minus the padding a line fragment
    /// hangs at on each side.
    ///
    /// Not `layoutFragmentFrame.width`, which is the *text's* width and, for a paragraph
    /// whose `---` has just been collapsed to `collapsedFont`, is very nearly zero - a rule
    /// drawn at it would be invisible. The container is the only thing here that knows how
    /// wide a column is, and it is read at drawing time rather than pushed in for the reason
    /// ADR-0019 §D2 gives for `attachmentBounds`: a number handed over from outside goes
    /// stale on the next window resize.
    private var ruleWidth: CGFloat {
        guard let container = textLayoutManager?.textContainer else { return layoutFragmentFrame.width }
        return max(0, container.size.width - container.lineFragmentPadding * 2)
    }

    /// Wide enough for the line, or the drawing is clipped at the collapsed text's own
    /// width. The header is explicit that this "should be larger than
    /// layoutFragmentFrame.size", which is what a decoration drawn past the end of the text
    /// needs - `FoldedHeadingFragment` widens itself for its badge the same way.
    override var renderingSurfaceBounds: CGRect {
        let base = super.renderingSurfaceBounds
        return CGRect(x: base.minX, y: base.minY, width: max(base.width, ruleWidth), height: base.height)
    }

    /// The line, centred in the row the paragraph's own newline still reserves.
    ///
    /// That row is why this works at all: the marker covers the `---` and stops before the
    /// `\n`, so the newline keeps the body font and the paragraph keeps a full line's
    /// height with nothing drawn in it - exactly the band a separator wants.
    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        let width = ruleWidth
        guard width > 0 else { return }
        let height = layoutFragmentFrame.height
        let line = CGRect(
            x: point.x,
            y: point.y + (height - Self.thickness) / 2,
            width: width,
            height: Self.thickness
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        ruleColor.setFill()
        NSBezierPath(rect: line).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
