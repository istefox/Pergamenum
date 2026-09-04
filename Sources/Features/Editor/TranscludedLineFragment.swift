import AppKit

/// A transcluded note, ready to be drawn: measured once, drawn with the same numbers.
///
/// Measurement and drawing use the *same* API on purpose. The height is bought in advance
/// with `paragraphSpacing` on the source line (measured in `TransclusionLayoutTests`), so a
/// rendition that drew taller than it measured would run over the line below it.
struct TranscludedRendition: Equatable {
    /// What the header says, and what a click opens.
    var title: String
    var reference: String
    /// The target's source with the editor's style applied - `MarkdownAttributedText` with
    /// links off, because these characters belong to a note this text view has not opened.
    var body: NSAttributedString
    /// True when the note did not fit under the cap and was cut.
    var isCut: Bool
    /// Everything the line has to reserve underneath itself: padding, header, body, and the
    /// line that offers the note when it was cut.
    var reservedHeight: CGFloat

    var ruleColor: NSColor = .separatorColor
    var captionColor: NSColor = .secondaryLabelColor

    // MARK: Geometry, shared by the measuring and the drawing

    static let gutter: CGFloat = 16
    static let ruleWidth: CGFloat = 3
    static let padding: CGFloat = 8
    /// Computed rather than stored: `NSFont` is not `Sendable`, and a static one would be
    /// shared mutable state as far as Swift 6 is concerned. The fold badge builds its own
    /// the same way, for the same reason.
    static var captionFont: NSFont { .systemFont(ofSize: 10, weight: .regular) }

    /// Past this the rendition is cut. The same cap the reading view uses, for the same
    /// reason: without it the height of one note depends on the length of another.
    static let maximumBodyHeight: CGFloat = 320

    /// The width the body is laid out in, and the offset it is drawn at.
    static func bodyWidth(inContainerOf width: CGFloat) -> CGFloat {
        max(80, width - gutter - ruleWidth - padding)
    }

    static func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        guard text.length > 0 else { return 0 }
        return ceil(text.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height)
    }

    /// The caption line's height, used for the header and for the cut notice.
    static var captionHeight: CGFloat { ceil(captionFont.ascender - captionFont.descender + 2) }
}

/// The line of a transcluded note, with the note drawn underneath it.
///
/// The source line is drawn by `super` and stays exactly what the file says - visible,
/// selectable, editable (ADR-0010 §D3). Everything this class adds happens in the space the
/// paragraph style already reserved, so no character is added to the note and nothing below
/// moves when the rendition is drawn.
///
/// The second user of the custom-fragment machinery after `FoldedHeadingFragment`, which is
/// what turns that trick into something worth having.
final class TranscludedLineFragment: NSTextLayoutFragment {
    nonisolated(unsafe) var rendition: TranscludedRendition?

    /// The text container's own width, minus the padding a line fragment hangs at on each
    /// side - the same reasoning as `HorizontalRuleFragment.ruleWidth`.
    ///
    /// **Declared by the tester** (bugfix red test, `TranscludedLineFragmentWidthTests`);
    /// `draw(at:in:)` below must read the body's layout width from this property instead of
    /// `layoutFragmentFrame.width`, which is the *source line's own text* width (the short
    /// `![[Nota]]` wikilink), not the column width - `HorizontalRuleFragment.swift:25-34`
    /// documents why that value cannot be used for anything that must span the container.
    ///
    /// TODO(coder): implement by reading `textLayoutManager?.textContainer`, mirroring
    /// `HorizontalRuleFragment.ruleWidth` exactly:
    /// `max(0, container.size.width - container.lineFragmentPadding * 2)`, falling back to
    /// `layoutFragmentFrame.width` only when there is no container to ask.
    var containerWidth: CGFloat {
        // Placeholder: intentionally still reads the wrong value so the red test in
        // TranscludedLineFragmentWidthTests.swift fails for the right reason (the bug this
        // stub exists to pin down), not because the property is missing.
        layoutFragmentFrame.width
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        guard let rendition, let line = textLineFragments.first else { return }

        let top = point.y + line.typographicBounds.maxY + TranscludedRendition.padding
        let left = point.x + TranscludedRendition.gutter
        let width = TranscludedRendition.bodyWidth(inContainerOf: layoutFragmentFrame.width)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        let bodyHeight = TranscludedRendition.height(of: rendition.body, width: width)
        let captionHeight = TranscludedRendition.captionHeight
        let ruleHeight = captionHeight + bodyHeight + (rendition.isCut ? captionHeight : 0)

        rendition.ruleColor.setFill()
        NSBezierPath(
            roundedRect: CGRect(
                x: left, y: top, width: TranscludedRendition.ruleWidth, height: max(0, ruleHeight)
            ),
            xRadius: TranscludedRendition.ruleWidth / 2,
            yRadius: TranscludedRendition.ruleWidth / 2
        ).fill()

        let textLeft = left + TranscludedRendition.ruleWidth + TranscludedRendition.padding
        caption(rendition.title, color: rendition.captionColor)
            .draw(at: CGPoint(x: textLeft, y: top))
        rendition.body.draw(
            with: CGRect(x: textLeft, y: top + captionHeight, width: width, height: bodyHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        if rendition.isCut {
            caption("… apri la nota", color: rendition.captionColor)
                .draw(at: CGPoint(x: textLeft, y: top + captionHeight + bodyHeight))
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    /// Where the drawn note is, in the text view's coordinates, so a click can find it.
    ///
    /// The whole area under the source line: the rendition is one target, not a set of
    /// them, and asking a person to hit the header exactly would be a worse gesture than
    /// none at all.
    var renditionFrame: CGRect {
        guard rendition != nil, let line = textLineFragments.first else { return .null }
        let frame = layoutFragmentFrame
        let top = frame.minY + line.typographicBounds.maxY
        return CGRect(x: frame.minX, y: top, width: frame.width, height: max(0, frame.maxY - top))
    }

    private func caption(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [.font: TranscludedRendition.captionFont, .foregroundColor: color]
        )
    }
}
