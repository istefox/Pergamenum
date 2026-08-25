import SwiftUI

/// The Workspace: a spatial view of one folder, with the board hierarchy above it.
struct WorkspaceView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation
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
    @State private var isShowingQuickLook = false
    @State private var importProposals: [WorkspaceController.ImportProposal] = []
    /// Pen settings for the Disegno tool (SPEC §6.4, tool 10).
    @State private var penColor: ColorToken = .textPrimary
    @State private var penWidth: CGFloat = 2
    @State private var isErasing = false
    /// The board list's width, dragged with `WorkspacePaneDivider`. Machine-local
    /// (`@AppStorage`, not `VaultSettings`): it describes the screen, not the vault
    /// (ADR-0012 §D10).
    @AppStorage("workspaceBrowserWidth") private var browserWidth: Double = 200
    /// Raised on leaving concentrazione, consumed once the board's `GeometryReader`
    /// settles on the size it grew back into - `zoomToFit` needs that size, and at the
    /// moment of the click it is still the narrow one.
    @State private var needsRefit = false
    /// The entering counterpart to `needsRefit`: raised on entering concentrazione,
    /// consumed the same way once the board's widened viewport is known.
    @State private var needsActualSizeZoom = false
    /// `NavigationSplitView` animates `columnVisibility`, so toggling concentrazione
    /// reports several intermediate `geometry.size` values before the panels finish
    /// sliding in or out - fitting against the first one undercorrects and leaves part
    /// of the content behind the tray or the board list once the layout keeps moving.
    /// Debounced instead of one-shot: every intermediate size reschedules this, so only
    /// the size the layout actually settles on ever reaches `zoomToFit`/`zoomToActualSize`.
    @State private var pendingFitTask: Task<Void, Never>?

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
                // R-01: the vault's boards, in the shape they have on disk. Leading,
                // beside the tool column, because it is where you are rather than what
                // you can do - the same split the note pane makes between its list and
                // its editor. Hidden in concentrazione, alongside the app sidebar and
                // the tray, so the board keeps the width they gave up.
                if !navigation.isWorkspaceFocused {
                    WorkspaceBrowser(
                        openBoardPath: openBoardPath,
                        actions: folderActions,
                        onOpen: { path in
                            workspace.open(folder: (path as NSString).deletingLastPathComponent)
                        },
                        onDeselect: { workspace.closeBoard() }
                    )
                    .frame(width: CGFloat(browserWidth))
                    WorkspacePaneDivider(width: Binding(
                        get: { CGFloat(browserWidth) },
                        set: { browserWidth = Double($0) }
                    ))
                }
                if workspace.hasOpenBoard {
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
        .toolbar { toolbar }
        .quickLook(urls: workspace.selectedFileURLs, isPresented: $isShowingQuickLook)
        .onChange(of: vault.isShowingQuickLook) { _, requested in
            guard requested else { return }
            isShowingQuickLook = true
            vault.isShowingQuickLook = false
        }
        // Entering shows the content at its actual size - concentrazione is for working
        // on the board, not for reading it at whatever scale it happened to be left at.
        // Leaving hands the width back to the app sidebar, the board list and the tray,
        // so the fit has to catch up with the viewport they take back.
        .onChange(of: navigation.isWorkspaceFocused) { _, focused in
            if focused { needsActualSizeZoom = true } else { needsRefit = true }
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
            if !workspace.hasOpenBoard || workspace.folder != folder { workspace.open(folder: folder) }
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

    /// The board on screen, as a vault-relative path, so the browser can draw its row
    /// as the selected one. A board is named after its folder (`boardPath(forFolder:)`
    /// is the whole of that mapping), so the folder the controller holds is enough.
    private var openBoardPath: String? {
        guard workspace.hasOpenBoard, let root = vault.root else { return nil }
        return CanvasStore(root: root).boardPath(forFolder: workspace.folder)
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

    // MARK: Folder verbs

    /// The sidebar's three verbs, performed here rather than in the browser because all
    /// three need this view's `WorkspaceController` (ADR-0022 §D10).
    ///
    /// Each one is the same three steps in the same order, and the order is the whole of
    /// the decision: **flush first** - the board autosaves about a second after a change
    /// and that write would otherwise land on the old path, recreating the directory the
    /// rename moved or the delete trashed (§F10) - then the vault call, then the
    /// navigation rule that says where the open board goes next.
    private var folderActions: WorkspaceFolderActions {
        WorkspaceFolderActions(
            create: { name, parent in createWorkspace(named: name, in: parent) },
            rename: { folder, newName in renameWorkspace(folder, to: newName) },
            delete: { folder in deleteWorkspace(folder) }
        )
    }

    /// Creates the folder, gives it its board, and opens it (R-02).
    ///
    /// `CanvasStore.createFolder(named:in:)` unchanged: it refuses a name that is taken
    /// and does not create intermediate directories, and the sheet has already blocked on
    /// both. The board file is written straight after because a workspace is a folder
    /// *with a board* - the sidebar tree is built from `allBoards()`, so a folder created
    /// without one would not appear in the pane it was created from. Empty, so it holds
    /// exactly what `load(folder:)` would have returned had the file stayed missing.
    private func createWorkspace(named name: String, in parent: String) {
        guard let root = vault.root else { return }
        flushBoard()
        do {
            let store = CanvasStore(root: root)
            let created = try store.createFolder(named: name, in: parent)
            try store.save(.empty, folder: created)
            workspace.open(folder: created)
            Task { await vault.rescan() }
        } catch {
            // The board is still usable and the name can be retried, so this is a line in
            // the problem list rather than a modal - the same treatment the "Cartella"
            // tool gives a rejected name.
            vault.recordProblem("nuova workspace: \(error)")
        }
    }

    /// Renames the folder and keeps the open board on it (R-05, R-08).
    private func renameWorkspace(_ folder: String, to newName: String) {
        flushBoard()
        guard vault.renameFolder(at: folder, to: newName) else { return }
        // "Keeps the open board on it" only means something if a board is actually
        // open - with nothing chosen there is nothing to land somewhere else.
        guard workspace.hasOpenBoard else { return }

        // The destination `FolderFileOperations.renamePlan` computed for itself: a rename
        // is a new last component under the same parent, never a move (SPEC, out of scope).
        let parent = (folder as NSString).deletingLastPathComponent
        let newPath = parent.isEmpty ? newName : "\(parent)/\(newName)"
        let landing = WorkspaceFolderActions.folderAfterRename(
            open: workspace.folder, renamed: folder, to: newPath
        )
        guard landing != workspace.folder else { return }
        // Reopened rather than renamed in place: the document on screen was read from a
        // file that has moved, and `open(folder:)` is what re-reads it, refreshes the
        // folder's contents and redraws the breadcrumb from `workspace.folder`.
        workspace.open(folder: landing)
    }

    /// Trashes the folder and lands on its parent when what went was underfoot (R-11, R-12).
    ///
    /// The confirmation happened in the browser, which is where the counts are; by the
    /// time this runs the question has been answered.
    private func deleteWorkspace(_ folder: String) {
        flushBoard()
        guard vault.trashFolder(at: folder) else { return }
        guard workspace.hasOpenBoard else { return }

        let landing = WorkspaceFolderActions.folderAfterDelete(
            open: workspace.folder, deleted: folder
        )
        guard landing != workspace.folder else { return }
        workspace.open(folder: landing)
    }

    /// Everything the board still owes the disk, written now.
    ///
    /// The crop is ended before the flush rather than left to `open(folder:)`, which ends
    /// it on the way out (ADR-0020 §D5): confirming a crop is a `mutate`, and a `mutate`
    /// after the folder has moved is a write to a path that is no longer there - the
    /// autosave problem of §F10 arriving through the other door. Ended here, its write
    /// goes to the folder that still exists.
    private func flushBoard() {
        workspace.endCrop(confirm: true)
        workspace.flushPendingSave()
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

            // The same state the Vista menu's «Pannello Workspace» drives, now that it
            // lives on `Navigation`: one toggle, two places to reach it.
            // Label left as it was: `UITests/SectionToolbarsUITests.swift:132` finds this
            // toggle by its words, and renaming it to match the menu entry would break a
            // suite this task does not own. The identifier below is what a new test uses.
            Toggle(isOn: Bindable(navigation).isShowingTray) {
                Label("Nuovi elementi", systemImage: "tray")
            }
            .help("Nuovi elementi, task collegati e assegnati, note referenziate")
            .accessibilityIdentifier("workspace-tray-toggle")

            // Hides the app sidebar, the board list and the tray, leaving only the
            // tool column and the board. Same reach pattern as the tray toggle above:
            // one piece of state on `Navigation`, a toolbar toggle and a Vista entry.
            Toggle(isOn: Bindable(navigation).isWorkspaceFocused) {
                Label("Concentrazione", systemImage: "rectangle.expand.vertical")
            }
            .help("Nasconde la sidebar, l'elenco board e il tray per lasciare più spazio alla board")
            .accessibilityIdentifier("workspace-focus-toggle")
        }
    }

    // MARK: Board

    private var board: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                theme.color(.canvasBackground)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        // A click outside the card confirms an open crop (ADR-0020 D5)
                        // rather than acting on whatever tool is selected.
                        if workspace.croppingNodeID != nil {
                            workspace.endCrop(confirm: true)
                        } else {
                            handleTap(at: canvasPoint(from: location, in: geometry.size))
                        }
                    }
                    // Attached to the background alone. On the whole board it also
                    // fired while a card was being dragged, and the two gestures moved
                    // the same content against each other.
                    .gesture(backgroundGesture(in: geometry.size))

                // Esc cancels an open crop, Enter confirms it (ADR-0020 D5). Hidden
                // buttons rather than an `onKeyPress`: the board hosts no first
                // responder of its own, and a keyboard shortcut on a button reaches the
                // window regardless of what has focus, the same way Annulla/Ripeti do
                // in the toolbar above.
                if workspace.croppingNodeID != nil {
                    Button("") { workspace.endCrop(confirm: false) }
                        .keyboardShortcut(.escape, modifiers: [])
                        .hidden()
                    Button("") { workspace.endCrop(confirm: true) }
                        .keyboardShortcut(.return, modifiers: [])
                        .hidden()
                }

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
                    // Above the pen row, so the zoom controls stay where a person has
                    // learned to find them when the bar appears and disappears with the
                    // selection (ADR-0023 §D7).
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
            .onChange(of: geometry.size) { _, size in
                viewportSize = size
                guard needsActualSizeZoom || needsRefit else { return }
                let actualSize = needsActualSizeZoom
                pendingFitTask?.cancel()
                pendingFitTask = Task {
                    // Long enough to land after the columnVisibility animation's last
                    // intermediate frame, short enough that the fit still reads as
                    // immediate once the panels stop moving.
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    if actualSize {
                        workspace.zoomToActualSize(in: size)
                    } else {
                        workspace.zoomToFit(in: size)
                    }
                    needsActualSizeZoom = false
                    needsRefit = false
                }
            }
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
