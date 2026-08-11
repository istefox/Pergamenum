import CoreGraphics
import Foundation
import Observation

/// Drives one Workspace board: which folder it shows, what is on it, what is
/// selected, and when it is written back.
///
/// Terminology follows SPEC §6: the view is the **Workspace**, "canvas" is only the
/// name of the file format.
@MainActor
@Observable
final class WorkspaceController {
    /// The eleven tools of SPEC §6.4. `forms` is excluded from v1 and kept only so
    /// the toolbar layout does not have to be redone in v2.
    enum Tool: String, CaseIterable, Identifiable, Sendable {
        case select, note, text, folder, image, document, link, todo, forms, drawing, arrow

        var id: String { rawValue }

        var isAvailable: Bool { self != .forms }

        /// Single-key shortcut. Tools without one are not reachable from the keyboard.
        var shortcut: String? {
            switch self {
            case .select: "v"
            case .note: "n"
            case .text: "t"
            case .folder: "f"
            case .image: "i"
            case .document: "d"
            case .link: "l"
            case .todo: "k"
            case .drawing: "p"
            case .arrow: "a"
            case .forms: nil
            }
        }

        var title: String {
            switch self {
            case .select: "Seleziona"
            case .note: "Nota"
            case .text: "Testo"
            case .folder: "Cartella"
            case .image: "Immagine"
            case .document: "Documento"
            case .link: "Link"
            case .todo: "To Do"
            case .forms: "Moduli (v2)"
            case .drawing: "Disegno"
            case .arrow: "Freccia"
            }
        }

        var symbol: String {
            switch self {
            case .select: "cursorarrow"
            case .note: "note.text"
            case .text: "textformat"
            case .folder: "folder"
            case .image: "photo"
            case .document: "doc.text"
            case .link: "link"
            case .todo: "checklist"
            case .forms: "rectangle.on.rectangle.slash"
            case .drawing: "pencil.tip"
            case .arrow: "arrow.up.right"
            }
        }
    }

    /// Zoom bounds from SPEC §6.1.
    static let zoomRange: ClosedRange<CGFloat> = 0.05...4.0

    private(set) var folder = ""
    private(set) var document = CanvasDocument.empty
    private(set) var contents = CanvasStore.FolderContents(subfolders: [], unplaced: [])
    private(set) var problems: [String] = []

    var tool: Tool = .select
    /// True when a tool stays active after one use (double click on the tool).
    var isToolLocked = false
    var selection: Set<String> = []
    var zoom: CGFloat = 1
    var pan: CGSize = .zero

    /// Whether the board has changes not yet on disk. Shown as the "Salvato"
    /// indicator of §6.1.
    private(set) var hasUnsavedChanges = false

    private var store: CanvasStore?
    /// Renders and caches card previews. Lives here rather than in the view so a
    /// board reopened after navigation reuses the same in-memory renders.
    private(set) var thumbnails: ThumbnailStore?
    /// Header lines for `.eml` cards, keyed by vault path. Parsed once per file.
    private(set) var emailHeaders: [String: EmailHeaders] = [:]
    private var saveTask: Task<Void, Never>?
    /// Autosave delay of SPEC §6.1.
    private let autosaveDelay = Duration.seconds(1)

    /// Hashes written by this controller, for the vault watcher to recognise as its
    /// own rather than reloading the board under the user (ADR-0001 §D3).
    private(set) var lastWrittenHash: [String: String] = [:]

    // MARK: Navigation

    func attach(to store: CanvasStore) {
        self.store = store
        thumbnails = ThumbnailStore(root: store.root)
        open(folder: "")
    }

    func detach() {
        saveTask?.cancel()
        saveTask = nil
        store = nil
        thumbnails = nil
        emailHeaders = [:]
        document = .empty
        contents = .init(subfolders: [], unplaced: [])
        folder = ""
        selection = []
    }

    /// The breadcrumb of SPEC §6.1: each segment is a folder the user can jump to.
    var breadcrumb: [(title: String, folder: String)] {
        var trail: [(String, String)] = [("Workspace", "")]
        var accumulated = ""
        for component in folder.split(separator: "/") {
            accumulated = accumulated.isEmpty ? String(component) : "\(accumulated)/\(component)"
            trail.append((String(component), accumulated))
        }
        return trail
    }

    func open(folder newFolder: String) {
        guard let store else { return }
        // Leaving a board with pending edits must not lose them.
        flushPendingSave()

        folder = newFolder
        selection = []
        pan = .zero
        zoom = 1
        do {
            document = try store.load(folder: newFolder)
        } catch {
            document = .empty
            problems.append("\(newFolder): \(error)")
        }
        refreshContents()
        hasUnsavedChanges = false
    }

    /// Records a problem for the UI to show. Used where a failure should not stop the
    /// board being usable: a rejected folder name can simply be retyped.
    func recordProblem(_ message: String) {
        problems.append(message)
    }

    func refreshContents() {
        guard let store else { return }
        contents = store.contents(ofFolder: folder, board: document)
    }

    // MARK: Editing

    /// Applies a change and schedules the write. Every mutation goes through here so
    /// no path can edit the board and forget to save it.
    private func mutate(_ change: (inout CanvasDocument) -> Void) {
        change(&document)
        hasUnsavedChanges = true
        scheduleSave()
    }

    func move(nodeIDs: Set<String>, by delta: CGSize) {
        guard !delta.width.isZero || !delta.height.isZero else { return }
        mutate { document in
            for index in document.nodes.indices where nodeIDs.contains(document.nodes[index].id) {
                document.nodes[index].x += delta.width
                document.nodes[index].y += delta.height
            }
        }
    }

    func resize(nodeID: String, to size: CGSize) {
        // A node with zero or negative extent cannot be grabbed again, so the minimum
        // is a floor rather than a preference.
        let width = max(40, size.width)
        let height = max(30, size.height)
        mutate { document in
            guard let index = document.nodes.firstIndex(where: { $0.id == nodeID }) else { return }
            document.nodes[index].width = width
            document.nodes[index].height = height
        }
    }

    func setColor(_ color: CanvasColor?, forNodeIDs ids: Set<String>) {
        mutate { document in
            for index in document.nodes.indices where ids.contains(document.nodes[index].id) {
                document.nodes[index].color = color
            }
        }
    }

    func setText(_ text: String, forNodeID id: String) {
        mutate { document in
            guard let index = document.nodes.firstIndex(where: { $0.id == id }) else { return }
            if case .text = document.nodes[index].kind {
                document.nodes[index].kind = .text(text)
            }
        }
    }

    func delete(nodeIDs: Set<String>) {
        mutate { document in
            document.nodes.removeAll { nodeIDs.contains($0.id) }
            // An edge to a node that no longer exists is unrenderable and would be
            // rejected by a strict reader.
            document.edges.removeAll { nodeIDs.contains($0.fromNode) || nodeIDs.contains($0.toNode) }
        }
        selection.subtract(nodeIDs)
        refreshContents()
    }

    @discardableResult
    func addNode(_ node: CanvasNode) -> String {
        mutate { $0.nodes.append(node) }
        refreshContents()
        return node.id
    }

    @discardableResult
    func connect(from: String, to: String) -> String? {
        guard from != to, document.node(id: from) != nil, document.node(id: to) != nil else { return nil }
        let edge = CanvasEdge(id: CanvasID.generate(), fromNode: from, toNode: to, toEnd: .arrow)
        mutate { $0.edges.append(edge) }
        return edge.id
    }

    /// Places an existing vault file on the board, which is how an item leaves the
    /// "Nuovi elementi" tray.
    @discardableResult
    func placeFile(_ relativePath: String, at point: CGPoint) -> String {
        addNode(CanvasNode(
            id: CanvasID.generate(),
            kind: .file(path: relativePath, subpath: nil),
            x: point.x, y: point.y,
            width: 260, height: 180
        ))
    }

    func addStickyNote(_ text: String, at point: CGPoint, color: CanvasColor? = .preset(3)) -> String {
        addNode(CanvasNode(
            id: CanvasID.generate(),
            kind: .text(text),
            x: point.x, y: point.y,
            width: 220, height: 120,
            color: color
        ))
    }

    func addFreeText(_ text: String, at point: CGPoint) -> String {
        // No colour: SPEC §6.4 tool 3 is text without a background.
        addNode(CanvasNode(
            id: CanvasID.generate(),
            kind: .text(text),
            x: point.x, y: point.y,
            width: 220, height: 60
        ))
    }

    func addLink(_ url: String, at point: CGPoint) -> String {
        addNode(CanvasNode(
            id: CanvasID.generate(),
            kind: .link(url: url),
            x: point.x, y: point.y,
            width: 260, height: 90
        ))
    }

    /// Creates a real directory and puts its card on the board (SPEC §6.4, tool 4).
    @discardableResult
    func createFolder(named name: String, at point: CGPoint) throws -> String {
        guard let store else { throw CanvasStore.StoreError.alreadyExists("nessun vault aperto") }
        let relativePath = try store.createFolder(named: name, in: folder)
        let id = placeFile(relativePath, at: point)
        refreshContents()
        return id
    }

    /// Absolute URL of the file a node points at, when it points at one.
    func fileURL(for node: CanvasNode) -> URL? {
        guard let store, case .file(let path, _) = node.kind else { return nil }
        return store.root.appending(path: path, directoryHint: .notDirectory)
    }

    /// URLs of the selected file cards, for the Quick Look panel (SPEC §6.6).
    var selectedFileURLs: [URL] {
        document.nodes
            .filter { selection.contains($0.id) }
            .compactMap { node in
                // A folder card previews as a folder, which Quick Look renders as an
                // icon; the file cards are what the panel is useful for.
                subfolder(for: node) == nil ? fileURL(for: node) : nil
            }
            .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    /// Reads and memoises the headers of an `.eml` card.
    ///
    /// Only the header block is read (SPEC §14 excludes body rendering), so this stays
    /// cheap even for a message with a large attachment.
    func loadEmailHeaders(for relativePath: String) {
        guard let store, emailHeaders[relativePath] == nil else { return }
        let fileURL = store.root.appending(path: relativePath, directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: fileURL) else { return }

        // Latin-1 as the fallback: an .eml whose headers are not UTF-8 still has
        // readable ASCII field names, and refusing the file would leave the card blank.
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        emailHeaders[relativePath] = EmailHeaderParser.parse(text)
    }

    /// The folder a card points at, when it points at one.
    func subfolder(for node: CanvasNode) -> String? {
        guard case .file(let path, _) = node.kind else { return nil }
        return contents.subfolders.contains(path) ? path : nil
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [autosaveDelay] in
            try? await Task.sleep(for: autosaveDelay)
            guard !Task.isCancelled else { return }
            save()
        }
    }

    /// Writes now, cancelling any pending debounce. Called when leaving a board or
    /// closing the vault, where waiting out the delay would lose the edit.
    func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        if hasUnsavedChanges { save() }
    }

    private func save() {
        guard let store, hasUnsavedChanges else { return }
        do {
            let hash = try store.save(document, folder: folder)
            lastWrittenHash[store.boardPath(forFolder: folder)] = hash
            hasUnsavedChanges = false
        } catch {
            // Left dirty on purpose: an indicator still showing unsaved changes is
            // the truth, and the next edit will retry.
            problems.append("salvataggio di \(folder): \(error)")
        }
    }

    // MARK: Viewport

    func zoom(by factor: CGFloat) {
        zoom = min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
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
