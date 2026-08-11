import SwiftUI

/// The Workspace: a spatial view of one folder, with the board hierarchy above it.
struct WorkspaceView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @State private var workspace = WorkspaceController()
    @State private var viewportSize: CGSize = .zero
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
            topBar
            Divider()
            HStack(spacing: 0) {
                toolbar
                Divider()
                board
                if isShowingTray, !workspace.contents.unplaced.isEmpty {
                    Divider()
                    tray
                }
            }
        }
        .background(theme.color(.backgroundPrimary))
        .quickLook(urls: workspace.selectedFileURLs, isPresented: $isShowingQuickLook)
        .onChange(of: vault.isShowingQuickLook) { _, requested in
            guard requested else { return }
            isShowingQuickLook = true
            vault.isShowingQuickLook = false
        }
        .onAppear {
            if let root = vault.root { workspace.attach(to: CanvasStore(root: root)) }
        }
        .onDisappear { workspace.flushPendingSave() }
        .onChange(of: vault.root) { _, newRoot in
            workspace.detach()
            if let newRoot { workspace.attach(to: CanvasStore(root: newRoot)) }
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

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Circle()
                .fill(theme.color(workspace.hasUnsavedChanges ? .taskScheduled : .accentPrimary))
                .frame(width: 8, height: 8)

            ForEach(Array(workspace.breadcrumb.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Text("›").themedText(.body, color: .textTertiary)
                }
                Button(crumb.title) { workspace.open(folder: crumb.folder) }
                    .buttonStyle(.plain)
                    .themedText(
                        .body,
                        color: index == workspace.breadcrumb.count - 1 ? .textPrimary : .textSecondary
                    )
            }

            Spacer()

            Label(
                workspace.hasUnsavedChanges ? "Salvataggio…" : "Salvato",
                systemImage: workspace.hasUnsavedChanges ? "arrow.triangle.2.circlepath" : "checkmark.circle"
            )
            .themedText(.caption, color: .textSecondary)

            Button {
                isShowingQuickLook = true
            } label: {
                Label("Anteprima", systemImage: "eye")
            }
            .buttonStyle(.plain)
            .themedText(.caption, color: .textSecondary)
            .disabled(workspace.selectedFileURLs.isEmpty)
            .help("Anteprima rapida del file selezionato (barra spaziatrice)")

            Button {
                isShowingTray.toggle()
            } label: {
                Label("Nuovi elementi", systemImage: "tray")
            }
            .buttonStyle(.plain)
            .themedText(.caption, color: .textSecondary)
            .help("Elementi della cartella non ancora posati sulla board")
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.vertical, theme.spacing(.s))
    }

    // MARK: Toolbar

    private var toolbar: some View {
        VStack(spacing: theme.spacing(.xs)) {
            ForEach(WorkspaceController.Tool.allCases) { tool in
                Button {
                    workspace.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 30, height: 30)
                        .foregroundStyle(theme.color(
                            tool == workspace.tool ? .onAccent : (tool.isAvailable ? .textSecondary : .textTertiary)
                        ))
                        .background(tool == workspace.tool ? theme.color(.accentPrimary) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!tool.isAvailable)
                .opacity(tool.isAvailable ? 1 : 0.4)
                .help(tool.shortcut.map { "\(tool.title) (\($0.uppercased()))" } ?? tool.title)
                .keyboardShortcut(tool.shortcut.map { KeyEquivalent(Character($0)) } ?? "\0", modifiers: [])
            }
            Spacer()
        }
        .padding(theme.spacing(.xs))
        .frame(width: 44)
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
                    // Pan is attached to the background alone. On the whole board it
                    // also fired while a card was being dragged, and the two gestures
                    // moved the same content against each other.
                    .gesture(panGesture)

                grid

                ZStack(alignment: .topLeading) {
                    ForEach(workspace.document.edges) { edge in
                        edgeShape(edge)
                    }
                    ForEach(workspace.document.nodes) { node in
                        nodeView(node)
                    }
                }
                // Scales from the top-left and then offsets, so a board point p
                // lands at p * zoom + pan. Anchoring at the centre instead would make
                // the pan depend on the viewport size and the two would fight.
                .scaleEffect(workspace.zoom, anchor: .topLeading)
                .offset(workspace.pan)

                if workspace.tool == .drawing || !workspace.activeDrawing.strokes.isEmpty {
                    drawingLayer(in: geometry.size)
                }

                VStack(alignment: .trailing, spacing: theme.spacing(.xs)) {
                    if workspace.tool == .drawing { penControls }
                    zoomControls
                }
                .padding(theme.spacing(.m))
            }
            .clipped()
            .dropDestination(for: URL.self) { urls, location in
                importProposals = workspace.importFiles(
                    urls, at: canvasPoint(from: location, in: geometry.size)
                )
                return !importProposals.isEmpty
            }
            .onAppear {
                viewportSize = geometry.size
                workspace.zoomToFit(in: geometry.size)
            }
            .onChange(of: geometry.size) { _, size in viewportSize = size }
            .onChange(of: workspace.folder) { _, _ in
                // A board opens over its content, not over the origin.
                workspace.zoomToFit(in: viewportSize)
            }
        }
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

    private var zoomControls: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Button { workspace.zoom(by: 1 / 1.25) } label: { Image(systemName: "minus") }
            Button { workspace.resetZoom() } label: {
                Text("\(Int(workspace.zoom * 100))%").themedText(.caption)
            }
            Button { workspace.zoom(by: 1.25) } label: { Image(systemName: "plus") }
            Divider().frame(height: 12)
            Button { workspace.zoomToFit(in: viewportSize) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.color(.textSecondary))
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .background(theme.color(.surfaceRaised))
        .clipShape(Capsule())
        .themedShadow(.card)
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

    private var penControls: some View {
        HStack(spacing: theme.spacing(.xs)) {
            ForEach([ColorToken.textPrimary, .accentPrimary, .taskOverdue, .stickyYellow], id: \.self) { token in
                Circle()
                    .fill(theme.color(token))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle().strokeBorder(
                            token == penColor ? theme.color(.canvasSelection) : theme.color(.borderSubtle),
                            lineWidth: token == penColor ? 2 : 1
                        )
                    )
                    .onTapGesture { penColor = token; isErasing = false }
            }
            Divider().frame(height: 14)
            ForEach([CGFloat(2), 6, 14], id: \.self) { width in
                Circle()
                    .fill(theme.color(width == penWidth && !isErasing ? .accentPrimary : .textTertiary))
                    .frame(width: width + 4, height: width + 4)
                    .onTapGesture { penWidth = width; isErasing = false }
            }
            Divider().frame(height: 14)
            Image(systemName: "eraser")
                .foregroundStyle(theme.color(isErasing ? .accentPrimary : .textSecondary))
                .onTapGesture { isErasing.toggle() }
            Divider().frame(height: 14)
            Button("Fatto") {
                _ = workspace.commitDrawing()
                workspace.tool = .select
            }
            .buttonStyle(.plain)
            .themedText(.caption, color: .accentPrimary)
            .disabled(workspace.activeDrawing.strokes.isEmpty)
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .background(theme.color(.surfaceRaised))
        .clipShape(Capsule())
        .themedShadow(.card)
    }

    /// Board point to view point, the forward direction of `canvasPoint`.
    private func viewPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * workspace.zoom + workspace.pan.width,
            y: point.y * workspace.zoom + workspace.pan.height
        )
    }

    // MARK: Edges

    /// Draws a connector between two nodes.
    ///
    /// The endpoints are computed from the nodes' current frames rather than stored,
    /// which is what makes the connector stay attached when a card moves (SPEC §6.4,
    /// tool 11) without writing the file on every drag frame.
    @ViewBuilder
    private func edgeShape(_ edge: CanvasEdge) -> some View {
        if let from = workspace.document.node(id: edge.fromNode),
           let to = workspace.document.node(id: edge.toNode) {
            let start = anchor(of: from, facing: to, side: edge.fromSide)
            let end = anchor(of: to, facing: from, side: edge.toSide)

            ZStack {
                Path { path in
                    path.move(to: start)
                    path.addLine(to: end)
                }
                .stroke(theme.color(.borderStrong), lineWidth: 1.5)

                // The spec's default for `toEnd` is `arrow`, so an absent value means
                // an arrow, not the absence of one.
                if (edge.toEnd ?? .arrow) == .arrow {
                    arrowHead(at: end, from: start)
                }
                if let label = edge.label {
                    Text(label)
                        .themedText(.caption, color: .textSecondary)
                        .padding(.horizontal, 4)
                        .background(theme.color(.canvasBackground))
                        .position(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                }
            }
        }
    }

    /// The point on a node's edge that faces another node. An explicit side from the
    /// file wins; otherwise the side is chosen from the relative position, which is
    /// what keeps a connector sensible after either card is dragged.
    private func anchor(of node: CanvasNode, facing other: CanvasNode, side: CanvasEdge.Side?) -> CGPoint {
        let frame = node.frame
        let resolved: CanvasEdge.Side = side ?? {
            let dx = other.frame.midX - frame.midX
            let dy = other.frame.midY - frame.midY
            if abs(dx) > abs(dy) { return dx > 0 ? .right : .left }
            return dy > 0 ? .bottom : .top
        }()

        return switch resolved {
        case .top: CGPoint(x: frame.midX, y: frame.minY)
        case .bottom: CGPoint(x: frame.midX, y: frame.maxY)
        case .left: CGPoint(x: frame.minX, y: frame.midY)
        case .right: CGPoint(x: frame.maxX, y: frame.midY)
        }
    }

    private func arrowHead(at point: CGPoint, from origin: CGPoint) -> some View {
        let angle = atan2(point.y - origin.y, point.x - origin.x)
        let length: CGFloat = 10
        let spread: CGFloat = .pi / 7

        return Path { path in
            path.move(to: point)
            path.addLine(to: CGPoint(
                x: point.x - length * cos(angle - spread),
                y: point.y - length * sin(angle - spread)
            ))
            path.move(to: point)
            path.addLine(to: CGPoint(
                x: point.x - length * cos(angle + spread),
                y: point.y - length * sin(angle + spread)
            ))
        }
        .stroke(theme.color(.borderStrong), lineWidth: 1.5)
    }

    // MARK: Nodes

    @ViewBuilder
    private func nodeView(_ node: CanvasNode) -> some View {
        let isSelected = workspace.selection.contains(node.id)

        // Gestures are attached BEFORE `.position`, which is load-bearing: `.position`
        // expands its result to fill the parent, so anything added after it responds
        // across the whole board instead of over the card. With them after, no card
        // could be selected at all.
        NodeCard(node: node, subfolder: workspace.subfolder(for: node), workspace: workspace)
            .frame(width: node.width, height: node.height)
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                    .strokeBorder(
                        isSelected ? theme.color(.canvasSelection) : .clear,
                        lineWidth: 2
                    )
            )
            .overlay(alignment: .bottomTrailing) {
                if isSelected { resizeHandle(node) }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { open(node) }
            .onTapGesture { workspace.selection = [node.id] }
            .gesture(
                // `.global`, not a named space: a named space that fails to resolve falls back
                // to `.local`, which sits inside the board's `scaleEffect`, so a 100-point
                // mouse move was reported as 170 units and then divided by the zoom again.
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { value in
                        // Selecting on drag start keeps a drag of an unselected card
                        // from moving whatever was selected before.
                        if !workspace.isDragging {
                            if !workspace.selection.contains(node.id) {
                                workspace.selection = [node.id]
                            }
                            workspace.beginDrag(nodeIDs: workspace.selection)
                        }
                        // Screen translation to board units: at 58% zoom a 100-point
                        // drag is 172 board units, not 100.
                        workspace.updateDrag(translation: CGSize(
                            width: value.translation.width / workspace.zoom,
                            height: value.translation.height / workspace.zoom
                        ))
                    }
                    .onEnded { _ in workspace.endDrag() }
            )
            .position(x: node.x + node.width / 2, y: node.y + node.height / 2)
            // Visual feedback for the drag. Safe now that the gesture measures in
            // `.global`: moving the view no longer moves the space it is measured in.
            .offset(workspace.dragOffsetInPoints(for: node.id))
    }

    private func resizeHandle(_ node: CanvasNode) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(theme.color(.canvasSelection))
            .frame(width: 10, height: 10)
            .offset(x: 4, y: 4)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        workspace.resize(nodeID: node.id, to: CGSize(
                            width: node.width + value.translation.width / workspace.zoom,
                            height: node.height + value.translation.height / workspace.zoom
                        ))
                    }
            )
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
        if !workspace.isToolLocked { workspace.tool = .select }
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
                _ = workspace.placeFile(path, at: point)
            } catch {
                workspace.recordProblem(ConformanceText.creationFailure(error))
            }
        case .text:
            _ = workspace.addFreeText(value, at: point)
        }
    }

    // MARK: New items tray

    private var tray: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("NUOVI ELEMENTI").themedText(.caption, color: .textTertiary)
            Text("Trascina o clicca per posare sulla board.")
                .themedText(.caption, color: .textTertiary)

            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                    ForEach(workspace.contents.unplaced, id: \.self) { path in
                        Button {
                            _ = workspace.placeFile(path, at: CGPoint(x: 60, y: 60))
                        } label: {
                            HStack(spacing: theme.spacing(.xs)) {
                                Image(systemName: workspace.contents.subfolders.contains(path)
                                      ? "folder" : "doc")
                                Text((path as NSString).lastPathComponent)
                                    .themedText(.caption)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
        }
        .padding(theme.spacing(.s))
        .frame(width: 200)
        .background(theme.color(.backgroundSecondary))
    }
}

/// One card on the board, drawn by node kind.
private struct NodeCard: View {
    @Environment(\.theme) private var theme
    let node: CanvasNode
    let subfolder: String?
    let workspace: WorkspaceController

    var body: some View {
        switch node.kind {
        case .text(let text):
            stickyOrText(text)
        case .file(let path, _):
            fileCard(path)
        case .link(let url):
            linkCard(url)
        case .group(let label):
            groupCard(label)
        case .unknown(let type):
            // Drawn as a placeholder rather than skipped, so a node from another tool
            // is visible and movable instead of silently invisible.
            placeholder("nodo «\(type)»")
        }
    }

    @ViewBuilder
    private func stickyOrText(_ text: String) -> some View {
        if let color = node.color {
            Text(text.isEmpty ? "Nota" : text)
                .themedText(.body)
                .padding(theme.spacing(.s))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(stickyColor(color))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.sticky), style: .continuous))
                .themedShadow(.card)
        } else {
            Text(text.isEmpty ? "Testo" : text)
                .themedText(.heading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Maps the six JSON Canvas presets onto theme tokens so a canvas made in
    /// Obsidian keeps its colour coding here, in this app's palette.
    private func stickyColor(_ color: CanvasColor) -> Color {
        switch color {
        case .hex(let value):
            let rgba = RGBA(hex: value) ?? RGBA(hex: "#E8E5DF")!
            return Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
        case .preset(let index):
            return switch index {
            case 1: theme.color(.stickyPink)
            case 2: theme.color(.stickyPink)
            case 3: theme.color(.stickyYellow)
            case 4: theme.color(.stickyGreen)
            case 5: theme.color(.stickyBlue)
            default: theme.color(.stickyGrey)
            }
        }
    }

    @ViewBuilder
    private func fileCard(_ path: String) -> some View {
        if subfolder != nil {
            folderCard(path)
        } else if (path as NSString).pathExtension.lowercased() == "eml" {
            emailCard(path)
        } else {
            previewCard(path)
        }
    }

    private func folderCard(_ path: String) -> some View {
        cardChrome {
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                HStack(spacing: theme.spacing(.xs)) {
                    Image(systemName: "folder.fill").foregroundStyle(theme.color(.accentPrimary))
                    Text((path as NSString).lastPathComponent).themedText(.body).lineLimit(2)
                }
                Text("cartella").themedText(.caption, color: .textTertiary)
                Spacer(minLength: 0)
            }
        }
    }

    /// A PDF, an image or any other file, shown with its Quick Look preview.
    ///
    /// SPEC §6.5 makes the PDF card a primary requirement: the first page rendered by
    /// PDFKit, cached, and regenerated at the new resolution when the card is resized.
    private func previewCard(_ path: String) -> some View {
        cardChrome {
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                ThumbnailImage(
                    workspace: workspace,
                    relativePath: path,
                    width: node.width,
                    fallbackSymbol: symbol(for: path)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                HStack {
                    Text((path as NSString).lastPathComponent)
                        .themedText(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text((path as NSString).pathExtension.uppercased())
                        .themedText(.caption, color: .textTertiary)
                }
            }
        }
    }

    /// From / Subject / Date read from the header block, with no body rendering
    /// (SPEC §6.5 and §14).
    private func emailCard(_ path: String) -> some View {
        let headers = workspace.emailHeaders[path]
        return cardChrome {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: theme.spacing(.xs)) {
                    Image(systemName: "envelope").foregroundStyle(theme.color(.accentPrimary))
                    Text(headers?.from?.displayText ?? (path as NSString).lastPathComponent)
                        .themedText(.body)
                        .lineLimit(1)
                }
                Text(headers?.subject ?? "—")
                    .themedText(.caption, color: .textSecondary)
                    .lineLimit(2)
                if let date = headers?.date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .themedText(.caption, color: .textTertiary)
                }
                Spacer(minLength: 0)
            }
            .task(id: path) { workspace.loadEmailHeaders(for: path) }
        }
    }

    private func cardChrome<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(theme.spacing(.s))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.color(.surfaceCard))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                    .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
            )
            .themedShadow(.card)
    }

    private func symbol(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "md": "doc.text"
        case "pdf": "doc.richtext"
        case "eml": "envelope"
        case "png", "jpg", "jpeg", "heic", "gif", "svg": "photo"
        case "canvas": "square.on.square"
        default: "doc"
        }
    }

    private func linkCard(_ url: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: theme.spacing(.xs)) {
                Image(systemName: symbol(forScheme: url))
                    .foregroundStyle(theme.color(.accentPrimary))
                Text(url).themedText(.body).lineLimit(1)
            }
            Text(URL(string: url)?.scheme.map { "\($0)://" } ?? "link")
                .themedText(.caption, color: .textTertiary)
            Spacer(minLength: 0)
        }
        .padding(theme.spacing(.s))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.color(.surfaceCard))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
        )
        .themedShadow(.card)
    }

    /// Schemes SPEC §9 singles out for their own icon.
    private func symbol(forScheme url: String) -> String {
        switch URL(string: url)?.scheme {
        case "obsidian": "circle.hexagongrid"
        case "x-devonthink-item": "square.stack.3d.up"
        case "message": "envelope"
        case "pergamenum": "scroll"
        default: "link"
        }
    }

    private func groupCard(_ label: String?) -> some View {
        RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
            .strokeBorder(theme.color(.borderStrong), lineWidth: 1)
            .overlay(alignment: .topLeading) {
                if let label {
                    Text(label)
                        .themedText(.caption, color: .textSecondary)
                        .padding(theme.spacing(.xs))
                }
            }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .themedText(.caption, color: .textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.color(.backgroundTertiary))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }
}

/// Names a new folder, link or note before it is created.
private struct NewCanvasItemSheet: View {
    enum Kind { case folder, link, note }

    @Environment(\.theme) private var theme
    let kind: Kind
    let onCancel: () -> Void
    let onConfirm: (String) -> Void

    @State private var value = ""

    private var title: String {
        switch kind {
        case .folder: "Nuova cartella"
        case .link: "Nuovo link"
        case .note: "Nuovo documento"
        }
    }

    private var prompt: String {
        switch kind {
        case .folder: "Nome della cartella"
        case .link: "URL o URI (https://, obsidian://, message://)"
        case .note: "Titolo della nota"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(title).themedText(.title)
            TextField(prompt, text: $value)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Annulla", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Crea") { onConfirm(value.trimmingCharacters(in: .whitespaces)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 460)
        .background(theme.color(.surfaceCard))
    }
}

/// Renders a file's thumbnail, falling back to its type icon while the render runs
/// or when the file has no preview at all.
private struct ThumbnailImage: View {
    @Environment(\.theme) private var theme
    let workspace: WorkspaceController
    let relativePath: String
    let width: CGFloat
    let fallbackSymbol: String

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(theme.color(.backgroundTertiary))
                    .overlay(
                        Image(systemName: fallbackSymbol)
                            .foregroundStyle(theme.color(.textTertiary))
                    )
            }
        }
        // Keyed on the size bucket rather than the raw width, so dragging a resize
        // handle does not start a render per frame (SPEC §6.5 asks for a regenerated
        // thumbnail at the end of a resize, not during it).
        .task(id: "\(relativePath)@\(ThumbnailStore.bucket(for: width))") {
            guard let store = workspace.thumbnails else { return }
            let task = await store.thumbnail(for: relativePath, width: width)
            let rendered = await task.value
            if !Task.isCancelled { image = rendered }
        }
    }
}


/// Confirms the names of files being imported, so the assisted rename of SPEC §4.2
/// is a proposal rather than something done behind the user's back.
private struct ImportSheet: View {
    @Environment(\.theme) private var theme
    @Binding var proposals: [WorkspaceController.ImportProposal]
    let onCancel: () -> Void
    let onConfirm: ([WorkspaceController.ImportProposal]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text(proposals.count == 1 ? "Importa file" : "Importa \(proposals.count) file")
                .themedText(.title)
            Text("Il nome proposto segue le convenzioni harness. Puoi modificarlo.")
                .themedText(.caption, color: .textSecondary)

            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                    ForEach($proposals) { $proposal in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(proposal.originalName)
                                .themedText(.caption, color: .textTertiary)
                            TextField("Nome file", text: $proposal.proposedName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
            .frame(maxHeight: 240)

            HStack {
                Spacer()
                Button("Annulla", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Importa") { onConfirm(proposals) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(theme.spacing(.l))
        .frame(width: 560)
        .background(theme.color(.surfaceCard))
    }
}
