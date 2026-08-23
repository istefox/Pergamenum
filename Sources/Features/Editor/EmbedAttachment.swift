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
        // thread the image itself is drawn on" - the only state it touches is `source`,
        // a finished render `ThumbnailStore` never mutates again, drawn exactly as
        // TextKit would have drawn it itself.
        let picture = NSImage(size: size, flipped: false) { rect in
            // Task 5 composites `EmbedResize.handleRect(in:)` here, on top of this draw
            // and inside these same bounds (ADR-0019 §D5).
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        redrawn = picture
        return picture
    }
}
