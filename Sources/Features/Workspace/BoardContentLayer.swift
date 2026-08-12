import SwiftUI

/// The board's own content: the connectors and the cards.
///
/// A view of its own rather than a section of `WorkspaceView`, which now holds the
/// board's gestures and the tools that create things. What is drawn and what listens
/// for a drag are two different concerns and were the two halves of that file.
struct BoardContentLayer: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    let workspace: WorkspaceController
    /// Shift and Option as the board is tracking them, for Shift+click and a
    /// proportional resize.
    let modifiers: EventModifiers
    let viewportSize: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(workspace.document.edges) { edge in
                edgeShape(edge)
            }
            ForEach(visibleNodes) { node in
                nodeView(node)
            }
        }
    }

    // MARK: Edges

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
                    arrowHead(at: end, from: start)
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

    private func arrowHead(at point: CGPoint, from origin: CGPoint) -> some View {
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
        .stroke(theme.color(.borderStrong), lineWidth: 1.5)
    }

    // MARK: Nodes

    @ViewBuilder
    private func nodeView(_ node: CanvasNode) -> some View {
        let isSelected = workspace.selection.contains(node.id)

        // Gestures are attached BEFORE `.position`, which is load-bearing: `.position`
        // expands its result to fill the parent, so anything added after it responds
        // across the whole board instead of over the card. With them after, no card
        // could be selected at all.
        // The frame a resize in flight is showing, which is the node's own frame the
        // rest of the time.
        let frame = workspace.displayFrame(for: node)

        cardBody(node)
            .frame(width: frame.width, height: frame.height)
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                    .strokeBorder(
                        isSelected ? theme.color(.canvasSelection) : .clear,
                        lineWidth: 2
                    )
            )
            .overlay {
                if isSelected {
                    ForEach(BoardGeometry.Handle.allCases, id: \.self) { handle in
                        resizeHandle(node, handle: handle, in: frame)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { open(node) }
            .onTapGesture { workspace.select(nodeID: node.id, adding: modifiers.contains(.shift)) }
            .contextMenu {
                Button("Apri") { open(node) }
                Button("Copia link Pergamenum") { copyLink(to: node) }
                Divider()
                Button("Elimina") { workspace.delete(nodeIDs: [node.id]) }
            }
            .gesture(
                // `.global`, not a named space: a named space that fails to resolve falls back
                // to `.local`, which sits inside the board's `scaleEffect`, so a 100-point
                // mouse move was reported as 170 units and then divided by the zoom again.
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { value in
                        // Selecting on drag start keeps a drag of an unselected card
                        // from moving whatever was selected before.
                        if !workspace.isDragging {
                            if !workspace.selection.contains(node.id) {
                                workspace.select(nodeID: node.id, adding: modifiers.contains(.shift))
                            }
                            workspace.beginDrag(nodeIDs: workspace.selection, anchor: node.id)
                        }
                        // Screen translation to board units: at 58% zoom a 100-point
                        // drag is 172 board units, not 100.
                        workspace.updateDrag(translation: CGSize(
                            width: value.translation.width / workspace.zoom,
                            height: value.translation.height / workspace.zoom
                        ))
                    }
                    .onEnded { _ in workspace.endDrag() }
            )
            .position(x: frame.midX, y: frame.midY)
            // Visual feedback for the drag. Safe now that the gesture measures in
            // `.global`: moving the view no longer moves the space it is measured in.
            .offset(workspace.dragOffsetInPoints(for: node.id))
    }

    /// One of the eight grips of SPEC §6.3, placed on the card's edge.
    private func resizeHandle(
        _ node: CanvasNode,
        handle: BoardGeometry.Handle,
        in frame: CGRect
    ) -> some View {
        let unit = handle.unitPoint
        return RoundedRectangle(cornerRadius: 2)
            .fill(theme.color(.canvasSelection))
            .frame(width: 9, height: 9)
            .position(x: unit.x * frame.width, y: unit.y * frame.height)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if workspace.resizingNodeID != node.id {
                            workspace.beginResize(nodeID: node.id, handle: handle)
                        }
                        workspace.updateResize(
                            translation: CGSize(
                                width: value.translation.width / workspace.zoom,
                                height: value.translation.height / workspace.zoom
                            ),
                            // Shift locks the proportions (SPEC §6.3).
                            lockAspect: modifiers.contains(.shift)
                        )
                    }
                    .onEnded { _ in workspace.endResize() }
            )
    }

    /// The cards worth drawing at the current pan and zoom (SPEC §6.3, culling).
    private var visibleNodes: [CanvasNode] {
        BoardGeometry.visibleNodes(
            workspace.document.nodes,
            in: BoardGeometry.visibleRect(
                viewport: viewportSize, pan: workspace.pan, zoom: workspace.zoom
            )
        )
    }

    /// A card's content, or a plain placeholder when it is too small to read.
    ///
    /// Below a quarter zoom the content is illegible anyway, and rendering a hundred
    /// PDF thumbnails costs the frame rate the board needs while panning.
    @ViewBuilder
    private func cardBody(_ node: CanvasNode) -> some View {
        if BoardGeometry.drawsPlaceholder(at: workspace.zoom) {
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .fill(theme.color(node.color == nil ? .surfaceCard : .surfaceRaised))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                        .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
                )
        } else {
            NodeCard(node: node, subfolder: workspace.subfolder(for: node), workspace: workspace)
        }
    }

    /// Puts a `pergamenum://canvas?file=…&node=…` link on the pasteboard, so a card
    /// can be linked to from Obsidian, DEVONthink or Mail (SPEC §9).
    private func copyLink(to node: CanvasNode) {
        guard let store = vault.root.map({ CanvasStore(root: $0) }) else { return }
        let boardPath = store.boardPath(forFolder: workspace.folder)
        guard let url = PergamenumLink.canvas(path: boardPath, nodeID: node.id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    /// Double click: enter a folder's board, or open the file the card points at.
    private func open(_ node: CanvasNode) {
        if let subfolder = workspace.subfolder(for: node) {
            workspace.open(folder: subfolder)
            return
        }
        switch node.kind {
        case .file(let path, _):
            if path.lowercased().hasSuffix(".svg"), workspace.editDrawing(nodeID: node.id) {
                // One of our own drawings: reopen the ink rather than the image.
                workspace.tool = .drawing
            } else if path.hasSuffix(".md") {
                vault.openNote(at: path)
            } else if let root = vault.root {
                NSWorkspace.shared.open(root.appending(path: path))
            }
        case .link(let url):
            if let target = URL(string: url) { NSWorkspace.shared.open(target) }
        case .text, .group, .unknown:
            break
        }
    }
}
