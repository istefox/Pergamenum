import AppKit

/// Draws a concealed Pratiche anchor line, `<!-- pergamenum-message: <Message-ID> -->`, as one
/// small envelope at the start of its row (ADR-0076 §D9, R-20) - the marker gate G1 left to the
/// implementation. `HorizontalRuleFragment`'s shape: the line's own characters are collapsed into
/// `collapsedFont` by the generic path, the paragraph's newline keeps a full row's height, and
/// this fragment draws into that row. Vended by
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
    /// Wider than the symbol at `markerPointSize`, so the drawing is never clipped at the
    /// collapsed text's own, nearly zero, width: 18pt at the caption token's 11pt.
    private var markerWidth: CGFloat { markerPointSize + 7 }

    override var renderingSurfaceBounds: CGRect {
        let base = super.renderingSurfaceBounds
        return CGRect(x: base.minX, y: base.minY, width: max(base.width, markerWidth), height: base.height)
    }

    /// The envelope, centred vertically in the row the paragraph's newline reserves.
    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        let configuration = NSImage.SymbolConfiguration(pointSize: markerPointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [markerColor]))
        guard let image = NSImage(systemSymbolName: Self.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return }
        let size = image.size
        let rect = CGRect(
            x: point.x,
            y: point.y + (layoutFragmentFrame.height - size.height) / 2,
            width: size.width,
            height: size.height
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
}
