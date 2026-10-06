import SwiftUI

/// The Workspace: a spatial view of one folder, with the board hierarchy above it.
///
/// Split across six files along the seams the `// MARK:` comments already marked -
/// this one keeps the view's state and its body, while the board itself, the drawing
/// overlay, the sidebar's folder verbs, item creation and the toolbar live in
/// `WorkspaceView+Board`, `WorkspaceView+Drawing`, `WorkspaceView+FolderVerbs`,
/// `WorkspaceView+Creation` and `WorkspaceView+Toolbar`. A member read by one of those
/// extensions is internal rather than `private` for that reason alone: `private` is file
/// scope, so an extension in another file cannot see it.
struct WorkspaceView: View {
    @Environment(\.theme) var theme
    @Environment(VaultController.self) var vault
    // Internal rather than `private`: `WorkspaceView+Toolbar` is another file, and
    // `private` is file scope.
    @Environment(Navigation.self) var navigation
    @Environment(ThemeEngine.self) var themeEngine
    /// «Apri» on the «Documento» sheet's confirmation goes through `showInNotePane`
    /// (`WorkspaceView+Creation`, note-workflow R-05). Optional because it is read only there, on
    /// a press, and a hosted test builds this view without it.
    @Environment(CommandActions.self) var commandActions: CommandActions?
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
    // Not `private`, on this property and the two below: the board that writes and reads
    // them is in `WorkspaceView+Board.swift`, and `private` is file scope. `viewportSize` is
    // also read here, by `openPendingCanvas()`.
    @State var viewportSize: CGSize = .zero
    /// Shift and Option as they are held right now. `DragGesture` carries no modifier
    /// information, so the board has to track them itself to tell a marquee from a
    /// pan and a free resize from a proportional one.
    @State var modifiers: EventModifiers = []
    /// The zoom a pinch started from, so the magnification is applied to it once
    /// rather than compounding on every frame of the gesture.
    @State var pinchOrigin: CGFloat?
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
                    // exactly the write already refused, on the same stale expectation
                    // (ADR-0054 §D5). `detach()` reports the loss only when the vault itself
                    // changes; a pane switch or a window close drops the conflicted board's
                    // edits with no problem line, because this view's controller goes with it
                    // (ADR-0089 §D7).
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
                // directly. `""` is "nothing open" on the controller
                // (`WorkspaceController.board`); `nil` is the same on
                // `VaultController.openBoardPath`.
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
                .font(theme.font(.iconDisplay))
                .foregroundStyle(theme.color(.textTertiary))
            Text("Nessuna board aperta").themedText(.body, color: .textSecondary)
                .accessibilityIdentifier("workspace-empty")
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
}
