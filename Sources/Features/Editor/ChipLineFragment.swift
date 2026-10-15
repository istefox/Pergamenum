import AppKit

/// The layout fragment of a paragraph that carries pills (ADR-0087 §D5): the standard line, with
/// `InlineChipPainter` filling each pill behind its glyphs.
final class ChipLineFragment: NSTextLayoutFragment {
    /// The pill's room and corners, pushed in from the delegate's `chipMetrics` the way
    /// `HorizontalRuleFragment.ruleColor` is.
    nonisolated(unsafe) var metrics = InlineChip.Metrics()

    /// Wide enough for a pill that starts its room before the first character.
    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.insetBy(dx: -metrics.padding, dy: 0)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        InlineChipPainter.paint(self, at: point, in: context, metrics: metrics)
        super.draw(at: point, in: context)
    }
}
