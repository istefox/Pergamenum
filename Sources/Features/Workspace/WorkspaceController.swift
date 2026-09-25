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
    /// The tools of SPEC §6.4, ten of the eleven it lists: ADR-0027 §D8 unified Nota
    /// into Testo, so `.text` is the only tool of that family and the `n` key is free.
    /// `forms` is excluded from v1 and kept only so the toolbar layout does not have to
    /// be redone in v2.
    enum Tool: String, CaseIterable, Identifiable, Sendable {
        case select, text, folder, image, document, link, todo, forms, drawing, arrow

        var id: String { rawValue }

        var isAvailable: Bool { self != .forms }

        /// Single-key shortcut. Tools without one are not reachable from the keyboard.
        var shortcut: String? {
            switch self {
            case .select: "v"
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

    /// Which bytes `document` came from (ADR-0054 §D2, applying ADR-0052 §D1/§D3's rule -
    /// an in-memory document records which file it was read from - to this second holder).
    /// One value, not a path property beside a hash property that can drift apart. It
    /// carries three things because §D4's reconciliation needs all three: *which* board,
    /// the hash of the *bytes* read (not of a re-encoding of them), and the *document*
    /// those bytes decoded to - the `base` of `save()`'s three-way comparison on a refusal.
    enum BoardOrigin: Equatable {
        case none
        case loaded(board: String, hash: String, document: CanvasDocument)
    }
    private(set) var origin: BoardOrigin = .none
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

    /// `.pending`/`.conflicted` while an edit has not safely reached disk, `.saved` once
    /// it has - the "Salvato"/"Salvataggio…"/"Conflitto" indicator of §6.1 (ADR-0054 §D5).
    ///
    /// Not `private(set)`: `WorkspaceController+Conflict.swift`'s `keepLocalBoard()` and
    /// `reloadBoardFromDisk()` advance it too, from a different file than the one that
    /// declares it - the ADR-0045 widening this repo already uses when a
    /// `type_body_length` split moves a writer out of the file that owns the property.
    enum SaveState: Equatable {
        case saved
        case pending
        case conflicted(reason: String)
    }
    var saveState: SaveState = .saved

    /// Whether the board has changes not yet safely on disk. Kept as its own computed
    /// property, name, type and meaning unchanged, so it can never disagree with
    /// `saveState` (ADR-0054 §D5) - `true` for `.pending` and for `.conflicted`, both of
    /// which still hold in-memory content nothing has written.
    var hasUnsavedChanges: Bool { saveState != .saved }

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
    ///
    /// Not `private(set)`: the only writer, `loadEmailHeaders(for:)`, lives in
    /// `WorkspaceController+Files.swift`.
    var emailHeaders: [String: EmailHeaders] = [:]
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
        replaceDocument(.empty, origin: .none)
        current = nil
        // A fold is transient and keyed by node id (ADR-0028 §D8): a table carried into
        // another vault would name ids that mean nothing here, or - worse - ids that mean
        // something else, since a canvas id is unique within its file and not across a vault.
        // This line is what makes "a fold resets when the board is reopened" true.
        foldedHeadings = [:]
        // Carried over from the load that used to happen here, because they are about the
        // vault being left rather than the board being read: a step recorded on the
        // previous vault's board must not be undoable onto this one, and a dirty flag
        // that outlived its store would aim the next flush at `board == ""`.
        saveState = .saved
        history.reset()
    }

    func detach() {
        // A crop mode left open when the vault closes must not be silently lost
        // (ADR-0020 Consequences: "the board gains its first modal state").
        endCrop(confirm: true)
        // `detach()` does not flush - it cancels. The flush that should have happened is
        // `WorkspaceView`'s `.onDisappear`, which runs before this and now skips a
        // conflicted board on purpose (ADR-0054 §D5), so this is the one path left where
        // an unresolved conflict's edit still disappears - reported, not blocked: refusing
        // to close over an autosave conflict would be worse than the loss it prevents.
        if case .conflicted = saveState {
            recordProblem(
                "«\(board)» aveva un conflitto di salvataggio non risolto: le ultime modifiche non sono state salvate"
            )
        }
        saveTask?.cancel()
        saveTask = nil
        store = nil
        thumbnails = nil
        vault = nil
        emailHeaders = [:]
        // Same reason as in `attach` above, from the other side of the same crossing.
        foldedHeadings = [:]
        replaceDocument(.empty, origin: .none)
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
    var breadcrumb: [BreadcrumbSegment] {
        var trail: [BreadcrumbSegment] = [BreadcrumbSegment(title: "Workspace", folder: "")]
        var accumulated = ""
        for component in (current?.folder ?? "").split(separator: "/") {
            accumulated = accumulated.isEmpty ? String(component) : "\(accumulated)/\(component)"
            trail.append(BreadcrumbSegment(title: String(component), folder: accumulated))
        }
        if case .board(let path)? = current {
            let fileName = (path as NSString).lastPathComponent
            trail.append(BreadcrumbSegment(
                title: (fileName as NSString).deletingPathExtension, folder: accumulated
            ))
        }
        return trail
    }

    /// Reads a board into this controller and says nothing about whether it is the
    /// selection - that is `open(board:)`'s decision (ADR-0024 §D4).
    ///
    /// Returns false when there is no store to read from, and when the file is not there:
    /// `CanvasStore.read(board:)` throws where the folder-derived read used to return
    /// `.empty`, and that failure has no successor fallback (ADR-0025 §D1/§D4). A board
    /// nothing could load must not become a board on screen, so the read happens before
    /// anything here is written and a miss leaves the open board exactly as it was.
    ///
    /// Reads through `store.read(board:)` rather than `store.load(board:)` so the hash
    /// `origin` records comes from the same read as the document (ADR-0054 §D2) - not a
    /// re-encoding of it, which `save()`'s reconciliation on a refusal depends on. This is
    /// also the only channel that notices an external `.canvas` change at all: `.canvas`
    /// paths never reach `VaultWatcher` (ADR-0054 §D7), so a board's own hash is stale
    /// from the moment another writer touches the file until this board is reopened or an
    /// autosave refuses and reconciles.
    @discardableResult
    private func load(board newBoard: String) -> Bool {
        guard let store else { return false }
        guard !refusesToLeaveConflictedBoard() else { return false }
        let loaded: (document: CanvasDocument, hash: String)
        do {
            loaded = try store.read(board: newBoard)
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
        replaceDocument(
            loaded.document,
            origin: .loaded(board: newBoard, hash: loaded.hash, document: loaded.document)
        )
        selection = []
        pan = .zero
        zoom = 1
        refreshContents()
        saveState = .saved
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
        // Before either branch: the `.board` one is also caught inside `load`, but the
        // folder/nil one below never reaches `load` and would wipe `document` and `origin`
        // under a `.conflicted` state, leaving a conflict nothing can resolve.
        guard !refusesToLeaveConflictedBoard() else { return }
        if case .board(let path)? = new {
            open(board: path)
            return
        }
        // Selecting a board-less folder, or nothing at all, is still leaving whatever
        // board was on screen, so it owes the same two obligations `load` discharges
        // before replacing a document (ADR-0020 D5). What it does not do is load: no
        // read happens here. But it must not go on showing what was already read
        // (PG-062): `board`/`document`/`contents` are reset the same way `detach()`
        // resets them, so `current == nil`/`.folder` and "a board's data is on screen"
        // can never disagree.
        endCrop(confirm: true)
        flushPendingSave()
        selection = []
        current = new
        replaceDocument(.empty, origin: .none)
        setContents(.init(subfolders: [], unplaced: []))
        board = ""
    }

    /// A conflicted board is not left (ADR-0057 §D8, #498): `flushPendingSave()` skips it by
    /// design (ADR-0054 §D5), so navigating away replaced its document and dropped the edit
    /// without a word. Refused and reported instead, the diary's rule (ADR-0057 §D5/§D6);
    /// `detach()` stays the one exit that is not refused, and reports the loss.
    private func refusesToLeaveConflictedBoard() -> Bool {
        guard case .conflicted = saveState else { return false }
        recordProblem(
            "«\(board)» ha un conflitto di salvataggio non risolto: resta aperta finché non scegli "
                + "«Mantieni le mie modifiche» o «Ricarica dal disco»"
        )
        return true
    }

    /// The sidebar's rename/move/trash verbs (`WorkspaceView+FolderVerbs.swift`) still
    /// perform their disk operation on a conflicted open board even though `load`/`select`
    /// now refuse the follow-up navigation: the file moves, `board` keeps naming the old
    /// path, and «Mantieni»/«Ricarica» can no longer read it - the conflict becomes
    /// unrecoverable rather than merely stranded. Checked before the disk operation, not
    /// after, so the file never moves out from under an unresolved conflict.
    func canLeaveOpenBoardForVerb() -> Bool {
        !refusesToLeaveConflictedBoard()
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
    /// is exactly the pdf, image and eml the tray exists for, and the same gap `save()`'s
    /// own `expecting:` precondition exists to cover for `.canvas` bytes rather than
    /// waiting on a watcher event that never comes (ADR-0054 §D7 - not a reason to extend
    /// the watcher to `.canvas`, see that section). A listing held until the next `load`
    /// would leave a dropped file invisible until the user navigated away and back, which
    /// is a worse trade than one directory enumeration per card.
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

    /// The only writer of `document`; every write carries the origin those bytes came
    /// from, so the two can never drift apart the way `LedgerOrigin` exists to prevent
    /// for the pratiche ledger's memory (ADR-0052 §D1/§D3, ADR-0054 §D2 applying the same
    /// rule here). `mutate` below is the one place that still writes `document` in place
    /// rather than through here, because an in-memory edit changes nothing about what
    /// disk holds and so must not touch `origin`.
    ///
    /// Not `private`: `WorkspaceController+Conflict.swift`'s `keepLocalBoard()` and
    /// `reloadBoardFromDisk()` (ADR-0054 §D5) call it from outside this file, the same
    /// `type_body_length`-driven widening ADR-0045 already used for this repo's other
    /// single-writer-door types.
    func replaceDocument(_ newDocument: CanvasDocument, origin newOrigin: BoardOrigin) {
        document = newDocument
        origin = newOrigin
    }

    // MARK: Editing

    /// Applies a change and schedules the write. Every mutation goes through here so
    /// no path can edit the board and forget to save it.
    func mutate(
        creatingOnDisk created: String? = nil,
        _ change: (inout CanvasDocument) -> Void
    ) {
        // PG-062: `attach` opens nothing (ADR-0025 §D4), so without this guard a card
        // created before any board is opened seemed to succeed - it returned an id and
        // even scheduled a save - while `document` and the on-screen board silently
        // disagreed with what `current` said was showing.
        guard current?.hasBoard == true else { return }
        history.record(before: document, creatingOnDisk: created)
        change(&document)
        markPendingUnlessConflicted()
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
            // Undo/redo moves memory, not disk, so the origin travels unchanged
            // (ADR-0054 §D2) - `replaceDocument` still owns the write so the two stay
            // paired, it is just handed the origin it already had.
            replaceDocument(restored, origin: origin)
            // A card that no longer exists must not stay selected: the toolbar would
            // offer actions on nothing. The ids are hashed once rather than scanned per
            // selected card, so holding Cmd+Z on a board with a large marquee selection
            // stays linear instead of costing selection × nodes comparisons a step.
            let liveIDs = Set(document.nodes.map(\.id))
            selection = selection.intersection(liveIDs)
            markPendingUnlessConflicted()
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

    /// `.saved` → `.pending` on an edit; a `.conflicted` board stays conflicted through
    /// further edits (ADR-0054 §D5) - the state is resolved only by an explicit choice,
    /// `keepLocalBoard()` or `reloadBoardFromDisk()`, never silently by typing.
    /// `scheduleSave()` still runs after this either way, but `save()` itself returns
    /// early while `.conflicted` (below), so a reschedule alone produces no further write
    /// and no further refusal - "must not turn into a refusal per second."
    private func markPendingUnlessConflicted() {
        if case .conflicted = saveState { return }
        saveState = .pending
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
    /// Whether a `.text` card draws its markdown or its markers (ADR-0028 §D10). The vault's
    /// own `hidesMarkup`, carried here by `WorkspaceView.applyBoardSettings()` beside the two
    /// above so that the board and the note editor read one setting and not two - a card never
    /// gets a switch of its own. `true` to match `VaultSettings.default`, for the window that
    /// draws a board before the settings have been applied to it.
    var hidesMarkup = true
    /// Whether a `.text` card narrows reveal-on-caret from paragraph to span for emphasis
    /// (ADR-0037 §D8) - the vault's `revealsInlineSpans`, carried down the same route
    /// `hidesMarkup` above already travels rather than a switch of the card's own. `false` to
    /// match `VaultSettings.default`, for the window that draws a board before the settings
    /// have been applied to it. A card's own switch has no `.strikethrough`/`.link` case
    /// (ADR-0029 §D17), so this only ever narrows bold/italic reveal there.
    var revealsInlineSpans = false
    /// The vault's note titles and boards, offered as `[[` completion candidates on a `.text`
    /// card - carried here by `WorkspaceView.applyBoardSettings()` beside `hidesMarkup` above,
    /// the same route rather than a switch of the card's own. Refreshes on board-open and on
    /// `vault.settings` change, not on every vault mutation - a note created in another pane
    /// while this board stays open will not appear until the board's settings next reapply,
    /// the same accepted staleness `hidesMarkup` itself already has.
    var wikilinkNoteTitles: [String] = []
    var wikilinkBoardTitles: [String] = []
    /// Which headings each `.text` card has folded right now, by node id (ADR-0028 §D8).
    ///
    /// The entry ordinals are `NoteOutline.entries(in:)`'s over that node's own text, exactly
    /// the numbers `NoteTab.foldedEntries` holds for a note - the same transient model, keyed
    /// differently because a card has no tab to hold it (plan C6). Transient in the same sense:
    /// nothing of this reaches the `.canvas` file, so a fold is a way of looking at a card and
    /// never a property of it (principle 1), and reopening a board starts unfolded.
    ///
    /// Cleared in `attach` and in `detach`, which is what actually enforces that reset - a
    /// table keyed by node id would otherwise outlive the board whose node ids it names, and
    /// canvas ids are unique within a file rather than across a vault.
    var foldedHeadings: [String: Set<Int>] = [:]
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
    /// Where the selection inside that card is and what is applied to it, published by the
    /// card's own text view and read by the board's floating format bar (ADR-0027 §D5).
    ///
    /// Here for `editingTextDraft`'s own reason - two views that must agree share one value
    /// rather than each keeping a copy - and a separate object rather than three more
    /// properties because it holds a reference to a live `NSTextView`, which is not something
    /// this file should know about (see `CardTextSelection`).
    let cardTextSelection = CardTextSelection()
    /// The `.text` card's `[[` completion popup - trigger, candidates and highlighted index -
    /// published by that card's own text view and read by the board's popup overlay. A
    /// separate holder from `cardTextSelection` above rather than three more properties on it,
    /// for the same reason that one is a separate object at all: it holds a reference to a
    /// live `NSTextView`.
    let wikilinkCompletionState = CardWikilinkCompletionState()

    /// The `.link` card's title being written into (PG-073), transient like `editingTextNodeID`
    /// above and for the same reason: the document is mutated once, at `endTitleEdit(commit:)`.
    var editingTitleNodeID: String?
    /// The field's own draft, same reasoning as `editingTextDraft`: Esc, an outside click and a
    /// focus change all commit the same value instead of each holding their own copy.
    var editingTitleDraft: String = ""

    /// The arrow being drawn with the Freccia tool (SPEC §6.4, tool 11): the card it
    /// started from and how far the pointer has travelled from there, in board units.
    ///
    /// Transient like the drag and the resize, and for the same reason: an edge is
    /// written once, on release, not on every frame of the gesture.
    var arrowSourceID: String?
    var arrowTranslation: CGSize = .zero

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

    /// `.canvas` paths never reach `VaultWatcher` (ADR-0054 §D7), so nothing tells this
    /// board when another writer has touched the file underneath it. `expecting:` is the
    /// substitute: the write proves against `origin`'s hash instead, and a mismatch is
    /// reconciled here rather than silently overwritten or silently discarded.
    private func save() {
        guard let store, hasUnsavedChanges else { return }
        // A conflicted board neither writes nor retries until the person chooses
        // `keepLocalBoard()` or `reloadBoardFromDisk()` (ADR-0054 §D5) - a retry per edit
        // would refuse once a second and fill the problem list.
        if case .conflicted = saveState { return }
        attemptSave(store: store, allowingRetry: true)
    }

    /// An origin of `.none`, or one naming a different board than `board`, writes with
    /// `expecting: nil` - there is nothing to prove and forcing a refusal would make the
    /// board unsavable.
    private func attemptSave(store: CanvasStore, allowingRetry: Bool) {
        let expecting: String? = {
            guard case .loaded(let originBoard, let hash, _) = origin, originBoard == board else { return nil }
            return hash
        }()

        do {
            let writtenHash = try store.save(document, board: board, expecting: expecting)
            replaceDocument(document, origin: .loaded(board: board, hash: writtenHash, document: document))
            saveState = .saved
        } catch is VaultWriteRefusal {
            guard allowingRetry else {
                // A second writer landed inside the retry window; treated as diverged
                // rather than reconciled and looped again (ADR-0054 §D4).
                enterConflicted(reason: VaultWriteRefusal.movedOn(board).description)
                return
            }
            reconcileAfterRefusal(store: store)
        } catch {
            // Left dirty on purpose: an indicator still showing unsaved changes is
            // the truth, and the next edit will retry.
            recordProblem("salvataggio di \(board): \(error)")
        }
    }

    /// ADR-0054 §D4: re-reads the board and asks the pure three-way rule what the
    /// external writer did, using the base `origin` kept from the read this board's
    /// unsaved edit started from.
    private func reconcileAfterRefusal(store: CanvasStore) {
        guard case .loaded(_, _, let base) = origin else {
            // `expecting` is only ever non-nil when `origin` matches this board, so a
            // refusal with nothing to reconcile against should not happen; nothing safe
            // to do but report it.
            enterConflicted(reason: VaultWriteRefusal.movedOn(board).description)
            return
        }

        let theirs: (document: CanvasDocument, hash: String)
        do {
            theirs = try store.read(board: board)
        } catch {
            recordProblem("salvataggio di \(board): \(error)")
            return
        }

        switch CanvasDocument.reconcile(mine: document, base: base, theirs: theirs.document) {
        case .adopted(let merged):
            replaceDocument(
                merged, origin: .loaded(board: board, hash: theirs.hash, document: theirs.document)
            )
            attemptSave(store: store, allowingRetry: false)
        case .diverged(let reasons):
            enterConflicted(
                reason: "\(VaultWriteRefusal.movedOn(board).description) (\(reasons.joined(separator: ", ")))"
            )
        }
    }

    /// The one door into `.conflicted` (ADR-0054 §D5): `recordProblem` fires here and only
    /// here, so re-entering `save()` while already conflicted - which `markPendingUnlessConflicted()`
    /// makes impossible until an explicit resolution - can never repeat it.
    private func enterConflicted(reason: String) {
        saveState = .conflicted(reason: reason)
        recordProblem(reason)
    }
}
