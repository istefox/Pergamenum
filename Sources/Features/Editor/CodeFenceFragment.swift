import AppKit

/// The layout fragment of a closed fence's opening or closing line (ADR-0087 §D6). The line's own
/// characters are collapsed by the generic path and its line break keeps the row's height, the
/// `HorizontalRuleFragment` shape: the header row draws the language badge and «N righe», the closing
/// row a quiet rule.
final class CodeFenceFragment: NSTextLayoutFragment {
    enum Role: Equatable {
        case header(language: String?, lineCount: Int)
        case closing
    }

    nonisolated(unsafe) var role: Role = .closing
    nonisolated(unsafe) var style = EditorConstructStyle()

    private static let gap: CGFloat = 8
    private static let thickness: CGFloat = 1

    /// The column the closing rule spans, read at drawing time as `HorizontalRuleFragment` reads it.
    private var columnWidth: CGFloat {
        guard let container = textLayoutManager?.textContainer else { return layoutFragmentFrame.width }
        let paragraph = (textElement as? NSTextParagraph)?.attributedString
        let paragraphStyle = (paragraph?.length ?? 0) > 0
            ? paragraph?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            : nil
        return EditorGutter.columnSpan(
            containerWidth: container.size.width, padding: container.lineFragmentPadding, style: paragraphStyle
        ).width
    }

    private var badge: NSAttributedString? {
        guard case .header(let language?, _) = role else { return nil }
        return NSAttributedString(
            string: language, attributes: [.font: style.badgeFont, .foregroundColor: style.badgeText]
        )
    }

    private var count: NSAttributedString? {
        guard case .header(_, let lineCount) = role else { return nil }
        return NSAttributedString(
            string: FenceChrome.lineCountLabel(lineCount),
            attributes: [.font: style.badgeFont, .foregroundColor: style.lineCountColor]
        )
    }

    override var renderingSurfaceBounds: CGRect {
        let base = super.renderingSurfaceBounds
        return CGRect(x: base.minX, y: base.minY, width: max(base.width, columnWidth), height: base.height)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        let height = layoutFragmentFrame.height
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard case .header = role else {
            let width = columnWidth
            guard width > 0 else { return }
            style.hairline.setFill()
            NSBezierPath(rect: CGRect(
                x: point.x, y: point.y + (height - Self.thickness) / 2, width: width, height: Self.thickness
            )).fill()
            return
        }

        var x = point.x
        if let badge {
            let size = badge.size()
            let padding = style.chip.padding
            let box = CGRect(
                x: x, y: point.y + (height - size.height) / 2 - 1,
                width: size.width + 2 * padding, height: size.height + 2
            )
            let radius = min(style.chip.radius, box.height / 2)
            style.badgeBackground.setFill()
            NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).fill()
            badge.draw(at: CGPoint(x: box.minX + padding, y: box.minY + 1))
            x = box.maxX + Self.gap
        }
        if let count {
            let size = count.size()
            count.draw(at: CGPoint(x: x, y: point.y + (height - size.height) / 2))
        }
    }
}
