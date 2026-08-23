import AppKit
import SwiftUI

/// A drawn embed's resize handle: where it is, and the drag that starts on it (ADR-0019:
/// "A drawn embed is resized by dragging it, and the size is written into the note"). Plan
/// `docs/superpowers/plans/2026-08-23-ridimensionamento-maniglie-embed-editor.md`,
/// Tasks 5 and 6.
///
/// A `Coordinator` extension beside `NoteTextView+EmbedCaret.swift`, sharing its shape:
/// `decoration(at:in:claimedBy:)` for the fragment walk,
/// `decorations.drawnEmbedRange(atParagraphStart:in:)` as the single "is a picture actually
/// on screen right now" guard plus `guard case .drawn`, and
/// `Coordinator.drawnPictureFrame(at:in:)` + `textContainerOrigin` to bring the picture and
/// the click into one space - the exact arithmetic `selectEmbed(at:in:)` does, called
/// through the same helper rather than retyped (ADR-0019 §D6).
///
/// **Nothing here decides where the handle *is*, or how big the picture may become.**
/// `EmbedResize.handleRect(in:)`/`handleHitRect(in:)` own the handle's geometry and
/// `EmbedResize.resolved(written:natural:column:)` owns the clamp, all three unit-tested
/// without a window; this file's whole job is finding the picture's frame, deciding whether
/// a point grabbed it, and keeping the overlay in step for as long as the gesture lasts.
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
        guard let grabbed = grabbedEmbed(at: point, in: textView) else { return nil }
        return EmbedResize.handleRect(in: grabbed.picture)
    }

    /// A drawn embed whose handle `point` landed on, with everything a drag needs to
    /// start: the run in the note's own characters, the picture's frame in the text
    /// view's own coordinate space, and the rendition's natural size.
    ///
    /// The single fragment walk this file makes. `handleRect(forEmbedAt:in:)` asks for a
    /// rect and `beginResize(at:in:)` asks for a gesture, and both are the same question -
    /// *which picture, if any, does this point grab?* - so answering it twice is how the
    /// handle drawn at one corner and the drag started from another would come about.
    private func grabbedEmbed(at point: CGPoint, in textView: NSTextView) -> GrabbedEmbed? {
        guard decorations.hidesMarkup,
              let manager = textView.textLayoutManager, let content = manager.textContentManager
        else { return nil }
        let text = textView.string as NSString
        let origin = textView.textContainerOrigin
        var grabbed: GrabbedEmbed?
        _ = decoration(at: point, in: textView) { (fragment: NSTextLayoutFragment) in
            let paragraphStart = content.offset(
                from: content.documentRange.location, to: fragment.rangeInElement.location
            )
            // `drawnEmbedRange` answers for a `.missing` embed too - it asks whether
            // *something* is drawn at this offset, and a placeholder is. The rendition is
            // what tells a picture from a placeholder, which is ADR-0019 §D8's one line on
            // top of the range lookup rather than a second copy of the lookup's own checks.
            guard case .drawn(let image) = embeds.renditions[paragraphStart],
                  let run = decorations.drawnEmbedRange(atParagraphStart: paragraphStart, in: text),
                  let attachmentLocation = content.location(
                      content.documentRange.location, offsetBy: run.location
                  ),
                  let picture = Self.drawnPictureFrame(at: attachmentLocation, in: fragment)
            else { return false }
            // Out of the container's space and into the view's, once and here, rather than
            // `inContainer(_:of:)` bringing the click the other way: everything downstream
            // of this walk - the hit test on the next line, the rect answered to a caller,
            // the overlay's own frame as a subview - lives in the view's space, and one
            // conversion at the boundary is what stops the two from being mixed.
            let frame = picture.offsetBy(dx: origin.x, dy: origin.y)
            guard EmbedResize.handleHitRect(in: frame).contains(point) else { return false }
            grabbed = GrabbedEmbed(run: run, picture: frame, natural: image.size)
            return true
        }
        return grabbed
    }

    /// What the walk above found: the answer to "which picture does this point grab", in
    /// the one space a click, a subview and this file's callers all already work in.
    private struct GrabbedEmbed {
        var run: NSRange
        var picture: CGRect
        var natural: CGSize
    }

    /// The drag itself (ADR-0019 §D6-§D7). Plan
    /// `docs/superpowers/plans/2026-08-23-ridimensionamento-maniglie-embed-editor.md`, Task 6:
    /// `.began` claims a point only inside `EmbedResize.handleHitRect(in:)` for some drawn
    /// embed's picture - the coexistence rule with `selectEmbed(at:in:)`/`onClickInMargin`,
    /// ADR-0019 §D6 - `.moved` rewrites the pending overlay's frame through
    /// `EmbedResize.resolved(written:natural:column:)`'s own clamp, and `.ended` takes the
    /// overlay away.
    ///
    /// Three overrides on `CompletingTextView` forward here and nothing else does, so the
    /// whole gesture is one method a test calls three times - which is the trade ADR-0019
    /// §D6 made deliberately against an `NSWindow.trackEvents` loop it could not have
    /// driven from the unit suite at all.
    ///
    /// **False is not a failure.** It is what leaves the event to whoever is next:
    /// `onClickInMargin` for a press anywhere on the picture but its corner, and `super`
    /// for the ordinary selection drag every `mouseDragged` outside a gesture still is.
    func resizeEmbed(_ phase: EmbedResize.Phase, in textView: NSTextView) -> Bool {
        switch phase {
        case .began(let point): beginResize(at: point, in: textView)
        case .moved(let point): continueResize(to: point, in: textView)
        case .ended: endResize()
        }
    }

    /// Claims the press, or declines it for `selectEmbed(at:in:)` to answer next.
    private func beginResize(at point: CGPoint, in textView: NSTextView) -> Bool {
        // Whatever was still open is over. A gesture whose `mouseUp` never arrived - the
        // pointer left the window, the app was switched away mid-drag, both named in
        // ADR-0019's Consequences as the class of defect this codebase's first drag brings
        // with it - would otherwise leave its rectangle painted over the note for good,
        // and the next press is the one event certain to follow it.
        _ = endResize()
        guard let grabbed = grabbedEmbed(at: point, in: textView) else { return false }
        let overlay = EmbedResizeOverlay(
            frame: grabbed.picture, style: Self.overlayStyle(theme: parent.theme)
        )
        textView.addSubview(overlay)
        embedDrag = EmbedDrag(
            run: grabbed.run,
            picture: grabbed.picture,
            natural: grabbed.natural,
            grab: point,
            size: grabbed.picture.size,
            overlay: overlay
        )
        return true
    }

    /// Moves the pending rectangle, and nothing else: not one character of the note is
    /// written between here and `.ended` (**R-02**).
    private func continueResize(to point: CGPoint, in textView: NSTextView) -> Bool {
        guard var drag = embedDrag else { return false }
        // The delta from where the handle was *grabbed*, never the pointer's own distance
        // from the picture's corner: a press that landed six points inside the 22-point
        // target would otherwise jump the rectangle by six points before it had moved.
        let requested = CGSize(
            width: drag.picture.width + point.x - drag.grab.x,
            height: drag.picture.height + point.y - drag.grab.y
        )
        // R-05, clamped here and not only at the commit - ADR-0019 §D3's second of three
        // call sites, and the reason it names three: a rectangle that followed the pointer
        // past the margin and snapped back at release is a different gesture from one that
        // stops at the margin. `.both` rather than `.width`, because SPEC's scope has the
        // two dimensions move independently, so the height asked for is the height shown.
        let size = EmbedResize.resolved(
            written: .both(requested.width, requested.height),
            natural: drag.natural,
            column: EmbedResize.column(of: textView.textContainer)
        )
        drag.size = size
        drag.overlay.frame = CGRect(origin: drag.picture.origin, size: size)
        embedDrag = drag
        return true
    }

    /// Takes the rectangle away and forgets the gesture, answering false when there was
    /// none in flight - which is what leaves an ordinary selection's own `mouseUp` to
    /// `super` (§D6).
    ///
    /// **Task 6 stops here.** Resolving the final size into the note's own characters is
    /// Task 7's single `replaceAtomically(_:with:in:)` (§D7), and it is why `EmbedDrag`
    /// carries a `run` and a `size` that nothing reads yet: they are what that one edit
    /// will be computed from, captured at the only moments they can be.
    private func endResize() -> Bool {
        guard let drag = embedDrag else { return false }
        drag.overlay.removeFromSuperview()
        embedDrag = nil
        return true
    }

    /// The overlay's colours and face, from the theme the view was built with - ADR-0019
    /// §D7's "pushed in from the theme at creation", the same hand-over
    /// `TranscludedRendition` gets its `ruleColor`/`captionColor` through.
    private static func overlayStyle(theme: Theme) -> EmbedResizeOverlay.Style {
        EmbedResizeOverlay.Style(
            border: NSColor(theme.color(.accentPrimary)),
            label: NSColor(theme.color(.textInverted)),
            labelBackground: NSColor(theme.color(.accentPrimary)),
            font: theme.nsFont(.caption),
            cornerRadius: theme.radius(.control)
        )
    }

    /// One drag, from the press inside a handle to the release that ends it: everything
    /// `.moved` and `.ended` need that a mouse event does not carry (ADR-0019 §D6, "the
    /// state lives on the Coordinator" - the text view stays the dumb forwarder every
    /// other decoration already treats it as).
    ///
    /// Held by `Coordinator.embedDrag`, which is nil exactly when no drag is in flight and
    /// is rebuilt from scratch by the next `.began`. Nothing here outlives a gesture, for
    /// the reason ADR-0018 §D3 gives about the attachment and §D1 repeats about the size:
    /// state that describes a picture and can disagree with the note is state nothing
    /// downstream would notice going wrong.
    struct EmbedDrag {
        /// The embed's own run in the note's characters - the range Task 7's `.ended` will
        /// replace. Captured at `.began` and safe to keep for the length of the gesture
        /// precisely because R-02 writes nothing while it lasts, so no offset moves.
        var run: NSRange
        /// The picture as it was drawn when the drag began, in the text view's own
        /// coordinate space: the overlay's origin, and the size every `.moved` adds its
        /// delta to.
        var picture: CGRect
        /// The rendition's own size, for `EmbedResize`'s aspect ratio - what tells `|W`
        /// from `|WxH` when Task 7 formats the suffix.
        var natural: CGSize
        /// Where the press landed, so the rectangle follows the pointer rather than
        /// jumping to it.
        var grab: CGPoint
        /// The clamped size the last `.moved` resolved, which is what Task 7 writes.
        var size: CGSize
        /// The rectangle on screen. Held here rather than found again by position in
        /// `textView.subviews`: a text view's subviews are not this file's to count.
        var overlay: EmbedResizeOverlay
    }
}
