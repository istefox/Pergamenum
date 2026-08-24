import SwiftUI

/// The Workspace: a spatial view of one folder, with the board hierarchy above it.
struct WorkspaceView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @State private var workspace = WorkspaceController()
    @State private var viewportSize: CGSize = .zero
    /// Shift and Option as they are held right now. `DragGesture` carries no modifier
    /// information, so the board has to track them itself to tell a marquee from a
    /// pan and a free resize from a proportional one.
    @State private var modifiers: EventModifiers = []
    /// The zoom a pinch started from, so the magnification is applied to it once
    /// rather than compounding on every frame of the gesture.
    @State private var pinchOrigin: CGFloat?
    @State private var newItemDraft: NewItemDraft?
    @State private var isShowingTray = true
    @State private var isShowingQuickLook = false
    @State private var importProposals: [WorkspaceController.ImportProposal] = []
    /// Pen settings for the Disegno tool (SPEC §6.4, tool 10).
    @State private var penColor: ColorToken = .textPrimary
    @State private var penWidth: CGFloat = 2
    @State private var isErasing = false

    /// What the user is about to create, once they have typed its name or URL.
    private struct NewItemDraft: Identifiable {
        enum Kind { case folder, link, note, text }
        let id = UUID()
        var kind: Kind
        var point: CGPoint
        var value = ""
    }

    var body: some View {
        VStack(spacing: 0) {
            BoardTopBar(workspace: workspace)
            Divider()
            HStack(spacing: 0) {
                BoardToolbar(workspace: workspace)
                Divider()
                board
                if isShowingTray {
                    Divider()
                    BoardTray(workspace: workspace)
                }
            }
        }
        .background(theme.color(.backgroundPrimary))
        .toolbar { toolbar }
        .quickLook(urls: workspace.selectedFileURLs, isPresented: $isShowingQuickLook)
        .onChange(of: vault.isShowingQuickLook) { _, requested in
            guard requested else { return }
            isShowingQuickLook = true
            vault.isShowingQuickLook = false
        }
        .onAppear {
            if let root = vault.root {
                workspace.attach(to: CanvasStore(root: root), thumbnails: vault.thumbnails)
            }
            checkPendingNewBoard()
        }
        .onDisappear { workspace.flushPendingSave() }
        // `pergamenum://canvas?file=…&node=…` parks its target on the controller, and
        // this is what acts on it. Nothing did before: the route reported success and
        // opened nothing at all. Checked on appear too, because a link that launches
        // the app arrives before this view exists.
        .task { openPendingCanvas() }
        .onChange(of: vault.routeState.pendingCanvas?.path) { _, _ in openPendingCanvas() }
        // File → "Nuova board" (SPEC §10): set before this view existed this session
        // (checked on appear, above) or while it is already showing (checked here) -
        // the same double registration `openPendingCanvas` needs and for the same
        // reason.
        .onChange(of: vault.pendingNewBoard) { _, isPending in
            guard isPending else { return }
            checkPendingNewBoard()
        }
        .onChange(of: vault.pendingWorkspacePlacement) { _, pending in
            // A note sent here from the editor lands on the board of its own folder,
            // which is where it already lives on disk.
            guard let pending = pending ?? nil else { return }
            let folder = (pending as NSString).deletingLastPathComponent
            if workspace.folder != folder { workspace.open(folder: folder) }
            if !workspace.document.nodes.contains(where: {
                if case .file(let path, _) = $0.kind { return path == pending } else { return false }
            }) {
                _ = workspace.placeFile(pending, at: CGPoint(x: 60, y: 60))
            }
            _ = vault.consumePendingWorkspacePlacement()
        }
        .onChange(of: vault.root) { _, newRoot in
            workspace.detach()
            if let newRoot {
                workspace.attach(to: CanvasStore(root: newRoot), thumbnails: vault.thumbnails)
            }
        }
        .sheet(item: $newItemDraft) { draft in
            newItemSheet(draft)
        }
        .sheet(isPresented: Binding(
            get: { !importProposals.isEmpty },
            set: { if !$0 { importProposals = [] } }
        )) {
            ImportSheet(
                proposals: $importProposals,
                onCancel: { importProposals = [] },
                onConfirm: { confirmed in
                    for proposal in confirmed { _ = workspace.commitImport(proposal) }
                    importProposals = []
                }
            )
        }
    }

    private func openPendingCanvas() {
        guard let pending = vault.consumePendingCanvasRoute() else { return }
        if let missing = workspace.openRoute(pending, viewport: viewportSize) {
            vault.recordProblem("il link punta a una card che non esiste: \(missing)")
        }
    }

    /// File → "Nuova board": opens the same naming sheet the "Cartella" tool's tap
    /// handler opens (`handleTap(at:)`, `.folder` case), on the current board, at the
    /// same position-less default `pendingWorkspacePlacement` uses below.
    private func checkPendingNewBoard() {
        guard vault.consumePendingNewBoard() else { return }
        newItemDraft = NewItemDraft(kind: .folder, point: CGPoint(x: 60, y: 60))
    }

    /// The board's window-level commands.
    ///
    /// Undo and redo keep the shortcuts they had in the top bar. They are not in the
    /// shortcut catalogue: the standard Modifica menu already shows Annulla and
    /// Ripeti, they do not reach the board, and reconciling the two is a change to
    /// the undo architecture rather than to a toolbar.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { workspace.undo() } label: {
                Label("Annulla", systemImage: "arrow.uturn.backward")
            }
            .help("Annulla")
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!workspace.canUndo)

            Button { workspace.redo() } label: {
                Label("Ripeti", systemImage: "arrow.uturn.forward")
            }
            .help("Ripeti")
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!workspace.canRedo)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button { isShowingQuickLook = true } label: {
                Label("Anteprima", systemImage: "eye")
            }
            .help("Anteprima rapida del file selezionato (barra spaziatrice)")
            .disabled(workspace.selectedFileURLs.isEmpty)

            Toggle(isOn: $isShowingTray) {
                Label("Nuovi elementi", systemImage: "tray")
            }
            .help("Elementi della cartella non ancora posati sulla board")
        }
    }

    // MARK: Board

    private var board: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                theme.color(.canvasBackground)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        handleTap(at: canvasPoint(from: location, in: geometry.size))
                    }
                    // Attached to the background alone. On the whole board it also
                    // fired while a card was being dragged, and the two gestures moved
                    // the same content against each other.
                    .gesture(backgroundGesture(in: geometry.size))

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

                if workspace.tool == .drawing || !workspace.activeDrawing.strokes.isEmpty {
                    drawingLayer(in: geometry.size)
                }

                VStack(alignment: .trailing, spacing: theme.spacing(.xs)) {
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
            .clipped()
            // SPEC §6.1: pinch zooms. Relative to the zoom the gesture started at, so
            // the magnification is not applied again on every frame.
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let origin = pinchOrigin ?? workspace.zoom
                        pinchOrigin = origin
                        workspace.setZoom(origin * value.magnification)
                    }
                    .onEnded { _ in pinchOrigin = nil }
            )
            .onModifierKeysChanged(mask: [.shift, .option]) { _, held in modifiers = held }
            .dropDestination(for: URL.self) { urls, location in
                importProposals = workspace.importFiles(
                    urls, at: canvasPoint(from: location, in: geometry.size)
                )
                return !importProposals.isEmpty
            }
            .onAppear {
                viewportSize = geometry.size
                workspace.zoomToFit(in: geometry.size)
                applyBoardSettings()
            }
            .onChange(of: vault.settings) { _, _ in applyBoardSettings() }
            .onChange(of: geometry.size) { _, size in viewportSize = size }
            .onChange(of: workspace.folder) { _, _ in
                // A board opens over its content, not over the origin.
                workspace.zoomToFit(in: viewportSize)
            }
        }
    }

    /// Carries the vault's canvas preferences into the board (SPEC §12).
    private func applyBoardSettings() {
        workspace.showsGrid = vault.settings.boardShowsGrid
        workspace.snapsToGrid = vault.settings.boardSnapsToGrid
    }

    private var grid: some View {
        Canvas { context, size in
            let step = 24 * workspace.zoom
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
                    workspace.beginMarquee(at: canvasPoint(from: value.startLocation, in: size))
                }
                workspace.updateMarquee(to: canvasPoint(from: value.location, in: size))
            }
            .onEnded { _ in
                workspace.endPan()
                workspace.endMarquee(adding: modifiers.contains(.shift))
            }
    }

    private var panGesture: some Gesture {
        // `.global`, not a named space: a named space that fails to resolve falls back
                // to `.local`, which sits inside the board's `scaleEffect`, so a 100-point
                // mouse move was reported as 170 units and then divided by the zoom again.
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                guard workspace.tool == .select, !workspace.isDragging else { return }
                workspace.beginPan()
                // Absolute, from the pan the gesture started at: a gesture reports its
                // total translation, so adding it each frame compounds it.
                workspace.updatePan(translation: value.translation)
            }
            .onEnded { _ in workspace.endPan() }
    }

    // MARK: Drawing

    /// Captures pen strokes over the board and previews them live.
    private func drawingLayer(in size: CGSize) -> some View {
        Canvas { context, _ in
            for stroke in workspace.activeDrawing.strokes {
                guard stroke.points.count > 1 else { continue }
                var path = Path()
                path.move(to: viewPoint(stroke.points[0]))
                for point in stroke.points.dropFirst() { path.addLine(to: viewPoint(point)) }

                context.stroke(
                    path,
                    with: .color(Color(hex: stroke.color).opacity(stroke.opacity)),
                    style: StrokeStyle(
                        lineWidth: stroke.width * workspace.zoom, lineCap: .round, lineJoin: .round
                    )
                )
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let point = canvasPoint(from: value.location, in: size)
                    if isErasing {
                        workspace.eraseStrokes(near: point, radius: max(8, penWidth * 3))
                        return
                    }
                    if value.translation == .zero {
                        workspace.beginStroke(
                            at: point,
                            color: theme.hexValue(penColor),
                            width: penWidth,
                            // A highlighter is a wide, translucent stroke; the pen is
                            // neither (SPEC §6.4, tool 10).
                            opacity: penWidth >= 10 ? 0.4 : 1
                        )
                    } else {
                        workspace.extendStroke(to: point)
                    }
                }
                .onEnded { _ in }
        )
    }

    /// Board point to view point, the forward direction of `canvasPoint`.
    private func viewPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * workspace.zoom + workspace.pan.width,
            y: point.y * workspace.zoom + workspace.pan.height
        )
    }

    // MARK: Creation

    /// Converts a point in the view to a point on the board, inverting
    /// `p * zoom + pan`.
    private func canvasPoint(from location: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (location.x - workspace.pan.width) / workspace.zoom,
            y: (location.y - workspace.pan.height) / workspace.zoom
        )
    }

    private func handleTap(at point: CGPoint) {
        switch workspace.tool {
        case .select:
            workspace.selection = []
        case .note:
            _ = workspace.addStickyNote("", at: point)
        case .text:
            _ = workspace.addFreeText("", at: point)
        case .folder:
            newItemDraft = NewItemDraft(kind: .folder, point: point)
        case .link:
            newItemDraft = NewItemDraft(kind: .link, point: point)
        case .document:
            newItemDraft = NewItemDraft(kind: .note, point: point)
        case .todo:
            _ = workspace.addStickyNote("- [ ] ", at: point)
        case .image:
            if let urls = VaultOpenPanel.chooseFiles(
                title: "Importa immagini",
                message: "Le immagini vengono copiate nella cartella della board."
            ) {
                importProposals = workspace.importFiles(urls, at: point)
            }
        case .drawing:
            // The drawing layer takes over the board while this tool is active.
            break
        case .arrow, .forms:
            // The arrow is drawn by dragging between two cards; forms is v2.
            break
        }
        // Back to Seleziona after one use (SPEC §6.4), except for the two tools that
        // are used by dragging rather than by tapping: resetting those would end the
        // gesture the user is in the middle of.
        if workspace.tool != .drawing, workspace.tool != .arrow {
            workspace.finishToolUse()
        }
    }

    private func newItemSheet(_ draft: NewItemDraft) -> some View {
        NewCanvasItemSheet(
            kind: draft.kind == .folder ? .folder : (draft.kind == .link ? .link : .note),
            onCancel: { newItemDraft = nil },
            onConfirm: { value in
                create(draft.kind, value: value, at: draft.point)
                newItemDraft = nil
            }
        )
    }

    private func create(_ kind: NewItemDraft.Kind, value: String, at point: CGPoint) {
        switch kind {
        case .folder:
            do {
                _ = try workspace.createFolder(named: value, at: point)
            } catch {
                // Reported through the workspace's own problem list rather than a
                // modal: the board is still usable and the name can be retried.
                workspace.recordProblem("\(error)")
            }
        case .link:
            _ = workspace.addLink(value, at: point)
        case .note:
            do {
                let path = try vault.createNote(
                    title: value, in: workspace.folder, date: .today
                )
                _ = workspace.placeFile(path, at: point, creatingOnDisk: path)
            } catch {
                workspace.recordProblem(ConformanceText.creationFailure(error))
            }
        case .text:
            _ = workspace.addFreeText(value, at: point)
        }
    }
}
