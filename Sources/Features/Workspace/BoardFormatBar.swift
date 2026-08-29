import AppKit
import Observation
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
        // `p * zoom + pan`, the board's own documented transform (`BoardOverlays.swift:16-19`).
        // `p` is the board point the selection begins at: the card's own origin plus the
        // view-local rectangle its text view reported, never a screen coordinate (ADR §D5).
        let origin = CGPoint(
            x: (cardOrigin.x + selectionFrame.origin.x) * zoom + pan.width,
            y: (cardOrigin.y + selectionFrame.origin.y) * zoom + pan.height
        )
        // Flip below, never clamp - the strategy this file's own doc comment above commits to.
        // The pill drawn above the selection needs its whole height plus `gap` of clearance;
        // with less than that it would be drawn past the container's top edge, so it takes the
        // other side of the same selection instead of sliding away from it.
        //
        // `viewport` is deliberately not read here: the top edge of the space `origin` already
        // lives in is `y = 0` whatever the viewport measures, exactly as `BoardMarquee` and
        // `BoardGuides` draw into that space without ever seeing a viewport. The parameter is
        // threaded for the horizontal clamp the doc comment above names as a future need.
        let flipsBelow = origin.y - gap - pillSize.height < 0
        return Placement(origin: origin, flipsBelow: flipsBelow)
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
        editingTextNodeID == forNodeID && selectionRange.length > 0
    }
}

/// The live selection inside the `.text` card being written into - the one thing
/// `BoardFormatBar` needs that only an `NSTextView` knows.
///
/// A small holder rather than three more properties on `WorkspaceController`, for a reason the
/// controller states about itself: it imports CoreGraphics, Foundation and Observation and
/// nothing else, so putting a reference to a live `NSTextView` on it would hang a view off the
/// object every non-view part of the Workspace reads. It is stored there as one `let`, beside
/// `editingTextNodeID`/`editingTextDraft`, on those two properties' own argument
/// (`WorkspaceController.swift:482-485`): one value three views share beats three copies.
///
/// The reference back to the text view is **weak**. A card's text view is deallocated every
/// time the card crosses `BoardContentLayer.visibleNodes`' culling rect (the reason
/// `CardTextView.dismantleNSView` exists at all), and a strong reference here would keep the
/// text view of a card nobody can see alive on the controller.
@MainActor
@Observable
final class CardTextSelection {
    /// The card the values below were read from, `nil` until some card has published one.
    ///
    /// Compared against `WorkspaceController.editingTextNodeID` rather than trusted: a card
    /// that stops being edited never clears this, and that mismatch is exactly what
    /// `BoardFormatBarGeometry.shouldShowFormatBar` reads to hide the bar. Nothing has to
    /// remember to tidy up, which is the same reason `endTextEdit` clears one variable rather
    /// than telling every view about it.
    private(set) var nodeID: String?
    /// The selection's rectangle in the card's own text view coordinates, `.zero` when there is
    /// no selection to point at.
    private(set) var frame: CGRect = .zero
    /// The selection itself, read by `shouldShowFormatBar` for its `length > 0` rule.
    private(set) var range = NSRange(location: 0, length: 0)

    /// `@ObservationIgnored` because a `weak` reference is not something a view observes: every
    /// change worth redrawing for already lands on `frame` and `range` above, published in the
    /// same call. Same shape as `WorkspaceController`'s own `weak var vault`.
    @ObservationIgnored private(set) weak var textView: FormattingTextView?

    /// Reads the current selection out of the card's text view.
    ///
    /// Called from that view's own delegate callbacks - selection changed, text changed - and
    /// never from inside a SwiftUI update pass, which would be a state mutation during view
    /// update.
    func update(nodeID: String, from textView: FormattingTextView) {
        self.nodeID = nodeID
        self.textView = textView
        range = textView.selectedRange()
        frame = textView.selectionFrameInView() ?? .zero
    }

    /// Whether `format` is already applied over the live selection - read straight from the text
    /// view rather than from a copy of its string, so the answer cannot lag a keystroke behind
    /// what the person is looking at.
    func isApplied(_ format: InlineFormat) -> Bool {
        guard let textView else { return false }
        return InlineFormat.isApplied(format, in: textView.string, over: textView.selectedRange())
    }

    /// The `LineFormat` half of `isApplied(_:)` above, on the lines the selection touches.
    func isApplied(_ format: LineFormat) -> Bool {
        guard let textView else { return false }
        return LineFormat.isApplied(format, in: textView.string, over: textView.selectedRange())
    }

    /// Toggles `format` on the live text view, which is what keeps a bar press and a Cmd+B
    /// press one and the same edit - one undo step, through `FormattingTextView`'s own single
    /// edit path. A card whose text view has gone (culled, or editing already over) formats
    /// nothing rather than reaching for a value that is no longer there.
    func toggle(_ format: InlineFormat) { textView?.toggleInlineFormat(format) }

    /// The `LineFormat` half of `toggle(_:)` above.
    func toggle(_ format: LineFormat) { textView?.toggleLineFormat(format) }
}

/// The SwiftUI sibling that actually draws `CardFormatBar` over the board (ADR §D5), positioned
/// by `BoardFormatBarGeometry` above.
///
/// Drawn by `BoardFormatBarLayer` (`BoardOverlays.swift`), which is where the decision about
/// *whether* there is a bar at all lives; this view is only the pill and its position. The layer
/// is a sibling of `BoardGuides`/`BoardMarquee` in `WorkspaceView`'s own board `ZStack`
/// (`WorkspaceView.swift:357-359`), **outside** `.scaleEffect(workspace.zoom, anchor: .topLeading)`
/// (`WorkspaceView.swift:354`) and never inside it - a view inside that scale would shrink the
/// pill exactly as ADR §D5 says a screen-space `NSPanel` might.
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
            // `placement.origin` is the *top* of the selection, so the flipped side has to
            // clear the selection's own drawn height before the gap starts - at zoom, since
            // that height is a board measurement while the pill and the gap are screen ones.
            // Above, there is nothing to clear: the pill's bottom edge is `gap` above that
            // same point.
            y: placement.flipsBelow
                ? placement.origin.y + selectionFrame.height * workspace.zoom
                    + BoardFormatBarGeometry.gap + size.height / 2
                : placement.origin.y - size.height / 2 - BoardFormatBarGeometry.gap
        )
    }
}
