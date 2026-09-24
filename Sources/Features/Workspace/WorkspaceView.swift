import SwiftUI

/// The Workspace: a spatial view of one folder, with the board hierarchy above it.
///
/// Split across five files along the seams the `// MARK:` comments already marked -
/// this one keeps the view's state, its body and the board itself, while the drawing
/// overlay, the sidebar's folder verbs, item creation and the toolbar live in
/// `WorkspaceView+Drawing`, `WorkspaceView+FolderVerbs`, `WorkspaceView+Creation` and
/// `WorkspaceView+Toolbar`. A member read by one of those extensions is internal
/// rather than `private` for that reason alone: `private` is file scope, so an
/// extension in another file cannot see it.
struct WorkspaceView: View {
    @Environment(\.theme) var theme
    @Environment(VaultController.self) var vault
    // Internal rather than `private`: `WorkspaceView+Toolbar` is another file, and
    // `private` is file scope.
    @Environment(Navigation.self) var navigation
    @Environment(ThemeEngine.self) var themeEngine
    /// The **window's** undo manager, which is the one `NSTextView` already registers its
    /// text edits on (ADR-0026 §D8): one window, one undo history, and Cmd+Z means "undo
    /// the last thing I did here" whatever had focus. Read here and handed to
    /// `VaultController.moveItems` as an argument, so the facade never reaches for
    /// `NSApp.keyWindow?.undoManager` and never imports AppKit for this.
    ///
    /// Internal rather than `private`: `WorkspaceView+FolderVerbs` is another file, and
    /// `private` is file scope.
    @Environment(\.undoManager) var undoManager
    @State var workspace = WorkspaceController()
    @State private var viewportSize: CGSize = .zero
    /// Shift and Option as they are held right now. `DragGesture` carries no modifier
    /// information, so the board has to track them itself to tell a marquee from a
    /// pan and a free resize from a proportional one.
    @State private var modifiers: EventModifiers = []
    /// The zoom a pinch started from, so the magnification is applied to it once
    /// rather than compounding on every frame of the gesture.
    @State private var pinchOrigin: CGFloat?
    @State var newItemDraft: NewItemDraft?
    // Internal rather than `private`: `WorkspaceView+Toolbar` is another file, and
    // `private` is file scope.
    @State var isShowingQuickLook = false
    @State var importProposals: [WorkspaceController.ImportProposal] = []
    /// Pen settings for the Disegno tool (SPEC §6.4, tool 10).
    @State var penColor: ColorToken = .textPrimary
    @State var penWidth: CGFloat = 2
    @State var isErasing = false
    /// The board list's width, dragged with `WorkspacePaneDivider`. Machine-local
    /// (`@AppStorage`, not `VaultSettings`): it describes the screen, not the vault
    /// (ADR-0012 §D10).
    @AppStorage("workspaceBrowserWidth") private var browserWidth: Double = 200

    var body: some View {
        // Split into `mainContent` plus two modifier stages: the single-expression
        // modifier chain this used to be tipped the whole-body type-check over its
        // budget the moment `attach(...)` grew a third argument ("the compiler is
        // unable to type-check this expression in reasonable time"), and the failure
        // point moved to a different modifier each time one was pulled out - the whole
        // chain is checked as one expression regardless of which piece is heaviest.
        // Splitting the CHAIN across separate declarations, not just extracting closure
        // bodies, is what actually bounds each piece's inference on its own.
        //
        // `selectedFileURLs` is derived once here and handed down rather than asked for
        // by each reader: it filters every node in the document and stats each selected
        // file, and its two readers - the Quick Look target below and the toolbar's
        // Anteprima button - are evaluated in the same body pass, so asking twice paid
        // that walk and those syscalls twice on every redraw of the board.
        let previewURLs = workspace.selectedFileURLs
        return lifecycleModifiers(
            mainContent(previewURLs: previewURLs), previewURLs: previewURLs
        )
    }

    @ViewBuilder
    private func lifecycleModifiers(_ content: some View, previewURLs: [URL]) -> some View {
        routingModifiers(
            content
                .quickLook(urls: previewURLs, isPresented: $isShowingQuickLook)
                .onChange(of: vault.isShowingQuickLook) { _, requested in
                    consumeQuickLookRequest(requested)
                }
                // Entering shows the content at its actual size - concentrazione is for
                // working on the board, not for reading it at whatever scale it happened
                // to be left at. Leaving hands the width back to the app sidebar, the
                // board list and the tray, so the fit has to catch up with the viewport
                // they take back. Both are owed rather than done: the viewport they need
                // is the one the layout has not finished animating to yet.
                .onChange(of: navigation.isWorkspaceFocused) { _, focused in
                    workspace.requestRefit(focused ? .actualSize : .fit)
                }
                .onAppear {
                    attachWorkspace()
                    checkPendingNewBoard()
                }
                .onDisappear {
                    // A conflicted board is not flushed here: flushing would attempt
                    // exactly the write already refused, on the same stale expectation.
                    // `detach()` (the next thing to run when the vault itself closes)
                    // reports the loss instead (ADR-0054 §D5).
                    guard case .conflicted = workspace.saveState else {
                        workspace.flushPendingSave()
                        return
                    }
                }
                // `pergamenum://canvas?file=…&node=…` parks its target on the controller,
                // and this is what acts on it. Nothing did before: the route reported
                // success and opened nothing at all. Checked on appear too, because a
                // link that launches the app arrives before this view exists.
                .task { openPendingCanvas() }
                .onChange(of: vault.routeState.pendingCanvas?.path) { _, _ in openPendingCanvas() }
                // The one value `Destination.workspaceBoard` (ADR-0015 §D1 amendment) needs
                // the window to read - `workspace.board` itself is `@State` here and stays
                // unreachable from `WindowPlace`, so it is mirrored up rather than exposed
                // directly. `""` is "nothing open" on the controller (`WorkspaceController.
                // swift:80`); `nil` is the same on `VaultController.openBoardPath`.
                .onChange(of: workspace.board) { _, board in
                    vault.openBoardPath = board.isEmpty ? nil : board
                }
        )
    }

    @ViewBuilder
    private func routingModifiers(_ content: some View) -> some View {
        content
            // File → "Nuova board" (SPEC §10): set before this view existed this session
            // (checked on appear, above) or while it is already showing (checked here) -
            // the same double registration `openPendingCanvas` needs and for the same
            // reason.
            .onChange(of: vault.pendingNewBoard) { _, isPending in
                guard isPending else { return }
                checkPendingNewBoard()
            }
            .onChange(of: vault.pendingWorkspacePlacement) { _, pending in placePendingNote(pending) }
            .onChange(of: vault.root) { _, newRoot in reattachWorkspace(to: newRoot) }
            .sheet(item: $newItemDraft) { draft in newItemSheet(draft) }
            .sheet(isPresented: Binding(
                get: { !importProposals.isEmpty },
                set: { if !$0 { importProposals = [] } }
            )) {
                ImportSheet(
                    proposals: $importProposals,
                    onCancel: { importProposals = [] },
                    onConfirm: { confirmed in confirmImports(confirmed) }
                )
            }
    }

    private func mainContent(previewURLs: [URL]) -> some View {
        VStack(spacing: 0) {
            BoardTopBar(workspace: workspace)
            Divider()
            HStack(spacing: 0) {
                // R-01: the vault's boards, in the shape they have on disk. Leading,
                // beside the tool column, because it is where you are rather than what
                // you can do - the same split the note pane makes between its list and
                // its editor. Hidden in concentrazione, alongside the app sidebar and
                // the tray, so the board keeps the width they gave up.
                if !navigation.isWorkspaceFocused && !navigation.isWorkspaceTreeCollapsed {
                    WorkspaceBrowser(
                        // The whole selection, not the folder read off it (ADR-0025 §D8):
                        // the pane lights the row the selection *names* - a board file's
                        // own row when one is open - and its two verbs dispatch on the
                        // case, so throwing it away here would only have to be recovered
                        // there.
                        selection: workspace.current,
                        actions: folderActions,
                        onSelect: { workspace.select($0) }
                    )
                    .frame(width: CGFloat(browserWidth))
                    WorkspacePaneDivider(width: Binding(
                        get: { CGFloat(browserWidth) },
                        set: { browserWidth = Double($0) }
                    ))
                }
                if workspace.isShowingBoard {
                    BoardToolbar(workspace: workspace)
                    Divider()
                    board
                    if navigation.isShowingTray && !navigation.isWorkspaceFocused {
                        Divider()
                        BoardTray(workspace: workspace)
                    }
                } else {
                    emptyState
                }
            }
        }
        .background(theme.color(.backgroundPrimary))
        .toolbar { toolbar(previewURLs: previewURLs) }
    }

    private func attachWorkspace() {
        guard let root = vault.root else { return }
        workspace.attach(to: CanvasStore(root: root), thumbnails: vault.thumbnails, vault: vault)
    }

    /// Points the board at the vault that has just opened, letting go of the previous one.
    private func reattachWorkspace(to newRoot: URL?) {
        workspace.detach()
        guard let newRoot else { return }
        workspace.attach(
            to: CanvasStore(root: newRoot), thumbnails: vault.thumbnails, vault: vault
        )
    }

    /// Takes the Quick Look request the vault parked, and puts it down again so the next
    /// one is a change this view can see.
    private func consumeQuickLookRequest(_ requested: Bool) {
        guard requested else { return }
        isShowingQuickLook = true
        vault.isShowingQuickLook = false
    }

    /// A note sent here from the editor lands on the board of its own folder, which is
    /// where it already lives on disk - if that folder means exactly one board (§D5).
    ///
    /// The only one of §D5's three navigations that also **reports**: the other two are
    /// navigation, this one is a gesture whose note would otherwise land nowhere. It used
    /// to open a board named after the folder, writing one where none existed - the last
    /// door through which the app created a `.canvas` nobody asked for (ADR-0025 §F8).
    private func placePendingNote(_ pending: String??) {
        guard let pendingOuter = pending, let pending = pendingOuter else { return }
        defer { _ = vault.consumePendingWorkspacePlacement() }
        let folder = (pending as NSString).deletingLastPathComponent
        // `enter(folder:)` selects the board or the folder and reads the board list here, in the
        // hand-off, never in `body`: `allBoards()` walks the vault uncached.
        let resolution = workspace.enter(folder: folder)
        if let problem = WorkspaceBoardResolver.placementProblem(
            for: pending, inFolder: folder, resolution: resolution
        ) {
            vault.recordProblem(problem)
            return
        }
        // A board that could not be read leaves the previous one on screen (ADR-0025 §D4),
        // and the note must not be placed on it.
        guard case .unique(let path) = resolution, workspace.current == .board(path: path.value) else { return }
        if !workspace.document.nodes.contains(where: {
            if case .file(let path, _) = $0.kind { return path == pending } else { return false }
        }) {
            _ = workspace.placeFile(pending, at: CGPoint(x: 60, y: 60))
        }
    }

    /// What the board area shows before anything has been chosen - the same shape as
    /// `EditorColumnView.emptyState`, so an empty Workspace and an empty editor column
    /// read as the same idea rather than two different ones.
    private var emptyState: some View {
        VStack(spacing: theme.spacing(.s)) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 32))
                .foregroundStyle(theme.color(.textTertiary))
            Text("Nessuna board aperta").themedText(.body, color: .textSecondary)
            Text("Seleziona una board dall'elenco a sinistra").themedText(.caption, color: .textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.color(.backgroundPrimary))
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

    /// Named out of the `ImportSheet` closure: an inline `for` loop there pushed the
    /// whole `body` modifier chain over the type-checker's per-expression budget.
    private func confirmImports(_ proposals: [WorkspaceController.ImportProposal]) {
        for proposal in proposals { _ = workspace.commitImport(proposal) }
        importProposals = []
    }

    // MARK: Board

    private var board: some View {
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
            .onChange(of: workspace.folder) { _, _ in
                // A board opens over its content, not over the origin.
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
