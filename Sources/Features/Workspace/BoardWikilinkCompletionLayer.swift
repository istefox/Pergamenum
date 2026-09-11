import AppKit
import Observation
import SwiftUI

/// Where the `[[` completion popup is drawn over the board (point 1 of the workspace
/// wikilink regression chain), mirroring `BoardFormatBarGeometry`'s own `p * zoom + pan`
/// placement and "flip below, never clamp" strategy: that file's own header explains why a
/// screen-space `NSPanel` (the note editor's `CompletionPanel`) cannot be trusted to track a
/// card's position under the board's `.scaleEffect`/`pan`, and the same reasoning applies to
/// this popup.
///
/// Free static functions over a controller method, matching `BoardFormatBarGeometry`'s own
/// shape rather than `WorkspaceController`'s - every rule here is checked directly, with no
/// window and no gesture.
enum BoardWikilinkCompletionGeometry {
    struct Placement: Equatable, Sendable {
        var origin: CGPoint
        var flipsBelow: Bool
    }

    /// The popup's own on-screen size, in the same zoom-invariant screen-point space
    /// `BoardFormatBarGeometry.pillSize` is measured in - a completion list that shrank with
    /// zoom would be unreadable at low zoom for the same reason a shrinking format bar would.
    static let rowHeight: CGFloat = 28
    static let width: CGFloat = 240
    static let gap: CGFloat = 4

    static func size(forRowCount count: Int) -> CGSize {
        CGSize(width: width, height: CGFloat(count) * rowHeight)
    }

    /// **Strategy: flip below, never clamp** - `BoardFormatBarGeometry`'s own house style,
    /// restated here rather than reused: that file's `placement(...)` is shaped around a
    /// selection rectangle and this one around a caret point, and pulling the shared half out
    /// into a third function would cost a signature neither call site needs for one `if`.
    static func placement(
        caretFrame: CGRect,
        cardOrigin: CGPoint,
        rowCount: Int,
        zoom: CGFloat,
        pan: CGSize,
        viewport: CGSize
    ) -> Placement {
        // `p * zoom + pan`, the board's own documented transform (`BoardOverlays.swift:16-19`).
        let origin = CGPoint(
            x: (cardOrigin.x + caretFrame.origin.x) * zoom + pan.width,
            y: (cardOrigin.y + caretFrame.origin.y) * zoom + pan.height
        )
        let height = size(forRowCount: rowCount).height
        // `viewport` is threaded through for the same reason `BoardFormatBarGeometry` takes
        // it: a future horizontal clamp has what it needs without another signature change,
        // even though nothing drawn today reads it.
        let flipsBelow = origin.y - gap - height < 0
        return Placement(origin: origin, flipsBelow: flipsBelow)
    }
}

/// The `.text` card's live `[[` completion popup state - the one thing the board's overlay
/// needs that only an `NSTextView` knows, mirroring `CardTextSelection`'s own shape exactly
/// (`BoardFormatBar.swift`).
///
/// A separate holder from `CardTextSelection` rather than three more properties on it: the
/// two publish from different callbacks (a selection bar needs a non-empty selection, this
/// needs an open `[[` trigger) and conflating them would mean either could silently overwrite
/// the other's most recent value.
@MainActor
@Observable
final class CardWikilinkCompletionState {
    /// The card the values below were read from, `nil` until some card has published one -
    /// compared against `WorkspaceController.editingTextNodeID` rather than trusted, the same
    /// reason `CardTextSelection.nodeID` is.
    private(set) var nodeID: String?
    private(set) var candidates: [WikilinkCandidate] = []
    private(set) var selectedIndex = 0
    /// The caret's rectangle in the card's own text view coordinates, `.zero` when there is
    /// nothing to point at.
    private(set) var caretFrame: CGRect = .zero

    /// `@ObservationIgnored` for the same reason `CardTextSelection.textView` is: a `weak`
    /// reference is not something a view observes, and every change worth redrawing for
    /// already lands on the properties above, published in the same call.
    @ObservationIgnored private(set) weak var textView: FormattingTextView?

    /// Reads the current popup state out of the card's text view. Called from that view's own
    /// `onWikilinkCompletionChange` callback, never from inside a SwiftUI update pass.
    func update(nodeID: String, from textView: FormattingTextView) {
        self.nodeID = nodeID
        self.textView = textView
        candidates = textView.wikilinkCompletion?.candidates ?? []
        selectedIndex = textView.wikilinkCompletion?.selectedIndex ?? 0
        caretFrame = textView.caretFrameInView() ?? .zero
    }

    /// Applies `candidate` on the live text view, which keeps a row click and a Return press
    /// one and the same edit - one undo step, through `FormattingTextView`'s own single edit
    /// path. A card whose text view has gone (culled, or editing already over) applies
    /// nothing rather than reaching for a value that is no longer there.
    func apply(_ candidate: WikilinkCandidate) {
        textView?.applyWikilinkCompletion(candidate)
    }
}

/// Decides *whether* the popup is drawn - the card that published it must still be the card
/// being edited, the node must still exist, and its text view must still be alive - mirroring
/// `BoardFormatBarLayer`'s own three-way guard exactly, and for the identical reasons.
struct BoardWikilinkCompletionLayer: View {
    let workspace: WorkspaceController
    /// `WorkspaceView`'s own `viewportSize`, threaded through for the reason
    /// `BoardFormatBarLayer` threads it: nothing drawn today reads it.
    let viewport: CGSize

    var body: some View {
        let state = workspace.wikilinkCompletionState
        if let nodeID = state.nodeID,
           workspace.editingTextNodeID == nodeID,
           !state.candidates.isEmpty,
           let node = workspace.document.node(id: nodeID) {
            BoardWikilinkCompletionPopup(
                workspace: workspace,
                node: node,
                caretFrame: state.caretFrame,
                candidates: state.candidates,
                selectedIndex: state.selectedIndex,
                viewport: viewport,
                onSelect: { candidate in state.apply(candidate) }
            )
        }
    }
}

/// The pill's own drawing, positioned by `BoardWikilinkCompletionGeometry` above -
/// `BoardFormatBar`'s own split between "whether" (the layer) and "where" (this view).
///
/// **Outside** `WorkspaceView`'s `.scaleEffect(workspace.zoom, anchor: .topLeading)`, a
/// sibling of `BoardFormatBarLayer` in the board's own `ZStack` - a view inside that scale
/// would shrink the popup exactly as `BoardFormatBar`'s own header warns.
private struct BoardWikilinkCompletionPopup: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController
    let node: CanvasNode
    let caretFrame: CGRect
    let candidates: [WikilinkCandidate]
    let selectedIndex: Int
    let viewport: CGSize
    let onSelect: (WikilinkCandidate) -> Void

    /// A coloured Nota wraps its `CardTextView` in `.padding(theme.spacing(.s))`
    /// (`StickyTextCard.swift`); a plain Testo does not - `BoardFormatBar.cardOrigin`'s own
    /// correction, needed here for the identical reason.
    private var cardOrigin: CGPoint {
        let inset = node.isNote ? theme.spacing(.s) : 0
        return CGPoint(x: node.x + inset, y: node.y + inset)
    }

    var body: some View {
        let placement = BoardWikilinkCompletionGeometry.placement(
            caretFrame: caretFrame,
            cardOrigin: cardOrigin,
            rowCount: candidates.count,
            zoom: workspace.zoom,
            pan: workspace.pan,
            viewport: viewport
        )
        let size = BoardWikilinkCompletionGeometry.size(forRowCount: candidates.count)
        VStack(spacing: 0) {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                row(candidate, isSelected: index == selectedIndex)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(theme.color(.surfaceRaised))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
        )
        .themedShadow(.card)
        .position(
            x: placement.origin.x + size.width / 2,
            // `placement.origin` is the caret's own top; the flipped side has to clear its
            // drawn height (at zoom) before the gap starts, exactly as `BoardFormatBar`'s own
            // `y` computation does for a selection rectangle.
            y: placement.flipsBelow
                ? placement.origin.y + caretFrame.height * workspace.zoom
                    + BoardWikilinkCompletionGeometry.gap + size.height / 2
                : placement.origin.y - size.height / 2 - BoardWikilinkCompletionGeometry.gap
        )
    }

    private func row(_ candidate: WikilinkCandidate, isSelected: Bool) -> some View {
        Button { onSelect(candidate) } label: {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: candidate.kind == .board ? "square.grid.2x2" : "doc.text")
                    .foregroundStyle(theme.color(.textSecondary))
                Text(candidate.displayTitle)
                    .themedText(.body, color: .textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing(.s))
            .frame(height: BoardWikilinkCompletionGeometry.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? theme.color(.accentMuted) : .clear)
        }
        .buttonStyle(.plain)
    }
}
