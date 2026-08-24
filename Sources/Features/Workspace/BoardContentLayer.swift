import SwiftUI

/// The board's own content: the cards, over the connector layer.
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
            BoardEdgeLayer(workspace: workspace)
            ForEach(visibleNodes) { node in
                nodeView(node)
            }
        }
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
            // A group answers the pointer on its frame only; everything else answers
            // over its whole rectangle.
            .contentShape(hitShape(for: node))
            .onTapGesture(count: 2) { open(node) }
            .onTapGesture { workspace.select(nodeID: node.id, adding: modifiers.contains(.shift)) }
            .contextMenu {
                Button("Apri") { open(node) }
                Button("Copia link Pergamenum") { copyLink(to: node) }
                Divider()
                Menu("Colore") {
                    Button("Nessuno") { workspace.setColor(nil, forNodeIDs: targets(node)) }
                    ForEach(1...6, id: \.self) { preset in
                        Button(Self.colorNames[preset - 1]) {
                            workspace.setColor(.preset(preset), forNodeIDs: targets(node))
                        }
                    }
                }
                Menu("Ridimensiona") {
                    ForEach(Self.sizePresets, id: \.name) { preset in
                        Button(preset.name) {
                            for id in targets(node) {
                                workspace.resize(nodeID: id, to: preset.size)
                            }
                        }
                    }
                    if CanvasCrop.read(from: node) != nil {
                        Divider()
                        Button("Adatta al ritaglio") { Task { await fitToCrop(node) } }
                    }
                }
                if isCroppable(node) {
                    Divider()
                    Button("Ritaglia") {
                        workspace.beginCrop(nodeID: node.id, drawnSize: workspace.displayFrame(for: node).size)
                    }
                    if CanvasCrop.read(from: node) != nil {
                        Button("Rimuovi ritaglio") { workspace.removeCrop(nodeIDs: targets(node)) }
                    }
                }
                Divider()
                Button("Elimina") { workspace.delete(nodeIDs: targets(node)) }
            }
            .gesture(cardGesture(node))
            // The grips come after the card's own gesture, which is what puts them
            // above it: attached before, the card's drag took the pointer first and
            // the corners could never be grabbed.
            .overlay { grips(node, isSelected: isSelected, frame: frame) }
            .position(x: frame.midX, y: frame.midY)
            // Visual feedback for the drag, in board units: this offset is applied
            // inside the board's `scaleEffect`, so the scale is already accounted for
            // and multiplying by the zoom here applied it twice. At 68% the card
            // trailed the pointer by a third of every move and then jumped into
            // place on release, which reads as a card that will not be grabbed.
            .offset(workspace.dragOffset(for: node.id))
    }

    /// Dragging a card: moves it, or draws an arrow from it when Freccia is the
    /// active tool (SPEC §6.4, tool 11).
    ///
    /// One gesture for both because SwiftUI delivers one drag per view; two would
    /// race for it.
    private func cardGesture(_ node: CanvasNode) -> some Gesture {
        // `.global`, not a named space: a named space that fails to resolve falls back
        // to `.local`, which sits inside the board's `scaleEffect`, so a 100-point
        // mouse move was reported as 170 units and then divided by the zoom again.
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                // Screen translation to board units: at 58% zoom a 100-point
                // drag is 172 board units, not 100.
                let translation = CGSize(
                    width: value.translation.width / workspace.zoom,
                    height: value.translation.height / workspace.zoom
                )
                guard workspace.tool != .arrow else {
                    if workspace.arrowSourceID == nil { workspace.beginArrow(from: node.id) }
                    workspace.updateArrow(translation: translation)
                    return
                }
                // Selecting on drag start keeps a drag of an unselected card
                // from moving whatever was selected before.
                if !workspace.isDragging {
                    if !workspace.selection.contains(node.id) {
                        workspace.select(nodeID: node.id, adding: modifiers.contains(.shift))
                    }
                    workspace.beginDrag(nodeIDs: workspace.selection, anchor: node.id)
                }
                workspace.updateDrag(translation: translation)
            }
            .onEnded { _ in
                if workspace.arrowSourceID != nil {
                    workspace.endArrow()
                    return
                }
                workspace.endDrag()
            }
    }

    /// The eight grips of SPEC §6.3, on a frame wide enough to hold them.
    ///
    /// The overlay is grown by one target on each side because a corner grip is
    /// centred on the corner: half of it falls outside the card, and content outside
    /// its parent's bounds is drawn but never hit.
    @ViewBuilder
    private func grips(_ node: CanvasNode, isSelected: Bool, frame: CGRect) -> some View {
        // No point on screen belongs to two gestures at once: the crop editor draws its
        // own eight grips over the same card (ADR-0020 D5).
        if isSelected, workspace.croppingNodeID != node.id {
            let target = BoardGeometry.boardUnits(
                BoardGeometry.handleTargetScreenSize, at: workspace.zoom
            )
            ZStack {
                ForEach(BoardGeometry.Handle.allCases, id: \.self) { handle in
                    ResizeHandleView(
                        workspace: workspace,
                        node: node,
                        handle: handle,
                        frame: frame,
                        modifiers: modifiers
                    )
                }
            }
            .frame(width: frame.width + target, height: frame.height + target)
        }
    }

    /// What the pointer can touch on a card.
    ///
    /// A group is hollow: it is a container, so a click in its middle belongs to
    /// whatever is inside it, and only its frame moves the group itself (SPEC §6.5).
    private func hitShape(for node: CanvasNode) -> AnyShape {
        guard node.isGroup else { return AnyShape(Rectangle()) }
        return AnyShape(
            GroupFrameShape(
                band: BoardGeometry.boardUnits(
                    BoardGeometry.groupBandScreenWidth, at: workspace.zoom
                )
            )
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
            NodeCard(
                node: node, subfolder: workspace.subfolder(for: node), workspace: workspace,
                modifiers: modifiers
            )
        }
    }

    /// Puts a `pergamenum://canvas?file=…&node=…` link on the pasteboard, so a card
    /// can be linked to from Obsidian, DEVONthink or Mail (SPEC §9).
    /// The cards an action applies to: the whole selection when the card is part of
    /// it, otherwise just this one. Acting on the selection when the user right-clicked
    /// something outside it is how a context menu deletes the wrong thing.
    private func targets(_ node: CanvasNode) -> Set<String> {
        workspace.selection.contains(node.id) ? workspace.selection : [node.id]
    }

    /// The JSON Canvas preset colours (SPEC §6.2), named as the spec numbers them.
    private static let colorNames = ["Rosso", "Arancio", "Giallo", "Verde", "Ciano", "Viola"]

    /// The presets of SPEC §10, "ridimensiona a preset".
    private static let sizePresets: [(name: String, size: CGSize)] = [
        ("Piccola", CGSize(width: 200, height: 120)),
        ("Media", CGSize(width: 320, height: 220)),
        ("Grande", CGSize(width: 480, height: 360)),
        ("Colonna", CGSize(width: 260, height: 520)),
    ]

    /// Whether "Ritaglia" belongs on this card's menu at all (ADR-0020 D8): a raster
    /// image, at a zoom where there is something on screen to aim at.
    private func isCroppable(_ node: CanvasNode) -> Bool {
        guard case .file(let path, _) = node.kind else { return false }
        return CanvasCrop.isCroppable(path: path) && !BoardGeometry.drawsPlaceholder(at: workspace.zoom)
    }

    /// "Adatta al ritaglio" (ADR-0020 D4): resizes each target that carries a crop to the
    /// height its own cropped region implies at its current width, so the card stops
    /// letterboxing without ever moving the crop itself. Needs the source image's own
    /// pixel size, which only `ThumbnailStore` knows - the one part of this action that
    /// cannot be synchronous.
    private func fitToCrop(_ node: CanvasNode) async {
        guard let store = workspace.thumbnails else { return }
        for id in targets(node) {
            guard let target = workspace.document.node(id: id),
                  case .file(let path, _) = target.kind,
                  let crop = CanvasCrop.read(from: target)
            else { continue }
            let task = await store.thumbnail(for: path, width: target.width)
            guard let image = await task.value else { continue }
            let croppedAspect = (crop.width * image.size.width) / (crop.height * image.size.height)
            guard croppedAspect.isFinite, croppedAspect > 0 else { continue }
            workspace.resize(nodeID: id, to: CGSize(width: target.width, height: target.width / croppedAspect))
        }
    }

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
