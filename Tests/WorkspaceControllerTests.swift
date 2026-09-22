import Foundation
import Testing
@testable import Pergamenum

// `WorkspaceController` breadcrumb navigation, board open/close, node CRUD and title
// editing tests (PG-088 — pure code motion off `CanvasTests.swift`).
// MARK: - Workspace controller

@MainActor
@Test func navigatesTheBoardHierarchyWithABreadcrumb() throws {
    // ADR-0025 §D3/§D4 (plan Task 3): a board is opened by its own path, not derived
    // from its folder. The existing vault's own convention - a board named after the
    // folder holding it - is kept here so the on-disk fixture matches R-13's "the
    // existing vault behaves exactly as it did before".
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("01 Progetti/vibrofer-emea")
    let store = CanvasStore(root: root.url)
    let boardPath = try store.createBoard(named: "vibrofer-emea", in: "01 Progetti/vibrofer-emea")
    let controller = WorkspaceController()
    controller.attach(to: store)

    #expect(controller.breadcrumb.map(\.title) == ["Workspace"])

    controller.open(board: boardPath)
    #expect(controller.breadcrumb.map(\.title) == ["Workspace", "01 Progetti", "vibrofer-emea", "vibrofer-emea"])
    // Only the navigable (non-last) segments' `.folder` is pinned: `BoardTopBar` reads
    // `.folder` solely to build the Button action for an ancestor segment
    // (BoardChrome.swift), never for the last one, which is a Text (ADR-0024 §D8.2) -
    // so the last segment's `.folder` value is left unspecified rather than guessed.
    #expect(controller.breadcrumb.dropLast().map(\.folder) == ["", "01 Progetti", "01 Progetti/vibrofer-emea"])
    controller.detach()
}

@MainActor
@Test func writesTheBoardWhenLeavingItEvenBeforeTheAutosaveDelay() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("A")
    try root.makeDirectory("B")
    let store = CanvasStore(root: root.url)
    let boardA = try store.createBoard(named: "A", in: "A")
    let boardB = try store.createBoard(named: "B", in: "B")
    let controller = WorkspaceController()
    controller.attach(to: store)

    controller.open(board: boardA)
    _ = controller.addStickyNote("appunto", at: CGPoint(x: 10, y: 10))
    #expect(controller.hasUnsavedChanges)

    // Navigating away must not lose the edit while the debounce is still pending.
    controller.open(board: boardB)
    let saved = try store.load(board: boardA)
    #expect(saved.nodes.count == 1)
    controller.detach()
}

// ADR-0054 §D2 (plan Task 3, R-05, R-06): `origin` records which bytes `document` came
// from, so `save()`'s reconciliation on a refusal has a `base` to compare against.

@MainActor
@Test func openingABoardSetsOriginToLoadedWithTheHashOfTheFilesBytes() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("A")
    let store = CanvasStore(root: root.url)
    let boardPath = try store.createBoard(named: "A", in: "A")
    let controller = WorkspaceController()
    controller.attach(to: store)

    controller.open(board: boardPath)

    guard case .loaded(let board, let hash, let document) = controller.origin else {
        Issue.record("expected .loaded")
        return
    }
    #expect(board == boardPath)
    let bytes = try Data(contentsOf: store.url(forBoard: boardPath))
    #expect(hash == NoteStore.hash(bytes))
    #expect(document == controller.document)
    controller.detach()
}

@MainActor
@Test func attachSelectNilSelectFolderAndDetachEachLeaveOriginNone() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("A")
    let store = CanvasStore(root: root.url)
    let boardPath = try store.createBoard(named: "A", in: "A")
    let controller = WorkspaceController()

    controller.attach(to: store)
    #expect(controller.origin == .none)

    controller.open(board: boardPath)
    guard case .loaded = controller.origin else {
        Issue.record("expected .loaded before select(nil)")
        return
    }
    controller.select(nil)
    #expect(controller.origin == .none)

    controller.open(board: boardPath)
    controller.select(.folder("A"))
    #expect(controller.origin == .none)

    controller.open(board: boardPath)
    controller.detach()
    #expect(controller.origin == .none)
}

@MainActor
@Test func aMutateLeavesOriginUntouchedWhileDocumentChanges() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    controller.flushPendingSave()
    let originBefore = controller.origin

    _ = controller.addStickyNote("appunto", at: .zero)

    #expect(controller.origin == originBefore)
    #expect(controller.document != .empty)
    controller.detach()
}

@MainActor
@Test func undoAndRedoLeaveOriginUntouched() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    controller.flushPendingSave()
    let originBefore = controller.origin

    _ = controller.addStickyNote("appunto", at: .zero)
    #expect(controller.undo())
    #expect(controller.origin == originBefore)

    #expect(controller.redo())
    #expect(controller.origin == originBefore)
    controller.detach()
}

@MainActor
@Test func aLoadThatThrowsLeavesThePreviousBoardsOriginIntact() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("A")
    let store = CanvasStore(root: root.url)
    let boardPath = try store.createBoard(named: "A", in: "A")
    let controller = WorkspaceController()
    controller.attach(to: store)
    controller.open(board: boardPath)
    let originBefore = controller.origin

    controller.open(board: "A/does-not-exist.canvas")

    #expect(controller.origin == originBefore)
    #expect(controller.board == boardPath)
    controller.detach()
}

@MainActor
@Test func deletingANodeAlsoRemovesItsEdges() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let a = controller.addStickyNote("a", at: .zero)
    let b = controller.addStickyNote("b", at: CGPoint(x: 300, y: 0))
    #expect(controller.connect(from: a, to: b) != nil)

    controller.delete(nodeIDs: [a])
    // An edge to a node that no longer exists is unrenderable and a strict reader
    // would reject the file.
    #expect(controller.document.edges.isEmpty)
    #expect(controller.document.nodes.map(\.id) == [b])
    controller.detach()
}

@MainActor
@Test func refusesAnEdgeToAMissingOrIdenticalNode() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let a = controller.addStickyNote("a", at: .zero)
    #expect(controller.connect(from: a, to: a) == nil)
    #expect(controller.connect(from: a, to: "inesistente") == nil)
    controller.detach()
}

@MainActor
@Test func beginTextEditSeedsTheDraftFromTheStoredTextAndCommitWritesItBack() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let id = controller.addStickyNote("appunto", at: .zero)
    controller.beginTextEdit(nodeID: id)
    #expect(controller.editingTextNodeID == id)
    #expect(controller.editingTextDraft == "appunto")

    controller.editingTextDraft = "appunto aggiornato"
    controller.endTextEdit(commit: true)
    #expect(controller.editingTextNodeID == nil)
    let node = try #require(controller.document.node(id: id))
    #expect(node.kind == .text("appunto aggiornato"))
    controller.detach()
}

@MainActor
@Test func endTextEditWithoutCommitDiscardsTheDraft() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let id = controller.addStickyNote("appunto", at: .zero)
    controller.beginTextEdit(nodeID: id)
    controller.editingTextDraft = "scartato"
    controller.endTextEdit(commit: false)

    #expect(controller.editingTextNodeID == nil)
    let node = try #require(controller.document.node(id: id))
    #expect(node.kind == .text("appunto"))
    controller.detach()
}

@MainActor
@Test func beginTextEditIgnoresANonTextNode() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let id = try controller.createFolder(named: "cartella", at: .zero)
    controller.beginTextEdit(nodeID: id)
    #expect(controller.editingTextNodeID == nil)
    controller.detach()
}

// PG-073 (R-04): begin seeds the draft from the stored title, or "" when unset.
@MainActor
@Test func beginTitleEditSeedsTheDraftFromTheStoredTitleOrEmptyWhenUnset() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let untitled = controller.addLink("https://example.com", at: .zero)
    controller.beginTitleEdit(nodeID: untitled)
    #expect(controller.editingTitleNodeID == untitled)
    #expect(controller.editingTitleDraft == "")
    controller.endTitleEdit(commit: false)

    let titled = controller.addLink("https://example.org", at: .zero)
    controller.setTitle("Documentazione", forNodeID: titled)
    controller.beginTitleEdit(nodeID: titled)
    #expect(controller.editingTitleDraft == "Documentazione")
    controller.detach()
}

// PG-073 (R-05): commit with a non-empty draft writes `pergamenum-title` and the title reads
// back correctly.
@MainActor
@Test func beginTitleEditCommitWithNonEmptyDraftWritesTheTitleKey() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let id = controller.addLink("https://example.com", at: .zero)
    controller.beginTitleEdit(nodeID: id)
    controller.editingTitleDraft = "Documentazione"
    controller.endTitleEdit(commit: true)

    #expect(controller.editingTitleNodeID == nil)
    let node = try #require(controller.document.node(id: id))
    #expect(LinkCardTitle.read(from: node) == "Documentazione")
    controller.detach()
}

// PG-073 (R-06): commit with an empty draft removes the key entirely, never writes "".
@MainActor
@Test func endTitleEditCommitWithEmptyDraftRemovesTheTitleKeyRatherThanWritingEmpty() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let id = controller.addLink("https://example.com", at: .zero)
    controller.setTitle("Documentazione", forNodeID: id)
    controller.beginTitleEdit(nodeID: id)
    controller.editingTitleDraft = ""
    controller.endTitleEdit(commit: true)

    let node = try #require(controller.document.node(id: id))
    #expect(LinkCardTitle.read(from: node) == nil)
    #expect(node.unknown[LinkCardTitle.key] == nil)
    controller.detach()
}

// PG-073 (R-07): Esc (`commit: false`) leaves the stored node unchanged.
@MainActor
@Test func endTitleEditWithoutCommitLeavesTheStoredTitleUnchanged() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let id = controller.addLink("https://example.com", at: .zero)
    controller.setTitle("Documentazione", forNodeID: id)
    controller.beginTitleEdit(nodeID: id)
    controller.editingTitleDraft = "scartato"
    controller.endTitleEdit(commit: false)

    #expect(controller.editingTitleNodeID == nil)
    let node = try #require(controller.document.node(id: id))
    #expect(LinkCardTitle.read(from: node) == "Documentazione")
    controller.detach()
}

@MainActor
@Test func beginTitleEditIgnoresANonLinkNode() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let id = controller.addStickyNote("appunto", at: .zero)
    controller.beginTitleEdit(nodeID: id)
    #expect(controller.editingTitleNodeID == nil)
    controller.detach()
}

// PG-073 (R-09): a duplicated `.link` node carries the same `pergamenum-title` value.
@MainActor
@Test func duplicatingATitledLinkNodeCarriesTheTitleAlong() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let id = controller.addLink("https://example.com", at: .zero)
    controller.setTitle("Documentazione", forNodeID: id)

    let copies = controller.duplicate(nodeIDs: [id])
    let copyID = try #require(copies.first)
    let copy = try #require(controller.document.node(id: copyID))
    #expect(LinkCardTitle.read(from: copy) == "Documentazione")
    controller.detach()
}

@MainActor
@Test func keepsNodesGrabbableWhenResizedToNothing() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let id = controller.addStickyNote("a", at: .zero)
    controller.resize(nodeID: id, to: CGSize(width: -50, height: 0))
    let node = try #require(controller.document.node(id: id))
    // A node with no extent could never be grabbed again.
    #expect(node.width >= 40)
    #expect(node.height >= 30)
    controller.detach()
}

@MainActor
@Test func creatingAFolderCardCreatesTheDirectory() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    _ = try controller.createFolder(named: "Rilievi", at: CGPoint(x: 20, y: 20))

    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(
        atPath: root.url.appending(path: "Rilievi").path(percentEncoded: false), isDirectory: &isDirectory
    )
    #expect(exists)
    #expect(isDirectory.boolValue)
    #expect(controller.contents.subfolders == ["Rilievi"])
    controller.detach()
}

@MainActor
@Test func clampsZoomToTheRangeOfTheSpec() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    controller.zoom(by: 100)
    #expect(controller.zoom == WorkspaceController.zoomRange.upperBound)
    controller.zoom(by: 0.0001)
    #expect(controller.zoom == WorkspaceController.zoomRange.lowerBound)
    controller.resetZoom()
    #expect(controller.zoom == 1)
    controller.detach()
}

@MainActor
@Test func zoomToFitOnAnEmptyBoardResetsInsteadOfDividingByZero() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    controller.zoomToFit(in: CGSize(width: 800, height: 600))
    #expect(controller.zoom == 1)
    #expect(controller.pan == .zero)
    controller.detach()
}

@MainActor
@Test func excludesTheFormsToolFromV1() {
    // SPEC §6.4 keeps the slot in the layout but not the feature. Counts updated for
    // ADR-0027 (docs/superpowers/plans/2026-08-28-unificare-nota-e-testo-in-un-solo-strume.md,
    // Task 1): `.note` is removed from `Tool`, so ten cases remain instead of eleven.
    #expect(WorkspaceController.Tool.allCases.count == 10)
    #expect(WorkspaceController.Tool.forms.isAvailable == false)
    #expect(WorkspaceController.Tool.allCases.filter(\.isAvailable).count == 9)
    #expect(WorkspaceController.Tool.allCases.filter { $0.shortcut != nil }.count == 9)
}

// ADR-0027 / plan 2026-08-28-unificare-nota-e-testo-in-un-solo-strume, Task 1 (R-01, R-02).
// Red until `case note` and its four exhaustive arms are removed from `Tool` and
// `Tool.TapBehaviour`. Do not weaken: these assert the *positive* shape of the
// unification, not just the stale counts above.

@MainActor
@Test func exactlyOneToolCreatesATextCardAndItIsTestoWithTheDocumentedShortcut() {
    // R-01: "The Workspace toolbar has exactly one tool that creates a `.text` card."
    // Operationalized as "creates a *blank* `.text`-kind card from an empty board tap":
    // `.createFreeText` always does (Testo), and `.createSticky(seed)` does only when
    // `seed` is empty - which is exactly `.note`'s tapBehaviour today
    // (`WorkspaceController+Tools.swift:32`, `.createSticky("")`) and precisely what this
    // task removes. `.todo`'s `.createSticky("- [ ] ")` is deliberately excluded: its seed
    // is non-empty, so it is a checklist tool, not a contender for "the" blank-text-card
    // tool, and is asserted separately below as an invariant this task must not disturb.
    // Before `.note` is removed this matches two tools (`.note`, `.text`); it must match
    // exactly one (`.text`) once it is.
    let blankTextCardTools = WorkspaceController.Tool.allCases.filter {
        switch $0.tapBehaviour {
        case .createFreeText: true
        case .createSticky(let seed): seed.isEmpty
        default: false
        }
    }
    #expect(blankTextCardTools == [.text])
    #expect(WorkspaceController.Tool.text.title == "Testo")
    #expect(WorkspaceController.Tool.text.symbol == "textformat")
    #expect(WorkspaceController.Tool.text.shortcut == "t")
}

@MainActor
@Test func noToolCarriesTheFreedNShortcut() {
    // R-01: "the `n` shortcut is freed and assigned to nothing" - not reassigned to any
    // other tool either.
    #expect(WorkspaceController.Tool.allCases.allSatisfy { $0.shortcut != "n" })
}

@MainActor
@Test func todoTapBehaviourStillCreatesAStickyWithItsChecklistPrefix() {
    // Guard against C2's mistake: deleting `.note` must not take `addStickyNote` down
    // with it, since `.todo` is its other caller. `TapBehaviour` is not `Equatable`
    // (WorkspaceController+Tools.swift:14), so this pattern-matches instead of `==`.
    guard case .createSticky(let seed) = WorkspaceController.Tool.todo.tapBehaviour else {
        Issue.record("Tool.todo.tapBehaviour is no longer .createSticky")
        return
    }
    #expect(seed == "- [ ] ")
}

@MainActor
@Test func addFreeTextStillProducesAnUncoloredDefaultSizedCardThatColoreCanStillPaint() throws {
    // R-02: "Creating a card with the unified tool always produces a plain (uncolored)
    // card; the existing 'Colore' command still changes its background afterward."
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let id = controller.addFreeText("qualsiasi", at: CGPoint(x: 10, y: 20))
    let created = try #require(controller.document.node(id: id))
    #expect(created.color == nil)
    #expect(created.width == 220)
    #expect(created.height == 60)

    controller.setColor(.preset(3), forNodeIDs: [id])
    #expect(controller.document.node(id: id)?.color == .preset(3))

    controller.detach()
}

@Test func writesPathsWithUnescapedSlashes() throws {
    // `\/` is legal JSON, but Obsidian does not write it, and a vault where every
    // path is escaped differently depending on which app saved last produces a diff
    // on every save.
    var board = CanvasDocument()
    board.nodes.append(CanvasNode(
        id: "a", kind: .file(path: "01 Progetti/vibrofer-emea/nota.md", subpath: nil),
        x: 0, y: 0, width: 10, height: 10
    ))
    let text = String(decoding: try board.encoded(), as: UTF8.self)
    #expect(text.contains("01 Progetti/vibrofer-emea/nota.md"))
    #expect(!text.contains("\\/"))
}
