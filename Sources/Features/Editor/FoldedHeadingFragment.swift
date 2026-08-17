import AppKit

/// A heading whose section is folded, drawn with a badge saying how much is hidden.
///
/// The badge cannot be text. The note's characters are the file's characters and a folded
/// section may not add any (principle 1, and the promise at the top of `MarkdownStyler`),
/// so the only place a count can exist is in the drawing. That is what a custom layout
/// fragment is for: it draws its own line and then whatever else it wants inside its
/// rendering surface.
///
/// Chosen over a tinted background alone because a folded section is otherwise
/// indistinguishable from a section with nothing under it, and that reads as lost text.
final class FoldedHeadingFragment: NSTextLayoutFragment {
    /// How many lines are hidden under this heading. Drawn as written: the point of the
    /// badge is that the number is the thing you cannot infer from the screen.
    nonisolated(unsafe) var hiddenLines = 0
    nonisolated(unsafe) var badgeColor: NSColor = .secondaryLabelColor
    nonisolated(unsafe) var badgeBackground: NSColor = .quaternaryLabelColor

    private static let gap: CGFloat = 8
    private static let padding = NSSize(width: 6, height: 1)

    private var badge: NSAttributedString {
        NSAttributedString(
            string: "⌄ \(hiddenLines) \(hiddenLines == 1 ? "riga" : "righe")",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: badgeColor,
            ]
        )
    }

    /// Wide enough for the badge, or the drawing is clipped at the line's own width.
    ///
    /// The header is explicit that this "should be larger than layoutFragmentFrame.size",
    /// which is exactly what a decoration drawn past the end of the text needs.
    override var renderingSurfaceBounds: CGRect {
        let base = super.renderingSurfaceBounds
        let extra = badge.size().width + Self.gap + Self.padding.width * 2
        return CGRect(
            x: base.minX,
            y: base.minY,
            width: base.width + extra,
            height: base.height
        )
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        guard hiddenLines > 0, let line = textLineFragments.first else { return }

        let text = badge
        let size = text.size()
        let origin = CGPoint(
            x: point.x + line.typographicBounds.maxX + Self.gap,
            y: point.y + line.typographicBounds.minY
                + (line.typographicBounds.height - size.height - Self.padding.height * 2) / 2
        )
        let box = CGRect(
            origin: origin,
            size: CGSize(
                width: size.width + Self.padding.width * 2,
                height: size.height + Self.padding.height * 2
            )
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        badgeBackground.setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        text.draw(at: CGPoint(x: box.minX + Self.padding.width, y: box.minY + Self.padding.height))
        NSGraphicsContext.restoreGraphicsState()
    }
}
