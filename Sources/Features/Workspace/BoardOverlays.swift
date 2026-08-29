import SwiftUI

/// The selection rectangle, drawn in view coordinates over the board (SPEC §6.3).
///
/// Its own view rather than a computed property on `WorkspaceView`, following
/// `BoardContentLayer` and `BoardZoomControls`: everything it needs arrives through
/// the controller, so it neither reads nor widens the board's private state.
struct BoardMarquee: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController

    var body: some View {
        if let rect = workspace.marqueeRect {
            // The board scales from its top-left and then offsets, so a board point p
            // lands at p * zoom + pan.
            let origin = CGPoint(
                x: rect.origin.x * workspace.zoom + workspace.pan.width,
                y: rect.origin.y * workspace.zoom + workspace.pan.height
            )
            Rectangle()
                .fill(theme.color(.canvasSelection).opacity(0.12))
                .overlay(Rectangle().strokeBorder(theme.color(.canvasSelection), lineWidth: 1))
                .frame(width: rect.width * workspace.zoom, height: rect.height * workspace.zoom)
                .position(
                    x: origin.x + rect.width * workspace.zoom / 2,
                    y: origin.y + rect.height * workspace.zoom / 2
                )
                .allowsHitTesting(false)
        }
    }
}

/// Alignment guides, shown only while a drag is snapping to something (SPEC §6.3).
struct BoardGuides: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController

    var body: some View {
        Canvas { context, size in
            for guide in workspace.activeGuides {
                var path = Path()
                switch guide.axis {
                case .vertical:
                    let x = guide.position * workspace.zoom + workspace.pan.width
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                case .horizontal:
                    let y = guide.position * workspace.zoom + workspace.pan.height
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(
                    path, with: .color(theme.color(.accentPrimary)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// The floating format pill over the `.text` card being written into (ADR-0027 §D5).
///
/// The third overlay in this file, and here for the same reason as the two above: it draws in
/// board-container coordinates, **outside** `WorkspaceView`'s `.scaleEffect`, converting a board
/// point with the transform `BoardMarquee` documents at the top of this file. Unlike those two
/// it is not `allowsHitTesting(false)` - its whole purpose is to be pressed - which is also why
/// it is the last of the three in the board's `ZStack`.
///
/// This view decides *whether* there is a bar; `BoardFormatBar` decides where it goes. Three
/// things must line up before one is drawn, and each has a way of not being true: the card that
/// published a selection must still be the card being edited (it stops being one as soon as
/// editing moves on, and nothing clears the published value), the node must still exist in the
/// document, and its text view must still be alive - a weak reference to a view SwiftUI is free
/// to dismantle whenever the card leaves `BoardContentLayer.visibleNodes`' culling rect.
struct BoardFormatBarLayer: View {
    let workspace: WorkspaceController
    /// `WorkspaceView`'s own `viewportSize`, threaded through to `placement` for the horizontal
    /// clamp `BoardFormatBarGeometry` names as a future need. Nothing drawn today reads it.
    let viewport: CGSize

    var body: some View {
        let selection = workspace.cardTextSelection
        if let nodeID = selection.nodeID,
           BoardFormatBarGeometry.shouldShowFormatBar(
               editingTextNodeID: workspace.editingTextNodeID,
               forNodeID: nodeID,
               selectionRange: selection.range
           ),
           let node = workspace.document.node(id: nodeID) {
            BoardFormatBar(
                workspace: workspace,
                node: node,
                selectionFrame: selection.frame,
                viewport: viewport,
                // Closures over the holder rather than over the text view it points at: the
                // holder is owned by the controller and outlives every card, so a bar left
                // behind by one render cannot keep a dead card's text view alive.
                isInlineApplied: { selection.isApplied($0) },
                isLineApplied: { selection.isApplied($0) },
                onToggleInline: { selection.toggle($0) },
                onToggleLine: { selection.toggle($0) }
            )
        }
    }
}
