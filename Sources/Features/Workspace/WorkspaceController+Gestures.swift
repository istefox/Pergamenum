import CoreGraphics
import Foundation

/// The gestures of SPEC §6.3: dragging cards, panning the board, the marquee and the
/// resize grips.
///
/// The model is not touched while a gesture is in flight. Moving it moves the view the
/// gesture is attached to, SwiftUI re-anchors the gesture to the new position, and the
/// translation feeds back into itself: one 100-point drag reported 48, 112, 262, 662,
/// 1780, then 4965 points. Each gesture is therefore a transient offset the view draws
/// with, committed once on release - which also turns twelve autosaves into one.
extension WorkspaceController {
    func beginDrag(nodeIDs: Set<String>, anchor: String? = nil) {
        guard draggingIDs.isEmpty else { return }
        // Moving a group moves what it holds (SPEC §6.5).
        draggingIDs = BoardGeometry.expandingGroups(nodeIDs, among: document.nodes)
        dragAnchorID = anchor ?? nodeIDs.first
        dragTranslation = .zero
        activeGuides = []
    }

    /// Records the gesture's total translation, already converted to board units, and
    /// pulls the card onto whatever it lines up with.
    func updateDrag(translation: CGSize) {
        guard !draggingIDs.isEmpty else { return }
        guard let anchorID = dragAnchorID, let anchor = document.node(id: anchorID) else {
            dragTranslation = translation
            return
        }

        let proposed = anchor.frame.offsetBy(dx: translation.width, dy: translation.height)
        let others = document.nodes
            .filter { !draggingIDs.contains($0.id) }
            .map(\.frame)
        // The threshold is in board units, so the pull is the same handful of pixels
        // whatever the zoom: a fixed board threshold would be imperceptible zoomed out
        // and would fight the pointer zoomed in.
        let (snapped, guides) = BoardGeometry.snapped(
            proposed, to: others,
            threshold: 6 / max(zoom, 0.01),
            gridStep: snapsToGrid ? Self.gridStep : nil
        )
        dragTranslation = CGSize(width: snapped.minX - anchor.x, height: snapped.minY - anchor.y)
        activeGuides = guides
    }

    /// Applies the drag to the model and clears the transient state.
    func endDrag() {
        defer {
            draggingIDs = []
            dragTranslation = .zero
            dragAnchorID = nil
            activeGuides = []
        }
        guard !draggingIDs.isEmpty,
              dragTranslation != .zero
        else { return }
        move(nodeIDs: draggingIDs, by: dragTranslation)
    }

    /// The offset a node should be drawn with while a drag is in flight.
    ///
    /// In board units, which is what the model uses and also what the view wants:
    /// the card layer is drawn inside the board's `scaleEffect`, so board units are
    /// converted to screen points for free. A screen-point variant of this existed
    /// and was applied there too, which scaled the offset twice and left the card
    /// trailing the pointer at any zoom below 100%.
    func dragOffset(for nodeID: String) -> CGSize {
        draggingIDs.contains(nodeID) ? dragTranslation : .zero
    }

    /// Pan at the moment the background drag began, held here for the same reason as

    func beginPan() {
        if panOrigin == nil { panOrigin = pan }
    }

    func updatePan(translation: CGSize) {
        guard let origin = panOrigin else { return }
        pan = CGSize(width: origin.width + translation.width, height: origin.height + translation.height)
    }

    func endPan() {
        panOrigin = nil
    }

    func beginMarquee(at point: CGPoint) {
        marqueeStart = point
        marqueeRect = CGRect(origin: point, size: .zero)
    }

    func updateMarquee(to point: CGPoint) {
        guard let start = marqueeStart else { return }
        marqueeRect = BoardGeometry.rect(from: start, to: point)
    }

    /// Commits the marquee. `adding` is the Shift modifier: without it the marquee
    /// replaces the selection, with it the caught cards join what was already chosen.
    func endMarquee(adding: Bool = false) {
        defer {
            marqueeStart = nil
            marqueeRect = nil
        }
        guard let rect = marqueeRect else { return }
        let caught = BoardGeometry.nodeIDs(in: rect, among: document.nodes)
        selection = adding ? selection.union(caught) : caught
    }

    /// Chooses a card, or adds it to the selection when Shift is held.
    func select(nodeID: String, adding: Bool) {
        selection = adding ? BoardGeometry.toggling(nodeID, in: selection) : [nodeID]
    }

    /// Returns to Seleziona after a tool has been used once, unless the user locked
    /// the tool by double clicking it (SPEC §6.4, "one-shot").
    func finishToolUse() {
        if !isToolLocked { tool = .select }
    }

    func beginResize(nodeID: String, handle: BoardGeometry.Handle) {
        guard let node = document.node(id: nodeID) else { return }
        resizingNodeID = nodeID
        resizeHandle = handle
        resizeOriginalFrame = node.frame
        resizedFrame = node.frame
    }

    /// `lockAspect` is the Shift modifier of SPEC §6.3.
    func updateResize(translation: CGSize, lockAspect: Bool) {
        guard resizingNodeID != nil else { return }
        resizedFrame = BoardGeometry.resized(
            resizeOriginalFrame, handle: resizeHandle, by: translation, lockAspect: lockAspect
        )
    }

    func endResize() {
        defer {
            resizingNodeID = nil
            resizedFrame = nil
        }
        guard let nodeID = resizingNodeID, let frame = resizedFrame, frame != resizeOriginalFrame
        else { return }
        mutate { document in
            guard let index = document.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
            document.nodes[index].x = frame.minX
            document.nodes[index].y = frame.minY
            document.nodes[index].width = frame.width
            document.nodes[index].height = frame.height
        }
    }

    /// The frame a card should be drawn with, accounting for a resize in flight.
    func displayFrame(for node: CanvasNode) -> CGRect {
        node.id == resizingNodeID ? (resizedFrame ?? node.frame) : node.frame
    }

    // MARK: Arrow

    /// Starts an arrow at a card (SPEC §6.4, tool 11).
    ///
    /// Only the source is recorded. The far end is the source's centre plus the
    /// gesture's translation, which is what lets the whole thing be measured in the
    /// global space the card drags already use: an absolute pointer position would
    /// need the board's origin on screen, and the board is inside a `scaleEffect` and
    /// an `offset` that both move under it.
    func beginArrow(from nodeID: String) {
        guard document.node(id: nodeID) != nil else { return }
        arrowSourceID = nodeID
        arrowTranslation = .zero
    }

    func updateArrow(translation: CGSize) {
        guard arrowSourceID != nil else { return }
        arrowTranslation = translation
    }

    /// Where the arrow currently points, in board units, or `nil` when none is being
    /// drawn. The board draws the rubber band from the source's centre to here.
    var arrowEndPoint: CGPoint? {
        guard let sourceID = arrowSourceID, let source = document.node(id: sourceID) else { return nil }
        return CGPoint(
            x: source.frame.midX + arrowTranslation.width,
            y: source.frame.midY + arrowTranslation.height
        )
    }

    /// Commits the arrow if it ended on another card, and returns to Seleziona.
    ///
    /// Released over nothing, it draws no edge and reports it: an arrow to empty
    /// board has no second node to attach to, and JSON Canvas has no dangling edge.
    @discardableResult
    func endArrow() -> String? {
        defer {
            arrowSourceID = nil
            arrowTranslation = .zero
            finishToolUse()
        }
        guard let sourceID = arrowSourceID, let point = arrowEndPoint,
              let targetID = BoardGeometry.nodeID(at: point, among: document.nodes, excluding: sourceID)
        else { return nil }
        return connect(from: sourceID, to: targetID)
    }
}
