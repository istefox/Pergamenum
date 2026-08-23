import AppKit

/// The `NSTextAttachment` subclass that draws a wikilink embed at its resolved size
/// (ADR-0019 "A drawn embed is resized by dragging it, and the size is written into the
/// note", §D2: "the size is applied by an `NSTextAttachment` subclass, in the two hooks
/// the SDK already calls, and by nothing else"). Plan
/// `docs/superpowers/plans/2026-08-23-ridimensionamento-maniglie-embed-editor.md`, Task 3.
///
/// Both overrides read the `textContainer` the SDK hands them rather than a width pushed
/// in from outside - §D2's rejected `attachment.bounds` route. The column is therefore
/// whatever it is *at this layout pass*: a note saved `|900` on a wide window and reopened
/// on a narrow one draws inside its column on the first pass, not on whichever later pass
/// happens to refresh a number somebody cached.
///
/// Nothing here is stateful beyond the redraw memo. The attachment itself is rebuilt from
/// the note's own characters on every layout pass (ADR-0018 §D3), which is what makes
/// ADR-0019 §D1's "the size lives only in the text, and nothing else stores it" true
/// rather than merely intended - `written` and `natural` below are read off the run and
/// the rendition at construction and never updated afterwards, because there is never an
/// afterwards.
final class EmbedAttachment: NSTextAttachment {
    /// What this embed's own run says about its size, read by `EmbedResize.written(inRun:)`
    /// from the marker substring `embedParagraph(at:storage:)` already re-reads through
    /// `stillSpellsAnEmbed` - `nil` for an embed with no `|W`/`|WxH` suffix (ADR-0019 §D1).
    /// Set once, at construction, and never mutated afterwards: the attachment itself is
    /// rebuilt from the text on every layout pass (ADR-0018 §D3), so there is nothing to
    /// keep in sync.
    var written: EmbedResize.Written?

    /// The rendition's own size before any clamp - the resolved image's `size` for a
    /// `.drawn` rendition, or the placeholder's, for `.missing`. What
    /// `EmbedResize.resolved(written:natural:column:)` scales and clamps against, and what
    /// R-06's "no written size" case falls back to untouched but for the column clamp.
    var natural: CGSize = .zero

    /// The colour the resize handle is painted in, or nil for an embed that gets none
    /// (ADR-0019 §D5). Pushed in from `EditorDecorationDelegate.handleColor` at
    /// construction - the same one-line hand-over `FoldedHeadingFragment.badgeColor`
    /// already receives - and never read from a theme here: this type is built by an
    /// object that has no `ThemeEngine` and cannot be given one.
    ///
    /// Optional where the delegate's own property is not, and that is the whole of how a
    /// `.missing` embed keeps its old drawing: a placeholder is handed no colour, so
    /// nothing is composited over it, which matches `handleRect(forEmbedAt:in:)` refusing
    /// it at `guard case .drawn` (§D8).
    var handleColor: NSColor?

    /// The last picture `image(for:…)` built, kept so a second pass at the same bounds
    /// hands back the same object instead of allocating another. One slot rather than a
    /// dictionary keyed by size: probe 6 measured that one draw pass asks an attachment
    /// for its image exactly once (`imageQueries == 1`), so there is never a second live
    /// size to hold - the previous entry is dead weight the moment the text or the column
    /// moves, not a hit waiting to happen.
    private var redrawn: NSImage?

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        // A `.zero` origin, which is the one part of the SDK's own default this keeps:
        // `NSTextAttachment.h:40` derives its rect from `image.size` at the origin, and
        // ADR-0019 §D3's clamp answers a size, never a place. `location`,
        // `proposedLineFragment` and `position` are deliberately unread - the resolved
        // size depends on the note's own run and the live column, and on nothing about
        // where in the line this attachment happens to sit.
        CGRect(
            origin: .zero,
            size: EmbedResize.resolved(
                written: written, natural: natural, column: EmbedResize.column(of: textContainer)
            )
        )
    }

    override func image(
        for bounds: CGRect,
        attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSImage? {
        guard let source = image else { return nil }
        let size = bounds.size
        // A bounds nothing can be drawn into - zero, negative, infinite, NaN - gives the
        // source back untouched rather than an empty picture: the SDK's own default is
        // the right answer for a pass with no usable geometry, and an `NSImage` of that
        // size is not.
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1
        else { return source }
        if let redrawn, redrawn.size == size { return redrawn }

        // Block-based rather than `lockFocus`/`unlockFocus`, which `NSImage.h:294` marks
        // API_DEPRECATED naming this factory as the replacement: the handler runs when
        // the picture is actually drawn, at the destination's own resolution, which is
        // what keeps a thumbnail scaled up by the column clamp from being resampled twice.
        // `NSImage.h:117` warns the handler "may be invoked whenever and on whatever
        // thread the image itself is drawn on", so it touches exactly two things and both
        // are captured locals rather than members of `self`: `source`, a finished render
        // `ThumbnailStore` never mutates again and that TextKit would have drawn the same
        // way itself, and `handle` below, an immutable `NSColor`. The attachment itself is
        // not held by the block at all.
        let handle = handleColor
        let picture = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            if let handle { Self.drawHandle(in: rect, color: handle) }
            return true
        }
        redrawn = picture
        return picture
    }

    /// Paints ADR-0019 §D5's square into the picture's own bottom-right corner, on top of
    /// the picture and inside the same bounds - the property `frameForTextAttachment(at:)`,
    /// the click hit-test and the embed's accessibility frame all rest on, since a handle
    /// that had to grow the bounds would silently move every one of them.
    ///
    /// **The one mirror between two coordinate spaces, and the reason it is here.**
    /// `EmbedResize.handleRect(in:)` answers in the text view's own *flipped* space, where
    /// `maxY` is the bottom edge - the space `handleRect(forEmbedAt:in:)` hit-tests a click
    /// in. This drawing handler is *unflipped* (`flipped: false`, which is what puts
    /// `source` the right way up), so `maxY` is the top and the square has to be reflected
    /// across `rect`'s own middle. `EmbedResize` is not given an opinion about which way up
    /// a context is; what it keeps is the side and the inset, read from it here rather than
    /// retyped, so the painted square and the 22-point target around it cannot drift apart.
    private static func drawHandle(in rect: CGRect, color: NSColor) {
        let square = EmbedResize.handleRect(in: rect)
        let mirrored = CGRect(
            x: square.minX,
            y: rect.minY + rect.maxY - square.maxY,
            width: square.width,
            height: square.height
        )
        // A picture too small to hold its own handle gets none rather than a clipped one:
        // `EmbedResize.minimumSide` makes this unreachable through the drag, and
        // `image(for:…)` is asked for sizes the drag never chose.
        guard rect.contains(mirrored) else { return }
        color.setFill()
        // The corner radius `ResizeHandleView` already gives the Workspace's own grips -
        // a quarter of the side - so the two resize affordances in this app are the same
        // shape at two sizes rather than two shapes.
        NSBezierPath(
            roundedRect: mirrored, xRadius: mirrored.width / 4, yRadius: mirrored.height / 4
        ).fill()
    }
}
