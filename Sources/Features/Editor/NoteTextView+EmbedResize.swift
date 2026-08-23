import AppKit

/// The hit-test entry point for a drawn embed's resize handle (ADR-0019: "A drawn embed is
/// resized by dragging it, and the size is written into the note"). Plan
/// `docs/superpowers/plans/2026-08-23-ridimensionamento-maniglie-embed-editor.md`, Task 5.
///
/// A `Coordinator` extension beside `NoteTextView+EmbedCaret.swift`, sharing its shape: the
/// coder's implementation reuses `decoration(at:in:claimedBy:)` for the fragment walk,
/// `decorations.drawnEmbedRange(atParagraphStart:in:)` as the single "is a picture actually
/// on screen right now" guard plus `guard case .drawn`, and
/// `NSTextLayoutFragment.frameForTextAttachment(at:)` + `layoutFragmentFrame` +
/// `Coordinator.inContainer(_:of:)` to bring `point` into the fragment's space - the exact
/// arithmetic `selectEmbed(at:in:)` in `NoteTextView+EmbedCaret.swift` already does, called
/// through the same helpers rather than retyped (ADR-0019 §D6).
///
/// **Declared here, not implemented (ADR-0155 D1).** This file exists so the target builds
/// while `Tests/EmbedCaretTests.swift`'s new tests are red rather than non-compiling: the
/// tester dispatch for Task 5's test sub-step owns this signature, the coder owns the body.
extension NoteTextView.Coordinator {
    /// The resize handle's hit rect (`EmbedResize.handleHitRect(in:)`) for the drawn embed
    /// under `point`, in the text view's own coordinate space - the same space
    /// `selectEmbed(at:in:)` already receives a click in. `nil` whenever there is no handle
    /// to hit: `hidesMarkup` off (R-07), no rendition landed yet for that embed, a
    /// `.missing` embed (no real picture to resize), or `point` outside every drawn embed's
    /// hit rect.
    ///
    /// STUB: always `nil`. The fragment walk that answers this for real is Task 5's paint
    /// sub-step, not this dispatch.
    func handleRect(forEmbedAt point: CGPoint, in textView: NSTextView) -> CGRect? {
        nil
    }
}
