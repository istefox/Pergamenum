import AppKit

/// The size grammar, the resolve/clamp arithmetic and the handle's geometry for a drawn
/// embed's resize gesture (ADR-0019: "A drawn embed is resized by dragging it, and the
/// size is written into the note"). Plan
/// `docs/superpowers/plans/2026-08-23-ridimensionamento-maniglie-embed-editor.md`, Task 2.
///
/// Pure, modelled on `EmbedNavigation`/`Tests/EmbedNavigationTests.swift`: no `NSTextView`
/// state beyond an `NSTextContainer` read for its size, no `@MainActor`, nothing that
/// needs a window to run. ADR-0019 §D3 names three callers of the one clamp this type
/// carries - `EmbedAttachment.attachmentBounds` (what is drawn, Task 3), the drag's own
/// per-frame overlay (what is shown while dragging, Tasks 5-6) and the `mouseUp` commit
/// that formats the suffix (what is written, Task 7) - so that R-05 cannot disagree with
/// itself between the picture, the overlay and the file.
///
/// **Stub bodies only.** This is the tester's batch (ADR-0155 §D1): the interface every
/// assertion in `Tests/EmbedResizeTests.swift` needs is declared here so the target keeps
/// building, but every body is `fatalError` - the coder's Task 2 work is filling each one
/// in against ADR-0019 §D1, §D3 and §D5, which already specify the arithmetic. Declaring
/// the boundary is not implementing it.
enum EmbedResize {
    /// What an embed's own run says about its size, read by `written(inRun:)` - `nil`
    /// answers "no suffix at all", never a third case (ADR-0019 §D1, §D7).
    enum Written: Equatable {
        case width(CGFloat)
        case both(CGFloat, CGFloat)
    }

    /// One step of the drag gesture (ADR-0019 §D6), each carrying the point the mouse
    /// event reports, in the text view's own coordinate space.
    enum Phase {
        case began(CGPoint)
        case moved(CGPoint)
        case ended(CGPoint)
    }

    /// ADR-0019 §D3's geometric floor on either dimension. A constant, not a design
    /// token - the company of `TranscludedRendition.padding`/`.maximumBodyHeight`, not
    /// `ThemeEngine`.
    static let minimumSide: CGFloat = 80

    /// The column a drawn embed's width is clamped against: the live container's own
    /// width minus twice its line-fragment padding (ADR-0019 §D3) - the same source
    /// `applyTransclusions` already reads from `textView.textContainer?.size.width`, read
    /// fresh on every layout pass rather than pushed in and left to go stale across a
    /// window resize.
    static func column(of textContainer: NSTextContainer?) -> CGFloat {
        fatalError("EmbedResize.column(of:) is not implemented - Task 2 declares the signature only")
    }

    /// Reads `|W` or `|WxH` off an embed's own run text (the marker substring
    /// `EditorDecorationDelegate.embedParagraph(at:storage:)` already re-reads through
    /// `stillSpellsAnEmbed`) - the wikilink spelling only. `![alt](file.est)` and a bare
    /// `![[file.est]]` both answer `nil`, and so does any suffix that is not exactly an
    /// integer width or an integer `WxH` pair with a lowercase `x` (ADR-0019 §D1, §D7).
    static func written(inRun run: String) -> Written? {
        fatalError("EmbedResize.written(inRun:) is not implemented - Task 2 declares the signature only")
    }

    /// ADR-0019 §D3's one clamp, called from every one of its three sites: no written
    /// size resolves `natural` width-clamped to `column` with height scaled
    /// proportionally; `.width` clamps to `[minimumSide, column]` with height scaled
    /// proportionally to `natural`'s own aspect ratio; `.both` clamps its width the same
    /// way and its height to `[minimumSide, .infinity)` only, the free-aspect-ratio case.
    static func resolved(written: Written?, natural: CGSize, column: CGFloat) -> CGSize {
        fatalError("EmbedResize.resolved(written:natural:column:) is not implemented - Task 2 declares the signature only")
    }

    /// The suffix `rewritten(run:to:natural:)` writes for `size`: `"W"` when its height is
    /// the proportional height for `W` (against `natural`'s aspect ratio) within a point
    /// after rounding, `"WxH"` otherwise - integers, lowercase `x`, the two forms ADR-0019
    /// §D7 verified and no third.
    static func suffix(for size: CGSize, natural: CGSize) -> String? {
        fatalError("EmbedResize.suffix(for:natural:) is not implemented - Task 2 declares the signature only")
    }

    /// `run` rewritten to carry `size`'s suffix (`suffix(for:natural:)`) in place of
    /// whatever it already has - replacing an existing suffix rather than appending a
    /// second, adding one where `run` has none. `nil` when there is nothing to write: the
    /// CommonMark spelling (ADR-0019 §D7, no sizing syntax was verified for it) or a
    /// `size` that resolves to the same suffix `run` already carries - the zero-movement
    /// case ADR-0019 §D6 sends to `selectEmbed` instead of a write.
    static func rewritten(run: String, to size: CGSize, natural: CGSize) -> String? {
        fatalError("EmbedResize.rewritten(run:to:natural:) is not implemented - Task 2 declares the signature only")
    }

    /// The 14-point square painted into the picture's own bottom-right corner, inset 3
    /// points from each edge (ADR-0019 §D5) - always inside `frame`, which is the property
    /// that keeps `frameForTextAttachment(at:)`, and therefore the click hit-test and the
    /// embed's accessibility frame, byte-identical to the geometry without a handle.
    static func handleRect(in frame: CGRect) -> CGRect {
        fatalError("EmbedResize.handleRect(in:) is not implemented - Task 2 declares the signature only")
    }

    /// The 22-point square around `handleRect(in:)` that a mouse-down has to land in to
    /// claim the drag rather than fall through to `selectEmbed` (ADR-0019 §D6) - the
    /// ordinary allowance for a small control, bigger than the paint.
    static func handleHitRect(in frame: CGRect) -> CGRect {
        fatalError("EmbedResize.handleHitRect(in:) is not implemented - Task 2 declares the signature only")
    }
}
