import AppKit

/// Draws a concealed Pratiche anchor line, `<!-- pergamenum-message: <Message-ID> -->`, as one
/// small envelope at the start of its row (ADR-0076 §D9, R-20) - the marker gate G1 left to the
/// implementation. `HorizontalRuleFragment`'s shape: the line's own characters are collapsed into
/// `collapsedFont` by the generic path, and this fragment draws the envelope over the row that is
/// left - in the editor only a few points tall, so `renderingSurfaceBounds` grows past it to hold
/// the whole symbol (`markerFrame`). Vended by
/// `EditorDecorationDelegate.textLayoutManager(_:textLayoutFragmentFor:in:)` only while «Nascondi
/// markup» is on and the caret is not in the line; revealed, the line is raw text.
///
/// The envelope says what the line points at, a message, and nothing more: the Message-ID itself
/// is the raw line, one caret move away.
final class MessageAnchorFragment: NSTextLayoutFragment {
    /// The marker's colour, pushed in from a theme token (`EditorDecorationDelegate.messageAnchorColor`)
    /// the way `HorizontalRuleFragment.ruleColor` is - never hardcoded.
    nonisolated(unsafe) var markerColor: NSColor = .tertiaryLabelColor
    /// The envelope's point size, pushed in from a typography token
    /// (`EditorDecorationDelegate.messageAnchorPointSize`) the way `FoldedHeadingFragment.badgeFont`
    /// is - never hardcoded. The default is what an offscreen harness draws with.
    nonisolated(unsafe) var markerPointSize: CGFloat = 11

    private static let symbolName = "envelope"
    /// Room kept around the envelope inside the surface, so its antialiased edge is not shaved.
    private static let surfaceOutset: CGFloat = 1

    /// The envelope as drawn: the symbol at `markerPointSize`, in `markerColor`.
    private var markerImage: NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: markerPointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [markerColor]))
        return NSImage(systemSymbolName: Self.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    /// Where the envelope sits in the fragment's own coordinates: at the row's start, centred on
    /// the row's vertical middle. One computation for `draw(at:in:)` and `renderingSurfaceBounds`
    /// (`FoldedHeadingFragment.badgeFrame`'s rule, PG-021). With «Nascondi markup» on the
    /// collapsed row is only a few points tall, so the envelope reaches above and below it,
    /// evenly, into the space the heading above and the body below already leave.
    var markerFrame: CGRect {
        guard let size = markerImage?.size else { return .null }
        return CGRect(
            x: 0, y: (layoutFragmentFrame.height - size.height) / 2, width: size.width, height: size.height
        )
    }

    /// The row's own surface grown to hold the whole envelope - wider than the collapsed text's
    /// nearly zero width, and taller than the collapsed row - or the drawing is clipped to a
    /// sliver. The header allows a surface "larger than layoutFragmentFrame.size" for exactly a
    /// decoration drawn past the text, as `HorizontalRuleFragment` and `FoldedHeadingFragment` do.
    override var renderingSurfaceBounds: CGRect {
        let base = super.renderingSurfaceBounds
        let marker = markerFrame
        guard !marker.isNull else { return base }
        return base.union(marker.insetBy(dx: -Self.surfaceOutset, dy: -Self.surfaceOutset))
    }

    /// The envelope, at `markerFrame`.
    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        guard let image = markerImage else { return }
        let rect = markerFrame.offsetBy(dx: point.x, dy: point.y)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
}
