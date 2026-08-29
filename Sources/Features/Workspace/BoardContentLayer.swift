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
        // A card being written into keeps the pointer for its own `CardTextView` - caret
        // placement, selection, scrolling - none of which can share the click with the
        // card's own tap-to-select/drag/double-click-to-open gestures below.
        let isEditingText = workspace.editingTextNodeID == node.id

        // Gestures are attached BEFORE `.position`, which is load-bearing: `.position`
        // expands its result to fill the parent, so anything added after it responds
        // across the whole board instead of over the card. With them after, no card
        // could be selected at all.
        // The frame a resize in flight is showing, which is the node's own frame the
        // rest of the time.
        let frame = workspace.displayFrame(for: node)

        cardBody(node)
            // Stable regardless of render state: the placeholder branch below carries
            // no Text, so a UI test that only knows the node's title cannot find a card
            // once `drawsPlaceholder` switches it in at low zoom.
            .accessibilityIdentifier("canvas-node-\(node.id)")
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
            .selectionGestures(enabled: !isEditingText) {
                cardActions.open(node)
            } onSelect: {
                workspace.select(nodeID: node.id, adding: modifiers.contains(.shift))
            } drag: {
                cardGesture(node)
            }
            // The entries come from `CardCommand`, which the board's command bar reads
            // too, so the two surfaces cannot offer a card different commands under
            // different names (ADR-0023 §D1, §D8).
            .contextMenu { BoardCardMenuItems.menu(for: node, actions: cardActions) }
            // The grips come after the card's own gesture, which is what puts them
            // above it: attached before, the card's drag took the pointer first and
            // the corners could never be grabbed. Suppressed while writing, the same
            // condition the crop editor's own grips already use just below.
            .overlay { grips(node, isSelected: isSelected && !isEditingText, frame: frame) }
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

    /// What a card command does, and which cards it does it to. One value, read by this
    /// menu and by `BoardCardControls`, so the two surfaces perform the same body rather
    /// than two that agree today (ADR-0023 §D1). Every one of those bodies used to live in
    /// this file, back when the context menu was the only surface there was, and moved to
    /// `BoardCardActions` unchanged.
    private var cardActions: BoardCardActions {
        BoardCardActions(workspace: workspace, vault: vault)
    }

    /// The JSON Canvas preset colours (SPEC §6.2), named as the spec numbers them.
    ///
    /// Kept here rather than moved beside the menu builder that reads them: they are the
    /// submenu's contents, not the command list, and both surfaces read them from this one
    /// table.
    static let colorNames = ["Rosso", "Arancio", "Giallo", "Verde", "Ciano", "Viola"]

    /// The presets of SPEC §10, "ridimensiona a preset".
    static let sizePresets: [(name: String, size: CGSize)] = [
        ("Piccola", CGSize(width: 200, height: 120)),
        ("Media", CGSize(width: 320, height: 220)),
        ("Grande", CGSize(width: 480, height: 360)),
        ("Colonna", CGSize(width: 260, height: 520)),
    ]
}

private extension View {
    /// Tap-to-select, double-click-to-open and drag-to-move, or none of the three: a card
    /// being written into (`StickyTextCard`'s `CardTextView`) needs every click for its own
    /// caret placement and selection, and these three gestures would otherwise race it for
    /// the same pointer.
    @ViewBuilder
    func selectionGestures(
        enabled: Bool,
        onOpen: @escaping () -> Void,
        onSelect: @escaping () -> Void,
        drag: () -> some Gesture
    ) -> some View {
        if enabled {
            self
                .onTapGesture(count: 2, perform: onOpen)
                .onTapGesture(perform: onSelect)
                .gesture(drag())
        } else {
            self
        }
    }
}
