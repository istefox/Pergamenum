import AppKit

/// The layout fragment of a callout's title line (ADR-0087 §D8): the card's top band, the bar, the
/// kind's symbol, the Italian label when the line names no title, and a chevron when the callout is
/// foldable. The written title is the line's own text, drawn by TextKit in the type colour the
/// delegate's displayed copy gives it; the marker before it is collapsed.
final class CalloutTitleFragment: NSTextLayoutFragment {
    nonisolated(unsafe) var kind: CalloutKind = .note
    /// Nil when the callout is not foldable.
    nonisolated(unsafe) var isFolded: Bool?
    nonisolated(unsafe) var calloutOffset: Int = 0
    /// Whether the line names a title; when it does not, the fragment draws `kind.label`.
    nonisolated(unsafe) var hasTitle = true
    /// Whether a body line follows on screen: the card's bottom corners round here when none does.
    nonisolated(unsafe) var hasBody = true
    nonisolated(unsafe) var style = EditorConstructStyle()
    /// Where the column starts in the container, one quote step, and how far in the title starts.
    nonisolated(unsafe) var gutter: CGFloat = 0
    nonisolated(unsafe) var step: CGFloat = 0
    nonisolated(unsafe) var titleInset: CGFloat = 0

    private var column: CGRect { quoteColumn(gutter: gutter) }

    /// The first line's height, which the symbol, the label and the chevron are centred on.
    private func firstLineHeight(_ column: CGRect) -> CGFloat {
        textLineFragments.first?.typographicBounds.height ?? column.height
    }

    /// The symbol's box, centred in the room the title is inset by, on the first line.
    private func symbolFrame(in column: CGRect) -> CGRect {
        let side = style.calloutTitleFont.pointSize
        let start = column.minX + QuoteGeometry.indent(level: 1, step: step)
        return CGRect(
            x: start + (titleInset - side) / 2, y: column.minY + (firstLineHeight(column) - side) / 2,
            width: side, height: side
        )
    }

    /// The chevron's box, at the column's right end on the first line, in this fragment's coordinates.
    private func chevronFrame(in column: CGRect) -> CGRect {
        let side = style.calloutTitleFont.pointSize * 0.8
        return CGRect(
            x: column.maxX - side - style.chip.padding * 2, y: column.minY + (firstLineHeight(column) - side) / 2,
            width: side, height: side
        )
    }

    /// The chevron's box in the text container, nil when the callout is not foldable: what a click is
    /// compared with (`NoteTextView.Coordinator.toggleCallout(at:in:)`).
    var chevronFrameInContainer: CGRect? {
        guard isFolded != nil else { return nil }
        let frame = layoutFragmentFrame
        return chevronFrame(in: column).insetBy(dx: -4, dy: -4).offsetBy(dx: frame.minX, dy: frame.minY)
    }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.insetBy(dx: -style.chip.padding, dy: 0).union(column)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let column = column.offsetBy(dx: point.x, dy: point.y)
        let accent = style.accent(of: kind)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        CalloutCard.fill(
            column, roundingTop: true, roundingBottom: !hasBody || isFolded == true,
            color: style.band(of: kind), radius: style.cardRadius
        )
        if let offset = QuoteGeometry.barOffsets(level: 1, step: step).first {
            accent.setFill()
            NSBezierPath(rect: CGRect(
                x: column.minX + offset, y: column.minY, width: QuoteGeometry.barWidth, height: column.height
            )).fill()
        }
        Self.drawSymbol(kind.symbolName, in: symbolFrame(in: column), color: accent)
        if !hasTitle {
            let label = NSAttributedString(
                string: kind.label, attributes: [.font: style.calloutTitleFont, .foregroundColor: accent]
            )
            let start = column.minX + QuoteGeometry.indent(level: 1, step: step) + titleInset
            label.draw(at: CGPoint(x: start, y: column.minY + (firstLineHeight(column) - label.size().height) / 2))
        }
        if let isFolded {
            Self.drawSymbol(isFolded ? "chevron.right" : "chevron.down", in: chevronFrame(in: column), color: accent)
        }
        NSGraphicsContext.restoreGraphicsState()
        InlineChipPainter.paint(self, at: point, in: context, metrics: style.chip)
        super.draw(at: point, in: context)
    }

    /// An SF Symbol fitted into `rect` in `color`.
    private static func drawSymbol(_ name: String, in rect: CGRect, color: NSColor) {
        let configuration = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return }
        let size = image.size
        let scale = min(rect.width / max(size.width, 1), rect.height / max(size.height, 1), 1)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        let origin = CGPoint(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2)
        image.draw(
            in: CGRect(origin: origin, size: drawn), from: .zero, operation: .sourceOver, fraction: 1,
            respectFlipped: true, hints: nil
        )
    }
}
