import AppKit

/// The `NSTextAttachment` subclass that draws a wikilink embed at its resolved size
/// (ADR-0019 "A drawn embed is resized by dragging it, and the size is written into the
/// note", §D2: "the size is applied by an `NSTextAttachment` subclass, in the two hooks
/// the SDK already calls, and by nothing else"). Plan
/// `docs/superpowers/plans/2026-08-23-ridimensionamento-maniglie-embed-editor.md`, Task 3.
///
/// **Declared here, not implemented (ADR-0155 §D1: generator/verifier separation).** This
/// is the tester's half of Task 3: the interface `Tests/EmbedDrawingTests.swift`'s new
/// sizing tests compile against and the coder's three-line change to
/// `EditorDecorationDelegate.embedParagraph(at:storage:)` constructs, so the coder is
/// judged by tests it did not write. Both overrides below are stubs that defer to `super`
/// - the SDK's own default of deriving bounds from `image.size` and drawing the image
/// unscaled - never reading `written` or `natural` at all. That is deliberate: it lets the
/// target **build** while leaving the new tests **red**, never non-compiling. Turning them
/// green - making `attachmentBounds` return
/// `EmbedResize.resolved(written:natural:column: EmbedResize.column(of: textContainer))`,
/// and `image(for:)` draw the picture at `bounds.size` with the handle composited in
/// (Task 5) and the result memoised by bounds size (Task 3's own budget line) - is the
/// coder's half of this task, not this file's.
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

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        // STUB - see the type's own header. Left at the SDK default (`super`) rather than
        // calling `EmbedResize.resolved(written:natural:column:)`, which is the coder's
        // half of Task 3.
        super.attachmentBounds(
            for: attributes, location: location, textContainer: textContainer,
            proposedLineFragment: proposedLineFragment, position: position
        )
    }

    override func image(
        for bounds: CGRect,
        attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSImage? {
        // STUB - see the type's own header. Left at the SDK default (`super`), so the
        // picture draws unscaled and carries no resize handle (Task 5) and no memoisation
        // (Task 3's own budget line) yet.
        super.image(for: bounds, attributes: attributes, location: location, textContainer: textContainer)
    }
}
