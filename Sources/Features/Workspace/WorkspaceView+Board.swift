import SwiftUI

/// The board itself: the `ZStack` of background, grid, cards and overlays, the gestures on it,
/// and the conversion from a point in the view to a point on the board.
///
/// An extension file of `WorkspaceView` (ADR-0045 §D2). Every member moved here keeps its
/// access level; only `board` widens, because `mainContent` places it, and the view's three
/// `@State` properties the board writes are internal in `WorkspaceView.swift` for the same
/// reason (ADR-0045 §D3). `canvasPoint(from:)` was already internal before the move, for
/// `WorkspaceView+Drawing.swift`.
extension WorkspaceView {
    // MARK: Board

    /// Not `private`: `mainContent` in `WorkspaceView.swift` places it.
    var board: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                boardBackground(in: geometry.size)
                cropKeyboardShortcuts

                if workspace.showsGrid { grid }

                BoardContentLayer(
                    workspace: workspace,
                    modifiers: modifiers,
                    viewportSize: viewportSize
                )
                // Scales from the top-left and then offsets, so a board point p
                // lands at p * zoom + pan. Anchoring at the centre instead would make
                // the pan depend on the viewport size and the two would fight.
                .scaleEffect(workspace.zoom, anchor: .topLeading)
                .offset(workspace.pan)

                BoardGuides(workspace: workspace)
                BoardMarquee(workspace: workspace)
                // Third overlay outside the `scaleEffect` above, and the only one of the three
                // that answers the pointer, so it comes after both (ADR-0027 §D5).
                BoardFormatBarLayer(workspace: workspace, viewport: viewportSize)
                // Same placement, same reason as the layer above (ADR §D5): outside the
                // `scaleEffect`, after it in the ZStack so it answers the pointer for row clicks.
                BoardWikilinkCompletionLayer(workspace: workspace, viewport: viewportSize)

                if workspace.tool == .drawing || !workspace.activeDrawing.strokes.isEmpty {
                    drawingLayer(in: geometry.size)
                }

                floatingControls
            }
            .clipped()
            .gesture(pinchGesture)
            .onModifierKeysChanged(mask: [.shift, .option, .command]) { _, held in modifiers = held }
            .dropDestination(for: URL.self) { (urls: [URL], location: CGPoint) -> Bool in
                propose(import: urls, at: canvasPoint(from: location))
            }
            .onAppear {
                viewportSize = geometry.size
                workspace.zoomToFit(in: geometry.size)
                applyBoardSettings()
            }
            .onChange(of: vault.settings) { _, _ in applyBoardSettings() }
            // Every intermediate size the concentrazione animation reports lands here and
            // reschedules the reframing it owes; only the size the layout settles on ever
            // reaches `zoomToFit`/`zoomToActualSize` (`WorkspaceController+Viewport`).
            .onChange(of: geometry.size) { _, size in
                viewportSize = size
                workspace.applyPendingRefit(in: size)
            }
            .onChange(of: workspace.board) { _, _ in
                // A board opens over its content, not over the origin. Keyed on the board's
                // own path, not its folder (#569 point 6): since ADR-0025 two boards share a
                // folder, and the second opened on an empty viewport. `board` goes `""` on a
                // folder or empty selection, so reopening the same board refits too.
                workspace.zoomToFit(in: viewportSize)
            }
        }
    }

    /// The empty board under everything: what a click that hits no card lands on.
    private func boardBackground(in size: CGSize) -> some View {
        theme.color(.canvasBackground)
            .contentShape(Rectangle())
            .onTapGesture { location in
                // A click outside the card confirms an open crop (ADR-0020 D5) or a card
                // being written into, rather than acting on whatever tool is selected.
                if workspace.croppingNodeID != nil {
                    workspace.endCrop(confirm: true)
                } else if workspace.editingTextNodeID != nil {
                    workspace.endTextEdit(commit: true)
                } else {
                    handleTap(at: canvasPoint(from: location))
                }
            }
            // Attached to the background alone. On the whole board it also fired while a
            // card was being dragged, and the two gestures moved the same content against
            // each other.
            .gesture(backgroundGesture(in: size))
    }

    /// Esc cancels an open crop, Enter confirms it (ADR-0020 D5).
    ///
    /// Hidden buttons rather than an `onKeyPress`: the board hosts no first responder of
    /// its own, and a keyboard shortcut on a button reaches the window regardless of what
    /// has focus, the same way Annulla/Ripeti do in the toolbar.
    @ViewBuilder
    private var cropKeyboardShortcuts: some View {
        if workspace.croppingNodeID != nil {
            Button("") { workspace.endCrop(confirm: false) }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()
            Button("") { workspace.endCrop(confirm: true) }
                .keyboardShortcut(.return, modifiers: [])
                .hidden()
        }
    }

    /// The capsules that float over the board's bottom-trailing corner.
    private var floatingControls: some View {
        VStack(alignment: .trailing, spacing: theme.spacing(.xs)) {
            // Above the pen row, so the zoom controls stay where a person has learned to
            // find them when the bar appears and disappears with the selection
            // (ADR-0023 §D7).
            if BoardCardControls.isShown(selection: workspace.selection) {
                BoardCardControls(workspace: workspace)
            }
            if workspace.tool == .drawing {
                BoardPenControls(
                    workspace: workspace,
                    penColor: $penColor,
                    penWidth: $penWidth,
                    isErasing: $isErasing
                )
            }
            BoardZoomControls(workspace: workspace, viewportSize: viewportSize)
        }
        .padding(theme.spacing(.m))
    }

    /// SPEC §6.1: pinch zooms. Relative to the zoom the gesture started at, so the
    /// magnification is not applied again on every frame.
    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let origin = pinchOrigin ?? workspace.zoom
                pinchOrigin = origin
                workspace.setZoom(origin * value.magnification)
            }
            .onEnded { _ in pinchOrigin = nil }
    }

    /// Offers the dropped files as import proposals, answering whether any was accepted.
    private func propose(import urls: [URL], at point: CGPoint) -> Bool {
        importProposals = workspace.importFiles(urls, at: point)
        return !importProposals.isEmpty
    }

    /// Carries the vault's canvas preferences into the board (SPEC §12).
    private func applyBoardSettings() {
        workspace.showsGrid = vault.settings.boardShowsGrid
        workspace.snapsToGrid = vault.settings.boardSnapsToGrid
        // The editor's own markup setting, reaching the card by the route the two above already
        // take (ADR-0028 §D10): one switch for both surfaces, re-run on every settings change by
        // the `onChange(of: vault.settings)` this method is already wired to.
        workspace.hidesMarkup = vault.settings.hidesMarkup
        // ADR-0037 §D8: the same route, one property wider.
        workspace.revealsInlineSpans = vault.settings.revealsInlineSpans
        // The `[[` completion popup's candidate pool (point 1 of the workspace wikilink
        // regression chain) - refreshed on the same triggers as the settings above, not on
        // every vault mutation: a note created in another pane while this board stays open
        // will not appear until the next settings change re-runs this method, the same
        // accepted staleness `hidesMarkup` itself already has.
        workspace.wikilinkNoteTitles = vault.index.allNotes.map(\.title)
        workspace.wikilinkBoardTitles = vault.root.map { CanvasStore(root: $0).allBoards() } ?? []
    }

    private var grid: some View {
        Canvas { context, size in
            let step = WorkspaceController.gridStep * workspace.zoom
            guard step > 4 else { return }   // below this the grid is a solid wash

            var path = Path()
            let offsetX = workspace.pan.width.truncatingRemainder(dividingBy: step)
            let offsetY = workspace.pan.height.truncatingRemainder(dividingBy: step)
            for x in stride(from: offsetX, through: size.width, by: step) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: offsetY, through: size.height, by: step) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(theme.color(.canvasGrid)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    /// Drag on empty board: a marquee with the select tool, a pan with Option held.
    ///
    /// Both live on the same gesture because SwiftUI delivers one drag per view, and
    /// two `DragGesture`s on the background would race for it.
    private func backgroundGesture(in size: CGSize) -> some Gesture {
        // `.local` here, unlike the card gestures, and the difference is load-bearing.
        // The background is a sibling of the scaled layer, not inside it, so its local
        // space is the board's own unscaled space: translations are unaffected, and
        // `startLocation` is what `canvasPoint` inverts pan and zoom against. Measured
        // in `.global` the marquee was displaced by the whole sidebar and toolbar - it
        // caught cards to the right of the rectangle and missed the ones inside it.
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                guard !workspace.isDragging else { return }
                if modifiers.contains(.option) || workspace.tool != .select {
                    workspace.beginPan()
                    // Absolute, from the pan the gesture started at: a gesture reports
                    // its total translation, so adding it each frame compounds it.
                    workspace.updatePan(translation: value.translation)
                    return
                }
                if workspace.marqueeRect == nil {
                    workspace.beginMarquee(at: canvasPoint(from: value.startLocation))
                }
                workspace.updateMarquee(to: canvasPoint(from: value.location))
            }
            .onEnded { _ in
                workspace.endPan()
                workspace.endMarquee(adding: modifiers.contains(.shift))
            }
    }

    /// Converts a point in the view to a point on the board, inverting
    /// `p * zoom + pan`.
    func canvasPoint(from location: CGPoint) -> CGPoint {
        CGPoint(
            x: (location.x - workspace.pan.width) / workspace.zoom,
            y: (location.y - workspace.pan.height) / workspace.zoom
        )
    }
}
