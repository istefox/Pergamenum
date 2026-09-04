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
    /// The badge's own face (ADR-0030 §D1/§D5), pushed in from `EditorDecorationDelegate`'s own
    /// `badgeFont` (`textLayoutManager(_:textLayoutFragmentFor:in:)` assigns it beside
    /// `badgeColor`/`badgeBackground` above), never resolved here: this fragment has no `Theme`
    /// and, like the delegate that builds it, cannot hold one. The system-face default is what a
    /// fragment built by a test harness draws with, and the app overwrites it on every pass.
    nonisolated(unsafe) var badgeFont: NSFont = .systemFont(ofSize: 10, weight: .regular)
    /// The UTF-16 offset of the heading's own line, which is how a click on the badge says
    /// *which* section to open. The fold itself is held by index-entry ordinal, so this is
    /// translated on the way out rather than stored twice.
    nonisolated(unsafe) var headingOffset = 0

    private static let gap: CGFloat = 8
    private static let padding = NSSize(width: 6, height: 1)

    private var badge: NSAttributedString {
        NSAttributedString(
            string: "⌄ \(hiddenLines) \(hiddenLines == 1 ? "riga" : "righe")",
            attributes: [
                .font: badgeFont,
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

    /// Where the badge is, relative to a point the fragment is drawn at.
    ///
    /// One computation for the drawing and for the hit test (PG-021). Two would drift, and
    /// the way they would drift is a badge that looks right and cannot be clicked - the
    /// same shape of defect the transclusion card had a slice ago.
    func badgeFrame(at point: CGPoint) -> CGRect {
        guard hiddenLines > 0, let line = textLineFragments.first else { return .null }
        let size = badge.size()
        return CGRect(
            x: point.x + line.typographicBounds.maxX + Self.gap,
            y: point.y + line.typographicBounds.minY
                + (line.typographicBounds.height - size.height - Self.padding.height * 2) / 2,
            width: size.width + Self.padding.width * 2,
            height: size.height + Self.padding.height * 2
        )
    }

    /// The badge in the text container's coordinates, which is where a click arrives after
    /// `textContainerOrigin` has been taken off it.
    var badgeFrameInContainer: CGRect {
        badgeFrame(at: layoutFragmentFrame.origin)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        guard hiddenLines > 0 else { return }

        let text = badge
        let box = badgeFrame(at: point)
        guard !box.isNull else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        badgeBackground.setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        text.draw(at: CGPoint(x: box.minX + Self.padding.width, y: box.minY + Self.padding.height))
        NSGraphicsContext.restoreGraphicsState()
    }
}
