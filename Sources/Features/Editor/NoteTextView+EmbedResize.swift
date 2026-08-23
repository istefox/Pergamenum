import AppKit

/// The hit-test entry point for a drawn embed's resize handle (ADR-0019: "A drawn embed is
/// resized by dragging it, and the size is written into the note"). Plan
/// `docs/superpowers/plans/2026-08-23-ridimensionamento-maniglie-embed-editor.md`, Task 5.
///
/// A `Coordinator` extension beside `NoteTextView+EmbedCaret.swift`, sharing its shape:
/// `decoration(at:in:claimedBy:)` for the fragment walk,
/// `decorations.drawnEmbedRange(atParagraphStart:in:)` as the single "is a picture actually
/// on screen right now" guard plus `guard case .drawn`, and
/// `Coordinator.drawnPictureFrame(at:in:)` + `Coordinator.inContainer(_:of:)` to bring the
/// picture and the click into one space - the exact arithmetic `selectEmbed(at:in:)` does,
/// called through the same two helpers rather than retyped (ADR-0019 §D6).
///
/// **Nothing here decides where the handle *is*.** `EmbedResize.handleRect(in:)` and
/// `EmbedResize.handleHitRect(in:)` own that geometry and are unit-tested without a window;
/// this file's whole job is finding the picture's frame and handing it over.
extension NoteTextView.Coordinator {
    /// Where the resize handle is painted (`EmbedResize.handleRect(in:)`) for the drawn
    /// embed whose handle `point` lands on, in the text view's own coordinate space - the
    /// same space `selectEmbed(at:in:)` already receives a click in.
    ///
    /// **The target is bigger than the paint, and the two are not the same rect.** `point`
    /// is tested against `EmbedResize.handleHitRect(in:)`, the 22-point square ADR-0019 §D6
    /// puts around the 14-point handle so that a small control can be aimed at; what comes
    /// back is the 14-point square itself, which §D5 keeps strictly inside the picture.
    /// A caller therefore gets a rect it can draw, measure or grab from without having to
    /// know that the target reaches a point past the picture's own corner.
    ///
    /// `nil` whenever there is no handle to hit, and each of the four cases falls out of a
    /// guard that already exists somewhere else rather than a rule invented here:
    /// `hidesMarkup` off (R-07) and a render still in flight both make
    /// `drawnEmbedRange(atParagraphStart:in:)` itself answer nil; a `.missing` embed is a
    /// placeholder rather than a picture, and is refused by `guard case .drawn` before any
    /// geometry is computed; and a `point` outside every drawn embed's hit rect simply
    /// claims no fragment.
    func handleRect(forEmbedAt point: CGPoint, in textView: NSTextView) -> CGRect? {
        guard decorations.hidesMarkup,
              let manager = textView.textLayoutManager, let content = manager.textContentManager
        else { return nil }
        let text = textView.string as NSString
        var handle: CGRect?
        _ = decoration(at: point, in: textView) { (fragment: NSTextLayoutFragment) in
            let paragraphStart = content.offset(
                from: content.documentRange.location, to: fragment.rangeInElement.location
            )
            // `drawnEmbedRange` answers for a `.missing` embed too - it asks whether
            // *something* is drawn at this offset, and a placeholder is. The rendition is
            // what tells a picture from a placeholder, which is ADR-0019 §D8's one line on
            // top of the range lookup rather than a second copy of the lookup's own checks.
            guard case .drawn = embeds.renditions[paragraphStart],
                  let run = decorations.drawnEmbedRange(atParagraphStart: paragraphStart, in: text),
                  let attachmentLocation = content.location(
                      content.documentRange.location, offsetBy: run.location
                  ),
                  let picture = Self.drawnPictureFrame(at: attachmentLocation, in: fragment),
                  EmbedResize.handleHitRect(in: picture).contains(Self.inContainer(point, of: textView))
            else { return false }
            // Back out of the container's space into the view's, the one conversion
            // `inContainer(_:of:)` above just made in the other direction: this rect is
            // answered to a caller holding view coordinates, never to the layout.
            let origin = textView.textContainerOrigin
            handle = EmbedResize.handleRect(in: picture).offsetBy(dx: origin.x, dy: origin.y)
            return true
        }
        return handle
    }
}
