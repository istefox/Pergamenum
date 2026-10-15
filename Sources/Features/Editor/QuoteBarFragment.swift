import AppKit

/// The layout fragment of a quoted paragraph (ADR-0087 §D7, §D8): a bar per level over the
/// fragment's full height, paragraph spacing included, so consecutive quoted lines draw one unbroken
/// bar; in a callout, its band of the card first, rounded where the card ends.
///
/// The bars stand in the paragraph's indent, left of where TextKit places the fragment: their x is
/// read in the container (the gutter, `QuoteGeometry.barOffsets`) and moved into the fragment's own
/// coordinates at drawing time.
final class QuoteBarFragment: NSTextLayoutFragment {
    nonisolated(unsafe) var level: Int = 1
    nonisolated(unsafe) var callout: (kind: CalloutKind, piece: CalloutPiece)?
    nonisolated(unsafe) var style = EditorConstructStyle()
    /// Where the paragraph's column starts in the container, and one level's step.
    nonisolated(unsafe) var gutter: CGFloat = 0
    nonisolated(unsafe) var step: CGFloat = 0

    private var column: CGRect { quoteColumn(gutter: gutter) }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.insetBy(dx: -style.chip.padding, dy: 0).union(column)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let column = column.offsetBy(dx: point.x, dy: point.y)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        if let callout {
            CalloutCard.band(callout.piece, kind: callout.kind, in: column, style: style)
        }
        for (index, offset) in QuoteGeometry.barOffsets(level: level, step: step).enumerated() {
            // The card's own bar takes the callout's colour; a quote nested in it keeps the quote's.
            let color = index == 0 ? callout.map { style.accent(of: $0.kind) } : nil
            (color ?? style.quoteBar).setFill()
            NSBezierPath(rect: CGRect(
                x: column.minX + offset, y: column.minY, width: QuoteGeometry.barWidth, height: column.height
            )).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        InlineChipPainter.paint(self, at: point, in: context, metrics: style.chip)
        super.draw(at: point, in: context)
    }
}

extension NSTextLayoutFragment {
    /// The column a quote's bars and a callout's card span, from the gutter to the paragraph's tail
    /// indent and over the fragment's full height, in the fragment's own coordinates: TextKit places
    /// the fragment at the paragraph's indent, past the bars, so the column starts left of it.
    func quoteColumn(gutter: CGFloat) -> CGRect {
        let frame = layoutFragmentFrame
        guard let container = textLayoutManager?.textContainer else { return CGRect(origin: .zero, size: frame.size) }
        let padding = container.lineFragmentPadding
        let paragraph = (textElement as? NSTextParagraph)?.attributedString
        let paragraphStyle = (paragraph?.length ?? 0) > 0
            ? paragraph?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            : nil
        let left = padding + gutter
        let right = container.size.width - padding - max(0, -(paragraphStyle?.tailIndent ?? 0))
        return CGRect(x: left - frame.minX, y: 0, width: max(0, right - left), height: frame.height)
    }
}

/// Where a body line sits in its callout's card (ADR-0087 §D8): the only line, the first, a middle
/// one or the last. The card's bottom corners round on `last` and `only`.
enum CalloutPiece: Equatable, Sendable {
    case only, first, middle, last
}

/// The card both callout fragments paint their part of (ADR-0087 §D8), ADR-0079's rail-piece shape.
enum CalloutCard {
    /// Fills one body line's band of the card, the bottom corners rounded where the card ends.
    static func band(_ piece: CalloutPiece, kind: CalloutKind, in rect: CGRect, style: EditorConstructStyle) {
        let roundsBottom = piece == .last || piece == .only
        fill(
            rect, roundingTop: false, roundingBottom: roundsBottom,
            color: style.band(of: kind), radius: style.cardRadius
        )
    }

    /// Fills `rect` with the top corners, the bottom ones, both or neither rounded.
    static func fill(_ rect: CGRect, roundingTop: Bool, roundingBottom: Bool, color: NSColor, radius: CGFloat) {
        guard rect.width > 0, rect.height > 0 else { return }
        color.setFill()
        let corner = min(radius, rect.height / 2, rect.width / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
        // A square half over each side that does not round: the rounded rect's corners there are covered.
        let squared = [roundingTop ? nil : rect.minY, roundingBottom ? nil : rect.midY].compactMap { $0 }
        for top in squared {
            path.append(NSBezierPath(rect: CGRect(x: rect.minX, y: top, width: rect.width, height: rect.height / 2)))
        }
        path.windingRule = .nonZero
        path.fill()
    }
}
