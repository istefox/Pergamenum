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
    /// The single value that says both which row of the Workspace tree is lit and
    /// whether a board is drawn (ADR-0024 §D4). Replaces the former `hasOpenBoard`
    /// flag: `attach` prepares the root board's document the moment a vault opens, but
    /// that is readiness, not a choice, so `current` stays `nil` until something is
    /// actually selected.
    ///
    /// ADR-0024 Task 2 GREEN (coder): every write to `current` - `attach`'s `nil`,
    /// `open(folder:)`'s `.board(folder:)`, `select(_:)`'s dispatch, `detach`'s `nil`
    /// - is still a placeholder at this point in the task; see `select(_:)` below.
    private(set) var current: WorkspaceSelection?
    /// True only while a board is drawn, derived from `current` rather than stored
    /// separately (ADR-0024 §D4) - answering "is a board on screen" can never disagree
    /// with "which row is lit" because both read the same value.
    var isShowingBoard: Bool { if case .board = current { true } else { false } }
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

    /// Annulla/ripeti for this board (SPEC §6.1).
    private var history = BoardHistory()

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    var store: CanvasStore?

    /// Strokes being drawn right now, before they are written to their SVG, and the
    /// node whose SVG is being edited when a drawing was reopened (SPEC §6.2).
    ///
    /// Stored here because an extension cannot hold state; the drawing behaviour that
    /// uses them lives in `WorkspaceController+Drawing`.
    var activeDrawing = Drawing.empty
    var editingDrawingNodeID: String?
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

    /// `thumbnails` comes from the vault, which owns the cache. Nil is a board with no
    /// renderer: cards fall back to their symbols, which is what the tests exercise.
    func attach(to store: CanvasStore, thumbnails: ThumbnailStore? = nil) {
        self.store = store
        self.thumbnails = thumbnails
        // Loaded, not opened: the root board is ready the instant a vault attaches, but
        // that is not the same as the user having chosen it. `open(folder:)` still
        // does the loading; `current` is left as its default (`nil`) here rather than
        // explicitly reasserted, which is ADR-0024 Task 2's `attach`/`load(folder:)`
        // split - a placeholder for this task, left for the GREEN pass.
        open(folder: "")
    }

    func detach() {
        // A crop mode left open when the vault closes must not be silently lost
        // (ADR-0020 Consequences: "the board gains its first modal state").
        endCrop(confirm: true)
        saveTask?.cancel()
        saveTask = nil
        store = nil
        thumbnails = nil
        emailHeaders = [:]
        document = .empty
        contents = .init(subfolders: [], unplaced: [])
        folder = ""
        // ADR-0024 Task 2 GREEN (coder): `current = nil` belongs here, replacing the
        // removed `hasOpenBoard = false`. Left as a placeholder for this task - see
        // `Tests/WorkspaceOpenStateTests.swift`'s `detachClearsTheSelection`.
        selection = []
    }

    /// The breadcrumb of SPEC §6.1: each segment is a folder the user can jump to.
    ///
    /// ADR-0024 Task 2 GREEN (coder): this must walk `current?.folder ?? ""`, not
    /// `folder` - `folder` names the last *loaded* document, and a `.folder(F)`
    /// selection loads nothing, so the breadcrumb would keep showing the previous
    /// board's trail while the tree showed `F` selected (§D8.1). Left unchanged here as
    /// this task's placeholder; `Tests/WorkspaceOpenStateTests.swift`'s
    /// `breadcrumbFollowsTheSelectionNotTheLoadedDocument` is the assertion this is
    /// still failing.
    var breadcrumb: [(title: String, folder: String)] {
        var trail: [(String, String)] = [("Workspace", "")]
        var accumulated = ""
        for component in folder.split(separator: "/") {
            accumulated = accumulated.isEmpty ? String(component) : "\(accumulated)/\(component)"
            trail.append((String(component), accumulated))
        }
        return trail
    }

    /// Loads a folder's board. Every caller - a row click, the breadcrumb, a new
    /// board, a hand-off from the editor - means "this is now the selected board"
    /// (ADR-0024 §D4); `attach` is the one caller that wants the load without the
    /// selection, which is `WorkspaceController.attach`/`load(folder:)`'s split
    /// (ADR-0024 Task 2 GREEN, coder) - not yet done here, so `current` is not
    /// touched by this function at this point in the task.
    func open(folder newFolder: String) {
        guard let store else { return }
        // Navigating away confirms an open crop the same way a click outside the card
        // would (ADR-0020 D5), rather than silently discarding it.
        endCrop(confirm: true)
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
        // Each board has its own history: undoing on one board must never reach back
        // into a change made on another.
        history.reset()
    }

    /// Writes the tree's selection (ADR-0024 §D4), replacing the removed
    /// `closeBoard()`: `select(nil)` is what `closeBoard()` was, `select(.board(f))`
    /// is what a row click on a board does, `select(.folder(f))` is what a row click
    /// on a board-less folder does.
    ///
    /// ADR-0024 Task 2 GREEN (coder): the real dispatch - `guard new != current else
    /// { return }`, `.board(f)` → `open(folder: f)`, `.folder`/`nil` → `endCrop`,
    /// `flushPendingSave`, `selection = []`, `current = new` - is this task's
    /// placeholder. `Tests/WorkspaceOpenStateTests.swift` carries every assertion this
    /// still owes.
    func select(_ new: WorkspaceSelection?) {}

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
    func mutate(
        creatingOnDisk created: String? = nil,
        _ change: (inout CanvasDocument) -> Void
    ) {
        history.record(before: document, creatingOnDisk: created)
        change(&document)
        hasUnsavedChanges = true
        scheduleSave()
    }

    /// Steps back one change, or says why it will not.
    @discardableResult
    func undo() -> Bool {
        apply(history.undo(current: document))
    }

    @discardableResult
    func redo() -> Bool {
        apply(history.redo(current: document))
    }

    private func apply(_ outcome: BoardHistory.Outcome) -> Bool {
        switch outcome {
        case .restored(let restored):
            // The document just jumped to another point in history; an in-flight crop
            // draft measured against the old one is stale and must not be written over
            // whatever undo/redo just restored (ADR-0020 D5, Consequences).
            endCrop(confirm: false)
            document = restored
            // A card that no longer exists must not stay selected: the toolbar would
            // offer actions on nothing.
            selection = selection.filter { id in document.nodes.contains { $0.id == id } }
            hasUnsavedChanges = true
            scheduleSave()
            refreshContents()
            return true
        case .blocked(let name):
            recordProblem("«\(name)» è stata creata su disco: annullare toglierebbe la card e lascerebbe il file. Eliminalo dal Finder se non lo vuoi.")
            return false
        case .nothingToDo:
            return false
        }
    }

    /// Nodes being dragged right now, and how far, in board units.
    ///
    /// The model is NOT moved during the gesture. Moving it moves the view the
    /// gesture is attached to, SwiftUI re-anchors the gesture to the new position,
    /// and the translation feeds back into itself: one 100-point drag reported 48,
    /// 112, 262, 662, 1780, then 4965 points. The drag is therefore a transient
    /// offset the view draws with, committed once on release - which also turns
    /// twelve autosaves into one.
    /// Transient gesture state, written only by `WorkspaceController+Gestures` and
    /// read by the board. Internal rather than `private(set)` because that file is the
    /// one that owns it; what protects the model is that no gesture touches the
    /// document until it ends, not the access level of these.
    var draggingIDs: Set<String> = []
    var dragTranslation: CGSize = .zero

    var isDragging: Bool { !draggingIDs.isEmpty }

    /// The card the pointer is on, whose edges the alignment guides work from.
    var dragAnchorID: String?
    /// Guides to draw while a drag is in flight (SPEC §6.3).
    var activeGuides: [BoardGeometry.Guide] = []

    /// Whether the board draws a grid, and whether cards land on it. Both come from
    /// the vault settings (SPEC §12, "Canvas (griglia, snap)").
    var showsGrid = true
    var snapsToGrid = false
    /// The grid the board draws, and the one cards snap to when snapping is on. One
    /// constant for both: a card that landed on a spacing the user cannot see would
    /// look misaligned.
    static let gridStep: CGFloat = 24

    /// the drag translation.
    var panOrigin: CGSize?

    /// The marquee being dragged, in board units (SPEC §6.3).
    var marqueeStart: CGPoint?
    var marqueeRect: CGRect?



    func move(nodeIDs: Set<String>, by delta: CGSize) {
        guard !delta.width.isZero || !delta.height.isZero else { return }
        mutate { document in
            for index in document.nodes.indices where nodeIDs.contains(document.nodes[index].id) {
                document.nodes[index].x += delta.width
                document.nodes[index].y += delta.height
            }
        }
    }

    /// The card being resized, its grip, and the frame the drag has reached.
    ///
    /// Transient for the same reason the drag is: committing on every frame would
    /// write the file dozens of times and fill the undo stack with a step per frame,
    /// so Cmd+Z would undo one pixel of a resize.
    var resizingNodeID: String?
    var resizeHandle: BoardGeometry.Handle = .bottomRight
    var resizeOriginalFrame: CGRect = .zero
    var resizedFrame: CGRect?

    /// The card being cropped, transient like the resize above and for the same reason
    /// (ADR-0020 D5): a crop is written once, at `endCrop(confirm:)`, not per frame.
    /// `cropOriginal` and `cropDraft` are both in the drawn image's own point space, not
    /// the crop's stored fraction space - D5's own argument for why: a locked aspect
    /// ratio has to mean a literal square on screen, which only holds in points. Only
    /// `endCrop` converts to a normalised `CanvasCrop` before writing it.
    var croppingNodeID: String?
    var cropHandle: BoardGeometry.Handle = .bottomRight
    var cropOriginal: CGRect = .zero
    var cropDraft: CGRect?
    /// The image's drawn point size at `beginCrop`, needed to clamp the draft inside the
    /// picture and to normalise it back to a fraction at commit.
    var cropDrawnSize: CGSize = .zero

    /// The arrow being drawn with the Freccia tool (SPEC §6.4, tool 11): the card it
    /// started from and how far the pointer has travelled from there, in board units.
    ///
    /// Transient like the drag and the resize, and for the same reason: an edge is
    /// written once, on release, not on every frame of the gesture.
    var arrowSourceID: String?
    var arrowTranslation: CGSize = .zero

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
    func addNode(_ node: CanvasNode, creatingOnDisk created: String? = nil) -> String {
        mutate(creatingOnDisk: created) { $0.nodes.append(node) }
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
    func placeFile(
        _ relativePath: String,
        at point: CGPoint,
        creatingOnDisk created: String? = nil
    ) -> String {
        addNode(CanvasNode(
            id: CanvasID.generate(),
            kind: .file(path: relativePath, subpath: nil),
            x: point.x, y: point.y,
            width: 260, height: 180
        ), creatingOnDisk: created)
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
        guard let store else { throw CanvasStore.StoreError.alreadyExists("nessuna cartella note aperta") }
        let relativePath = try store.createFolder(named: name, in: folder)
        let id = placeFile(relativePath, at: point, creatingOnDisk: relativePath)
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


}
