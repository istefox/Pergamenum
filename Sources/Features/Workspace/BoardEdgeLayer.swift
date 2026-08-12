import SwiftUI

/// The connectors of a board: the edges already on it, and the one being drawn.
///
/// Split from `BoardContentLayer`, which kept the cards. The two share nothing but
/// the coordinate space they are drawn in, and a connector answers to no pointer at
/// all while a card is nothing but pointer behaviour.
struct BoardEdgeLayer: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(workspace.document.edges) { edge in
                edgeShape(edge)
            }
            arrowInFlight
        }
        // Connectors are drawn, never touched: without this they would take clicks
        // meant for the cards they run between.
        .allowsHitTesting(false)
    }

    /// Draws a connector between two nodes.
    ///
    /// The endpoints are computed from the nodes' current frames rather than stored,
    /// which is what makes the connector stay attached when a card moves (SPEC §6.4,
    /// tool 11) without writing the file on every drag frame.
    @ViewBuilder
    private func edgeShape(_ edge: CanvasEdge) -> some View {
        if let from = workspace.document.node(id: edge.fromNode),
           let to = workspace.document.node(id: edge.toNode) {
            let start = anchor(of: from, facing: to, side: edge.fromSide)
            let end = anchor(of: to, facing: from, side: edge.toSide)

            ZStack {
                Path { path in
                    path.move(to: start)
                    path.addLine(to: end)
                }
                .stroke(theme.color(.borderStrong), lineWidth: 1.5)

                // The spec's default for `toEnd` is `arrow`, so an absent value means
                // an arrow, not the absence of one.
                if (edge.toEnd ?? .arrow) == .arrow {
                    arrowHead(at: end, from: start, color: theme.color(.borderStrong))
                }
                if let label = edge.label {
                    Text(label)
                        .themedText(.caption, color: .textSecondary)
                        .padding(.horizontal, 4)
                        .background(theme.color(.canvasBackground))
                        .position(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                }
            }
        }
    }

    /// The rubber band of the Freccia tool, from the card the drag started on to
    /// wherever the pointer has reached (SPEC §6.4, tool 11).
    ///
    /// Dashed, so it reads as a proposal rather than as an edge that already exists:
    /// released over empty board it draws nothing at all.
    @ViewBuilder
    private var arrowInFlight: some View {
        if let sourceID = workspace.arrowSourceID,
           let source = workspace.document.node(id: sourceID),
           let end = workspace.arrowEndPoint {
            let start = CGPoint(x: source.frame.midX, y: source.frame.midY)
            ZStack {
                Path { path in
                    path.move(to: start)
                    path.addLine(to: end)
                }
                .stroke(
                    theme.color(.canvasSelection),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
                arrowHead(at: end, from: start, color: theme.color(.canvasSelection))
            }
        }
    }

    /// The point on a node's edge that faces another node. An explicit side from the
    /// file wins; otherwise the side is chosen from the relative position, which is
    /// what keeps a connector sensible after either card is dragged.
    private func anchor(of node: CanvasNode, facing other: CanvasNode, side: CanvasEdge.Side?) -> CGPoint {
        let frame = node.frame
        let resolved: CanvasEdge.Side = side ?? {
            let dx = other.frame.midX - frame.midX
            let dy = other.frame.midY - frame.midY
            if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
            return dy > 0 ? .bottom : .top
        }()

        return switch resolved {
        case .top: CGPoint(x: frame.midX, y: frame.minY)
        case .bottom: CGPoint(x: frame.midX, y: frame.maxY)
        case .left: CGPoint(x: frame.minX, y: frame.midY)
        case .right: CGPoint(x: frame.maxX, y: frame.midY)
        }
    }

    private func arrowHead(at point: CGPoint, from origin: CGPoint, color: Color) -> some View {
        let angle = atan2(point.y - origin.y, point.x - origin.x)
        let length: CGFloat = 10
        let spread: CGFloat = .pi / 7

        return Path { path in
            path.move(to: point)
            path.addLine(to: CGPoint(
                x: point.x - length * cos(angle - spread),
                y: point.y - length * sin(angle - spread)
            ))
            path.move(to: point)
            path.addLine(to: CGPoint(
                x: point.x - length * cos(angle + spread),
                y: point.y - length * sin(angle + spread)
            ))
        }
        .stroke(color, lineWidth: 1.5)
    }
}
