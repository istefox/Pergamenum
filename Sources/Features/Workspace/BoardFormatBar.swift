import SwiftUI

/// Where `CardFormatBar` is drawn over the board, and on which side of the selection it sits
/// (ADR-0027 §D5, plan `2026-08-28-unificare-nota-e-testo-in-un-solo-strume` Task 6, R-03/R-05).
///
/// Board point = the card's own board origin (`node.x`, `node.y`) plus the *view-local*
/// selection frame `FormattingTextView.selectionFrameInView()` already reports (Tasks 4/5) -
/// never a screen coordinate. `BoardFormatBar` below then draws at `p * zoom + pan`, exactly the
/// transform `BoardMarquee` and `BoardGuides` already use and document twice
/// (`BoardOverlays.swift:16-19`, `:44`), so the pill lands on the selection at any zoom and any
/// pan without measuring whether AppKit's own coordinate conversion happens to walk SwiftUI's
/// `scaleEffect` - the exact thing ADR §D5 rejected `FormatBarPanel` (alternative A4) for not
/// being able to promise.
///
/// Free static functions over a controller method, matching `BoardGeometry`'s own shape
/// (`BoardGeometry.swift:10`) rather than `WorkspaceController`'s: every rule here is checked
/// directly, with no window and no gesture, which is the whole point of Task 6's split between
/// tester and coder.
enum BoardFormatBarGeometry {
    /// One placement answer: where the pill's origin sits, in the same container-relative
    /// coordinate space `BoardMarquee`/`BoardGuides` already draw in, and which side of the
    /// selection it sits on.
    ///
    /// `origin` deliberately carries no size: the pill's own dimensions are `pillSize` below, a
    /// constant with no `zoom` parameter at all, so nothing about them can vary with zoom by
    /// construction - the SPEC's "the pill's own size does not scale with zoom" requirement,
    /// held at the type level rather than by a runtime check.
    struct Placement: Equatable, Sendable {
        var origin: CGPoint
        var flipsBelow: Bool
    }

    /// The pill's own on-screen size, in the same screen-point space `BoardGeometry`'s own
    /// `handleScreenSize`/`handleTargetScreenSize` are measured in (`BoardGeometry.swift:43-46`)
    /// - a resize handle would shrink to nothing at 25% zoom if it were sized in board units,
    /// and a selection bar that shrank with it would be unreadable at the same zoom for the
    /// same reason. Whoever draws `CardFormatBar` applies this size with no `.scaleEffect` of
    /// its own.
    static let pillSize = CGSize(width: 208, height: 30)

    /// Clearance kept between the pill and the selection it points at, in the same
    /// zoom-invariant space `pillSize` is measured in.
    static let gap: CGFloat = 8

    /// The board-space (converted to the board-container-relative screen space `BoardMarquee`
    /// draws in) placement for the pill, and whether it must sit below the selection instead of
    /// above it.
    ///
    /// **Strategy: flip below, never clamp** (plan Task 6, "pick one and document it, and assert
    /// it"). A clamp would slide the pill sideways or downward away from the point it is meant
    /// to indicate - the pill would still be on screen, pointing at the wrong text, which is a
    /// worse failure than picking the other side of the same selection. Flipping keeps the pill
    /// anchored to what it labels; only the side changes.
    ///
    /// "No room above" is read against the same container-relative space the transformed point
    /// already lives in, whose top edge is `y = 0` regardless of `viewport`'s own value (the
    /// space `BoardContentLayer` sizes to `viewport` and `BoardMarquee`/`BoardGuides` draw
    /// into without ever seeing `viewport` themselves): if placing the pill's bottom edge `gap`
    /// points above the transformed selection origin would put the pill's top edge above that
    /// `y = 0` line, there is no room, and the pill flips to sit `gap` points below the
    /// selection instead. `viewport` is threaded through the signature for the same reason
    /// `BoardGeometry.visibleRect(viewport:pan:zoom:)` takes it (`BoardGeometry.swift:237`) -
    /// so a future horizontal clamp (the pill running off the right edge of a narrow window) has
    /// what it needs without another signature change, even though R-03/R-05 do not ask for one
    /// yet.
    ///
    /// - Parameters:
    ///   - selectionFrame: the current selection's rectangle in the card's own text view
    ///     coordinates, from `FormattingTextView.selectionFrameInView()`.
    ///   - cardOrigin: the card's board position, `(node.x, node.y)`.
    ///   - zoom: `workspace.zoom`.
    ///   - pan: `workspace.pan`.
    ///   - viewport: the board's current viewport size (`WorkspaceView`'s own `viewportSize`).
    static func placement(
        selectionFrame: CGRect,
        cardOrigin: CGPoint,
        zoom: CGFloat,
        pan: CGSize,
        viewport: CGSize
    ) -> Placement {
        fatalError("not implemented")
    }

    /// True only while the card named `forNodeID` is the one currently being edited **and** the
    /// selection inside it is non-empty.
    ///
    /// Mirrors the rule `refreshFormatBar` already applies for the note editor's own bar
    /// (`CompletingTextView+FormatBar.swift:14-19`, `selection.length > 0`), restated here
    /// rather than reused because that file lives under `Sources/Features/Editor/`, outside
    /// this chain's edits (ADR §D6/§D9). A bare caret is plain caret movement, not something to
    /// format - the SPEC's own edge case - so it hides the bar rather than showing an empty one.
    static func shouldShowFormatBar(
        editingTextNodeID: String?,
        forNodeID: String,
        selectionRange: NSRange
    ) -> Bool {
        fatalError("not implemented")
    }
}

/// The SwiftUI sibling that actually draws `CardFormatBar` over the board (ADR §D5), positioned
/// by `BoardFormatBarGeometry` above.
///
/// **Not wired into `BoardContentLayer.swift` or `WorkspaceView.swift` by this task** - plan
/// Task 6 is explicit that the live placement (where in the view tree this sits, what feeds it
/// `selectionFrame` and `viewport` on every selection change) is the coder's job in the next
/// dispatch. Declared here as scaffolding only, following `BoardMarquee`/`BoardGuides`
/// (`BoardOverlays.swift`) as a SwiftUI sibling drawn **outside** `WorkspaceView`'s
/// `.scaleEffect(workspace.zoom, anchor: .topLeading)` (`WorkspaceView.swift:354`), never inside
/// it - a view inside that scale would shrink the pill exactly as ADR §D5 says a screen-space
/// `NSPanel` might.
struct BoardFormatBar: View {
    let workspace: WorkspaceController
    let node: CanvasNode
    let selectionFrame: CGRect
    let viewport: CGSize
    let isInlineApplied: (InlineFormat) -> Bool
    let isLineApplied: (LineFormat) -> Bool
    let onToggleInline: (InlineFormat) -> Void
    let onToggleLine: (LineFormat) -> Void

    var body: some View {
        let placement = BoardFormatBarGeometry.placement(
            selectionFrame: selectionFrame,
            cardOrigin: CGPoint(x: node.x, y: node.y),
            zoom: workspace.zoom,
            pan: workspace.pan,
            viewport: viewport
        )
        let size = BoardFormatBarGeometry.pillSize
        CardFormatBar(
            isInlineApplied: isInlineApplied,
            isLineApplied: isLineApplied,
            onToggleInline: onToggleInline,
            onToggleLine: onToggleLine
        )
        .frame(width: size.width, height: size.height)
        .position(
            x: placement.origin.x + size.width / 2,
            y: placement.flipsBelow
                ? placement.origin.y + size.height / 2 + BoardFormatBarGeometry.gap
                : placement.origin.y - size.height / 2 - BoardFormatBarGeometry.gap
        )
    }
}
