import CoreGraphics
import Foundation

/// Where the board is looked at from: zoom, and the two ways of framing content.
extension WorkspaceController {
    /// Steps the zoom by `factor`. With a real `viewport`, recenters around its middle so
    /// the board shrinks or grows in place rather than drifting - `p * zoom + pan` moves p
    /// toward the pan origin as zoom shrinks unless pan is corrected for the same change.
    /// `viewport == .zero` (the default) skips the correction: only the two unit tests in
    /// `CanvasTests.swift` call this without a real viewport, and they assert on the
    /// clamped `zoom` value alone.
    func zoom(by factor: CGFloat, in viewport: CGSize = .zero) {
        let oldZoom = zoom
        let newZoom = min(max(oldZoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        guard viewport != .zero else {
            zoom = newZoom
            return
        }
        let actualFactor = newZoom / oldZoom
        let mid = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        pan = CGSize(
            width: mid.x - (mid.x - pan.width) * actualFactor,
            height: mid.y - (mid.y - pan.height) * actualFactor
        )
        zoom = newZoom
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
        frameContent(in: viewport) { bounds in
            let margin: CGFloat = 80
            let scale = min(
                (viewport.width - margin) / max(bounds.width, 1),
                (viewport.height - margin) / max(bounds.height, 1)
            )
            return min(max(scale, Self.zoomRange.lowerBound), min(1, Self.zoomRange.upperBound))
        }
    }

    /// Shows the board at its actual size, centred on its content - concentrazione's
    /// entry state, the fixed-scale counterpart to `zoomToFit`'s scaled one.
    func zoomToActualSize(in viewport: CGSize) {
        frameContent(in: viewport) { _ in 1 }
    }

    /// The framing `zoomToFit` and `zoomToActualSize` both perform, with only the scale
    /// left to the caller: content measured, then placed under the middle of the viewport.
    ///
    /// A board with no nodes, or a viewport not laid out yet, has no middle to aim at, so
    /// both fall back to the origin at 1:1 rather than centring on nothing. `scale` is
    /// handed the content's bounding rect and owns its own clamping, because the two
    /// callers do not clamp alike - one to the zoom range capped at 1:1, the other not at
    /// all.
    private func frameContent(in viewport: CGSize, scale: (CGRect) -> CGFloat) {
        guard let bounds = contentBounds, viewport.width > 0, viewport.height > 0 else {
            resetZoom()
            return
        }
        zoom = scale(bounds)
        centre(on: CGPoint(x: bounds.midX, y: bounds.midY), in: viewport)
    }

    /// The two ways a board can be reframed once the viewport settles.
    enum RefitMode {
        /// Everything in view, scaled - what leaving concentrazione owes the width the
        /// sidebar, the board list and the tray take back.
        case fit
        /// Actual size, centred on the content - concentrazione's entry state.
        case actualSize
    }

    /// Records that the board owes a reframing, applied by `applyPendingRefit(in:)` once
    /// the viewport it needs is known.
    ///
    /// At the moment of the click the viewport is still the size it is leaving, so the
    /// framing cannot be computed here.
    func requestRefit(_ mode: RefitMode) {
        pendingRefit = mode
    }

    /// Performs the reframing `requestRefit` asked for, against the viewport the layout
    /// settles on.
    ///
    /// `NavigationSplitView` animates `columnVisibility`, so toggling concentrazione
    /// reports several intermediate viewport sizes before the panels finish sliding in or
    /// out - framing against the first one undercorrects and leaves part of the content
    /// behind the tray or the board list once the layout keeps moving. Debounced rather
    /// than one-shot: every intermediate size reschedules this, so only the size the
    /// layout actually settles on ever reaches `zoomToFit`/`zoomToActualSize`.
    func applyPendingRefit(in viewport: CGSize) {
        guard let mode = pendingRefit else { return }
        refitTask?.cancel()
        refitTask = Task {
            // Long enough to land after the columnVisibility animation's last
            // intermediate frame, short enough that the fit still reads as immediate
            // once the panels stop moving.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            switch mode {
            case .fit: zoomToFit(in: viewport)
            case .actualSize: zoomToActualSize(in: viewport)
            }
            pendingRefit = nil
        }
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
    /// The route names a `.canvas` file and that file is what opens: a board is addressed
    /// by its own path (ADR-0025 §D1), so the link's answer is no longer thrown away by a
    /// `deletingLastPathComponent` that opened whichever board the parent folder happened
    /// to imply (ADR-0025 F6).
    ///
    /// Returns the node id when the link named a card this board does not have, so the
    /// caller can say so. A link to a card someone has since deleted still opens the
    /// board: arriving at the right place with nothing selected beats arriving nowhere.
    @discardableResult
    func openRoute(_ route: (path: String, nodeID: String?), viewport: CGSize) -> String? {
        // ADR-0024 §D4: with a board-less folder selected, `board` still names the last
        // *loaded* board, so comparing against it (as the old guard did) would decline to
        // open the board this route names and the link would silently do nothing.
        // `current` is the value that answers "is this board on screen".
        if current != .board(path: route.path) { open(board: route.path) }

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
