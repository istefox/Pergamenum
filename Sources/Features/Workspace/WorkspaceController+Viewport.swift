import CoreGraphics
import Foundation

/// Where the board is looked at from: zoom, and the two ways of framing content.
extension WorkspaceController {
    func zoom(by factor: CGFloat) {
        zoom = min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    /// Sets the zoom directly, clamped to the range of SPEC §6.1. Used by the pinch
    /// gesture, which computes an absolute value rather than a step.
    func setZoom(_ value: CGFloat) {
        zoom = min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    func resetZoom() {
        zoom = 1
        pan = .zero
    }

    /// The rectangle enclosing every node, in board coordinates.
    var contentBounds: CGRect? {
        guard let first = document.nodes.first else { return nil }
        return document.nodes.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }

    /// Fits every node in the given viewport (the "adatta alla vista" control).
    ///
    /// The board's coordinate space is centred on the origin and routinely negative -
    /// Obsidian writes nodes at x = -720 - so a freshly opened board shows nothing at
    /// all unless the view is placed over the content rather than over the origin.
    func zoomToFit(in viewport: CGSize) {
        guard let bounds = contentBounds, viewport.width > 0, viewport.height > 0 else {
            resetZoom()
            return
        }
        let margin: CGFloat = 80
        let scale = min(
            (viewport.width - margin) / max(bounds.width, 1),
            (viewport.height - margin) / max(bounds.height, 1)
        )
        zoom = min(max(scale, Self.zoomRange.lowerBound), min(1, Self.zoomRange.upperBound))
        centre(on: CGPoint(x: bounds.midX, y: bounds.midY), in: viewport)
    }

    /// Shows the board at its actual size, centred on its content - concentrazione's
    /// entry state, the fixed-scale counterpart to `zoomToFit`'s scaled one.
    func zoomToActualSize(in viewport: CGSize) {
        guard let bounds = contentBounds, viewport.width > 0, viewport.height > 0 else {
            resetZoom()
            return
        }
        zoom = 1
        centre(on: CGPoint(x: bounds.midX, y: bounds.midY), in: viewport)
    }

    /// Places a board point at the middle of the viewport.
    ///
    /// The view scales from its top-left corner and then offsets, so a board point `p`
    /// lands at `p * zoom + pan`; solving for the viewport centre gives this.
    func centre(on point: CGPoint, in viewport: CGSize) {
        pan = CGSize(
            width: viewport.width / 2 - point.x * zoom,
            height: viewport.height / 2 - point.y * zoom
        )
    }
}

extension WorkspaceController {
    /// Acts on a `pergamenum://canvas` link (SPEC §9).
    ///
    /// The route names a `.canvas` file; this controller works in folders, because a
    /// board *is* a folder (SPEC §6.2), so the folder is the file's parent.
    ///
    /// Returns the node id when the link named a card this board does not have, so the
    /// caller can say so. A link to a card someone has since deleted still opens the
    /// board: arriving at the right place with nothing selected beats arriving nowhere.
    @discardableResult
    func openRoute(_ route: (path: String, nodeID: String?), viewport: CGSize) -> String? {
        let folder = (route.path as NSString).deletingLastPathComponent
        // ADR-0024 §D4: with a board-less folder selected, `self.folder` still names the
        // last *loaded* board, so comparing against it (as the old guard did) would
        // decline to open the board this route names and the link would silently do
        // nothing. `current` is the value that answers "is this board on screen".
        if current != .board(folder: folder) { open(folder: folder) }

        guard let nodeID = route.nodeID else { return nil }
        guard let node = document.nodes.first(where: { $0.id == nodeID }) else { return nodeID }

        selection = [nodeID]
        // Skipped before the first layout pass, when the viewport is still zero and
        // centring would put the board somewhere arbitrary.
        if viewport != .zero {
            centre(
                on: CGPoint(x: node.x + node.width / 2, y: node.y + node.height / 2),
                in: viewport
            )
        }
        return nil
    }
}
