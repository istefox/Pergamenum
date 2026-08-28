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

    /// The open board's own vault-relative path - its identity, and what `CanvasStore` is
    /// told (ADR-0025 §D1/§D4). A folder holds any number of boards under any name, so
    /// the file is named rather than worked out from the directory around it.
    ///
    /// `""` with nothing open, which is what `attach` and `detach` leave behind: there is
    /// no root board to stand in for one (§D1).
    private(set) var board = ""

    /// The directory the open board sits in, read off the board's path and never the
    /// other way round (ADR-0025 §D4) - `folder` still answers "which directory is the
    /// open board in", it has simply stopped being the identity. `""` for a board at the
    /// vault root.
    var folder: String { (board as NSString).deletingLastPathComponent }
    /// The single value that says both which row of the Workspace tree is lit and
    /// whether a board is drawn (ADR-0024 §D4). Replaces the former `hasOpenBoard`
    /// flag: `attach` opens nothing at all (ADR-0025 §D4), so `current` stays `nil`
    /// until something is actually selected.
    ///
    /// Written in exactly four places, all in this file: `attach` (`nil`),
    /// `open(board:)` (`.board`), `select(_:)` (whatever the tree asked for) and
    /// `detach` (`nil`). Everything else reads it.
    private(set) var current: WorkspaceSelection?
    /// True only while a board is drawn, derived from `current` rather than stored
    /// separately (ADR-0024 §D4) - answering "is a board on screen" can never disagree
    /// with "which row is lit" because both read the same value.
    var isShowingBoard: Bool { current?.hasBoard ?? false }
    private(set) var document = CanvasDocument.empty
    private(set) var contents = CanvasStore.FolderContents(subfolders: [], unplaced: [])
    /// `contents.subfolders` in the shape the "is this path a folder" question needs.
    ///
    /// That question is asked once per node while the board draws (`subfolder(for:)`,
    /// `selectedFileURLs`) and once per tray row (`BoardChrome`), so answering it by
    /// scanning the array cost O(nodes x subfolders) per redraw. `contents.subfolders`
    /// stays an ordered array because display order is its other job; this is the same
    /// data indexed for lookup, written only by `setContents` so the two cannot drift.
    private(set) var subfolderSet: Set<String> = []

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
    /// The vault this board belongs to, handed over by `attach` beside the store and the
    /// thumbnail cache. It exists for `recordProblem` alone: the Workspace draws no
    /// problem list of its own, so a recoverable failure is reported where the app
    /// already shows them (Impostazioni → Problemi, `SettingsView`).
    ///
    /// Weak and observation-ignored: the vault outlives the board and nothing redraws
    /// when it changes.
    @ObservationIgnored private weak var vault: VaultController?

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
    /// The reframing owed to a viewport that is still changing size, and the debounce
    /// waiting for it to settle. Stored here rather than as three `@State` flags in the
    /// view because it is viewport-framing policy; the behaviour lives in
    /// `WorkspaceController+Viewport`, which as an extension cannot hold state.
    ///
    /// One optional rather than a flag per mode: the two modes are mutually exclusive
    /// and this is what makes them unable to be raised together.
    var pendingRefit: RefitMode?
    var refitTask: Task<Void, Never>?

    // MARK: Navigation

    /// `thumbnails` comes from the vault, which owns the cache. Nil is a board with no
    /// renderer: cards fall back to their symbols, which is what the tests exercise.
    ///
    /// `vault` is nil for the same reason and with the same effect on `recordProblem`:
    /// a board attached without one still works, its failures simply have nobody to
    /// report to.
    func attach(
        to store: CanvasStore,
        thumbnails: ThumbnailStore? = nil,
        vault: VaultController? = nil
    ) {
        self.store = store
        self.thumbnails = thumbnails
        self.vault = vault
        // ADR-0024's "loaded, not chosen" becomes "not loaded at all" (ADR-0025 §D4):
        // there is no root board to read (§D1) and nothing ever needed the load - the
        // board area draws only while `isShowingBoard`, which is false until something
        // is opened.
        board = ""
        document = .empty
        current = nil
        // Carried over from the load that used to happen here, because they are about the
        // vault being left rather than the board being read: a step recorded on the
        // previous vault's board must not be undoable onto this one, and a dirty flag
        // that outlived its store would aim the next flush at `board == ""`.
        hasUnsavedChanges = false
        history.reset()
    }

    func detach() {
        // A crop mode left open when the vault closes must not be silently lost
        // (ADR-0020 Consequences: "the board gains its first modal state").
        endCrop(confirm: true)
        saveTask?.cancel()
        saveTask = nil
        store = nil
        thumbnails = nil
        vault = nil
        emailHeaders = [:]
        document = .empty
        setContents(.init(subfolders: [], unplaced: []))
        board = ""
        current = nil
        selection = []
    }

    /// The breadcrumb of SPEC §6.1: the folders the user can jump to, ending in the open
    /// board's own file name (ADR-0025 §D4, R-12).
    ///
    /// It walks the **selection**, not the loaded document (ADR-0024 §D8.1). `folder`
    /// names the last board `load` read, and a `.folder(F)` selection loads nothing, so
    /// deriving from `folder` would leave the previous board's trail on screen while the
    /// tree showed `F`. With nothing selected the trail is `["Workspace"]` alone.
    ///
    /// A board is a file rather than the folder holding it, so it earns a segment of its
    /// own: the two names can differ now (ADR-0025 §D3), and a folder holding two boards
    /// would otherwise draw the same trail for both. That segment is the last one, which
    /// `BoardTopBar` renders as a `Text` and not a link (ADR-0024 §D8.2), so it carries
    /// its containing folder for want of anywhere else to go.
    var breadcrumb: [(title: String, folder: String)] {
        var trail: [(String, String)] = [("Workspace", "")]
        var accumulated = ""
        for component in (current?.folder ?? "").split(separator: "/") {
            accumulated = accumulated.isEmpty ? String(component) : "\(accumulated)/\(component)"
            trail.append((String(component), accumulated))
        }
        if case .board(let path)? = current {
            let fileName = (path as NSString).lastPathComponent
            trail.append(((fileName as NSString).deletingPathExtension, accumulated))
        }
        return trail
    }

    /// Reads a board into this controller and says nothing about whether it is the
    /// selection - that is `open(board:)`'s decision (ADR-0024 §D4).
    ///
    /// Returns false when there is no store to read from, and when the file is not there:
    /// `CanvasStore.load(board:)` throws where the folder-derived read used to return
    /// `.empty`, and that failure has no successor fallback (ADR-0025 §D1/§D4). A board
    /// nothing could load must not become a board on screen, so the read happens before
    /// anything here is written and a miss leaves the open board exactly as it was.
    @discardableResult
    private func load(board newBoard: String) -> Bool {
        guard let store else { return false }
        let loaded: CanvasDocument
        do {
            loaded = try store.load(board: newBoard)
        } catch {
            recordProblem("\(newBoard): \(error)")
            return false
        }
        // Navigating away confirms an open crop the same way a click outside the card
        // would (ADR-0020 D5), rather than silently discarding it.
        endCrop(confirm: true)
        // Leaving a board with pending edits must not lose them. Still aimed at the board
        // being left, because `board` below has not moved yet.
        flushPendingSave()

        board = newBoard
        document = loaded
        selection = []
        pan = .zero
        zoom = 1
        refreshContents()
        hasUnsavedChanges = false
        // Each board has its own history: undoing on one board must never reach back
        // into a change made on another.
        history.reset()
        return true
    }

    /// Loads a board by its own path and makes it the selection. Every caller outside the
    /// tree - the breadcrumb, a folder card, a `pergamenum://canvas` route, a new board, a
    /// note handed over from the editor - means "this is now the selected board"
    /// (ADR-0024 §D4, F10), so there is no `markOpen:` left to say otherwise.
    ///
    /// A board that could not be read selects nothing and is reported (ADR-0025 §D4): a
    /// lit row for a file that is not there is the silent blank board this chain exists
    /// to remove.
    func open(board path: String) {
        guard load(board: path) else { return }
        current = .board(path: path)
    }

    /// Writes the tree's selection (ADR-0024 §D4), replacing the removed
    /// `closeBoard()`: `select(nil)` is what `closeBoard()` was, `select(.board(f))`
    /// is what a row click on a board does, `select(.folder(f))` is what a row click
    /// on a board-less folder does.
    ///
    /// The guard is why this is not simply a setter. ADR-0023 §D4 has the context menu
    /// set the selection before it raises a sheet, so without it a right-click on the
    /// board already on screen would re-`open` it and reset the zoom and pan of the very
    /// thing the user was looking at (ADR-0024 §D4).
    func select(_ new: WorkspaceSelection?) {
        guard new != current else { return }
        if case .board(let path)? = new {
            open(board: path)
            return
        }
        // Selecting a board-less folder, or nothing at all, is still leaving whatever
        // board was on screen, so it owes the same two obligations `load` discharges
        // before replacing a document (ADR-0020 D5). What it does not do is load:
        // `folder` and `document` stay as they are, unread until something is opened.
        endCrop(confirm: true)
        flushPendingSave()
        selection = []
        current = new
    }

    /// Records a problem for the UI to show. Used where a failure should not stop the
    /// board being usable: a rejected folder name can simply be retyped.
    ///
    /// Reported on the vault, not kept here. The Workspace has no surface that draws a
    /// problem list, so a list of its own would be a sink nothing empties and nobody
    /// reads. `VaultController.problems` is the one place the app already shows these
    /// (Impostazioni → Problemi), the same door `DayController` and the editor report
    /// their own recoverable failures through.
    func recordProblem(_ message: String) {
        vault?.recordProblem(message)
    }

    /// Re-reads the folder from disk and re-splits it into what the board shows and what
    /// it does not.
    ///
    /// The directory listing is deliberately **not** cached, even though every caller but
    /// `load` changes only the placed set and leaves the folder itself untouched. This
    /// re-read is the tray's entire freshness mechanism: SPEC §6.1 has a file dropped into
    /// the folder from Finder appear under "Nuovi elementi", no view ever calls this, and
    /// `scanGeneration` cannot stand in for the invalidation because
    /// `VaultWatcher.handle(absolutePaths:)` discards every path that is not `.md` - which
    /// is exactly the pdf, image and eml the tray exists for. A listing held until the next
    /// `load` would leave a dropped file invisible until the user navigated away and back,
    /// which is a worse trade than one directory enumeration per card.
    ///
    /// What is worth removing is a *second* call inside one mutation, where the first has
    /// already read the same document against the same disk - see `createFolder`.
    func refreshContents() {
        guard let store else { return }
        setContents(store.contents(ofBoard: board, document: document))
    }

    /// The only writer of `contents`, so `subfolderSet` is refilled with it every time
    /// and no future caller can update one and forget the other.
    private func setContents(_ new: CanvasStore.FolderContents) {
        contents = new
        subfolderSet = Set(new.subfolders)
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
            // offer actions on nothing. The ids are hashed once rather than scanned per
            // selected card, so holding Cmd+Z on a board with a large marquee selection
            // stays linear instead of costing selection × nodes comparisons a step.
            let liveIDs = Set(document.nodes.map(\.id))
            selection = selection.intersection(liveIDs)
            hasUnsavedChanges = true
            scheduleSave()
            refreshContents()
            return true
        case .blocked(let name):
            recordProblem(
                "«\(name)» è stata creata su disco: annullare toglierebbe la card e lascerebbe il file. "
                + "Eliminalo dal Finder se non lo vuoi."
            )
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

    /// The `.text` card being written into, transient like the crop above and for the same
    /// reason: the document is mutated once, at `endTextEdit(commit:)`, not per keystroke.
    var editingTextNodeID: String?
    /// The editor's own draft, on the controller rather than local view state (as
    /// `cropDraft` is) so that Esc, an outside click and a focus change - three different
    /// views - can all commit the same value instead of each holding their own copy.
    var editingTextDraft: String = ""

    /// Enters inline editing on a `.text` node - a double click, the «Modifica testo»
    /// command, or straight after Nota/Testo creates one (SPEC §6.3).
    func beginTextEdit(nodeID: String) {
        guard case .text(let text) = document.node(id: nodeID)?.kind else { return }
        // No two editors of different kinds open at once, the same rule `beginCrop` follows.
        if croppingNodeID != nil { endCrop(confirm: true) }
        select(nodeID: nodeID, adding: false)
        editingTextNodeID = nodeID
        editingTextDraft = text
    }

    /// Leaves inline editing. `commit` writes `editingTextDraft` through the existing
    /// `setText`; `false` discards it (Esc is the only caller that ever does).
    func endTextEdit(commit: Bool) {
        guard let id = editingTextNodeID else { return }
        if commit {
            setText(editingTextDraft, forNodeID: id)
        }
        editingTextNodeID = nil
    }

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
        // No second `refreshContents()` here. The directory exists before `placeFile` runs,
        // and `placeFile` -> `addNode` already refreshed against this same document and this
        // same disk, so a call on the way out enumerated the folder twice for one new card
        // and could only ever recompute the value already in `contents`.
        return placeFile(relativePath, at: point, creatingOnDisk: relativePath)
    }

    /// Absolute URL of the file a node points at, when it points at one.
    func fileURL(for node: CanvasNode) -> URL? {
        guard let store, case .file(let path, _) = node.kind else { return nil }
        return store.root.appending(path: path, directoryHint: .notDirectory)
    }

    /// URLs of the selected file cards, for the Quick Look panel (SPEC §6.6).
    ///
    /// The empty-selection exit is not tidiness: this walks every node in the document
    /// and stats each file it keeps, and the board redraws far more often than anything
    /// is selected. Nothing selected can only ever produce an empty list anyway.
    var selectedFileURLs: [URL] {
        guard !selection.isEmpty else { return [] }
        return document.nodes
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
    /// cheap even for a message with a large attachment: the file is mapped rather than
    /// copied, and only the bytes before the blank line are decoded.
    func loadEmailHeaders(for relativePath: String) {
        guard let store, emailHeaders[relativePath] == nil else { return }
        let fileURL = store.root.appending(path: relativePath, directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return }
        let headerBytes = Self.headerBlock(of: data)

        // Latin-1 as the fallback: an .eml whose headers are not UTF-8 still has
        // readable ASCII field names, and refusing the file would leave the card blank.
        let text = String(data: headerBytes, encoding: .utf8)
            ?? String(data: headerBytes, encoding: .isoLatin1)
            ?? ""
        emailHeaders[relativePath] = EmailHeaderParser.parse(text)
    }

    /// The bytes up to the blank line that ends an `.eml`'s header block.
    ///
    /// `EmailHeaderParser` stops at that line anyway, but only after the whole message
    /// has been decoded into a `String` - which for a base64 attachment is megabytes of
    /// UTF-8 validation done to be thrown away. Cutting at the boundary in bytes keeps
    /// the cost proportional to the headers.
    ///
    /// The search is capped: a file with no blank line in its first 64 KB is not a
    /// message these cards can describe, and the fallback cut lands on the last newline
    /// so a multi-byte character is never split - half a character fails UTF-8 and
    /// silently lands in the Latin-1 fallback as mojibake.
    private static func headerBlock(of data: Data) -> Data {
        let limit = min(data.count, 64 * 1024)
        let window = data[data.startIndex..<data.index(data.startIndex, offsetBy: limit)]

        let separators = [Data([0x0A, 0x0A]), Data([0x0D, 0x0A, 0x0D, 0x0A])]
        if let end = separators.compactMap({ window.range(of: $0)?.lowerBound }).min() {
            return window[window.startIndex..<end]
        }
        // Headers-only file shorter than the cap: nothing was truncated, keep it whole.
        guard limit < data.count, let lastNewline = window.lastIndex(of: 0x0A) else { return window }
        return window[window.startIndex..<lastNewline]
    }

    /// The folder a card points at, when it points at one.
    func subfolder(for node: CanvasNode) -> String? {
        guard case .file(let path, _) = node.kind else { return nil }
        return subfolderSet.contains(path) ? path : nil
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
            // The hash is deliberately dropped rather than recorded as a self-write:
            // `VaultWatcher` reports only `.md` paths, so a `.canvas` write never
            // reaches `VaultSession.reconcile` and there is nothing for a recorded hash
            // to be recognised against. The board cannot be reloaded under the user by
            // the watcher because the watcher never hears about it.
            try store.save(document, board: board)
            hasUnsavedChanges = false
        } catch {
            // Left dirty on purpose: an indicator still showing unsaved changes is
            // the truth, and the next edit will retry.
            recordProblem("salvataggio di \(board): \(error)")
        }
    }
}
