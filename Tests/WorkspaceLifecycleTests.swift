import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// ADR-0066 (PG-255, #569 chain 2, #506): every per-board transient state has one reset
// door, and every leave path settles then flushes. Each test below pins one leave path or
// one boundary this chain closed, and is red against the pre-fix code (see the ADR's own
// diff, e.g. `detach()` used to call `endCrop(confirm: true)` alone).

// MARK: - Item 1: crop confirmed, then detach()

@MainActor
@Test func cropConfirmedThenDetachWritesTheCropToDisk() throws {
    // Pre-fix: `detach()` only called `endCrop(confirm: true)`, which schedules the ~1 s
    // autosave debounce and returns - it does not write. `detach()` then cancelled
    // `saveTask` without flushing, so a crop confirmed a moment earlier never reached disk.
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let boardPath = controller.board
    let id = controller.placeFile("img.png", at: .zero)

    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 100, height: 100))
    controller.updateCrop(handle: .bottomRight, translation: CGSize(width: -20, height: -20), lockAspect: false)
    #expect(controller.endCrop(confirm: true))
    // Confirming a crop only *schedules* the autosave - it must still be pending here,
    // which is exactly the window the pre-fix bug lost.
    #expect(controller.hasUnsavedChanges)

    controller.detach()

    let store = CanvasStore(root: root.url)
    let onDisk = try store.load(board: boardPath)
    let node = try #require(onDisk.node(id: id))
    #expect(node.unknown[CanvasCrop.key] != nil)
}

// MARK: - Item 2: ink drawn on board A, then open(board: B)

@MainActor
@Test func openingAnotherBoardCommitsInkToTheOriginalBoardsFolderAndClearsTheDrawingSession() throws {
    // Pre-fix: `load(board:)` confirmed only the crop before flushing, so `activeDrawing`
    // survived the switch and a stroke drawn on A was written into B's folder the next
    // time it was confirmed.
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("A")
    try root.makeDirectory("B")
    let store = CanvasStore(root: root.url)
    let boardA = try store.createBoard(named: "A", in: "A")
    let boardB = try store.createBoard(named: "B", in: "B")
    let controller = WorkspaceController()
    controller.attach(to: store)
    controller.open(board: boardA)

    controller.beginStroke(at: CGPoint(x: 0, y: 0), color: "#000000", width: 2, opacity: 1)
    controller.extendStroke(to: CGPoint(x: 50, y: 50))
    #expect(!controller.activeDrawing.strokes.isEmpty)

    controller.open(board: boardB)

    #expect(controller.activeDrawing.strokes.isEmpty)
    #expect(controller.editingDrawingNodeID == nil)

    let onDiskA = try store.load(board: boardA)
    #expect(onDiskA.nodes.count == 1)
    guard case .file(let path, _) = onDiskA.nodes.first?.kind else {
        Issue.record("expected the committed drawing's file node on board A")
        return
    }
    #expect(path.hasPrefix("A/"))
    #expect(path.hasSuffix(".svg"))
    #expect(FileManager.default.fileExists(
        atPath: root.url.appending(path: path).path(percentEncoded: false)
    ))

    let onDiskB = try store.load(board: boardB)
    #expect(onDiskB.nodes.isEmpty)
    controller.detach()
}

// MARK: - Item 3: text/title edit open, then open(board:)/select(nil)/detach()

@MainActor
@Test func openingAnotherBoardCommitsAPendingTextEditAndClearsTheEditingID() throws {
    // Pre-fix: `load(board:)` never touched `editingTextNodeID`/`editingTextDraft`, so the
    // draft was neither committed nor cleared.
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("A")
    try root.makeDirectory("B")
    let store = CanvasStore(root: root.url)
    let boardA = try store.createBoard(named: "A", in: "A")
    let boardB = try store.createBoard(named: "B", in: "B")
    let controller = WorkspaceController()
    controller.attach(to: store)
    controller.open(board: boardA)

    let id = controller.addStickyNote("appunto", at: .zero)
    controller.beginTextEdit(nodeID: id)
    controller.editingTextDraft = "modificato"

    controller.open(board: boardB)

    #expect(controller.editingTextNodeID == nil)
    let onDiskA = try store.load(board: boardA)
    let node = try #require(onDiskA.node(id: id))
    #expect(node.kind == .text("modificato"))
    controller.detach()
}

@MainActor
@Test func selectingNilCommitsAPendingTitleEditAndClearsTheEditingID() throws {
    // Pre-fix: the folder/nil branch of `select(_:)` called `endCrop(confirm: true)` alone,
    // so a title draft was discarded (never committed) and the id was left dangling because
    // `document`/`current` are wiped by the very call this test exercises.
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let boardPath = controller.board
    let id = controller.addLink("https://example.com", at: .zero)
    controller.beginTitleEdit(nodeID: id)
    controller.editingTitleDraft = "Documentazione"

    controller.select(nil)

    #expect(controller.editingTitleNodeID == nil)
    let store = CanvasStore(root: root.url)
    let onDisk = try store.load(board: boardPath)
    let node = try #require(onDisk.node(id: id))
    #expect(LinkCardTitle.read(from: node) == "Documentazione")
    controller.detach()
}

@MainActor
@Test func leavingForAFolderOrDetachingLeavesNothingToUndo() throws {
    // The settle on leave commits through `mutate`, which records a history step. `load`
    // resets the history for the board it opens, but the folder/nil branch of `select(_:)`
    // and `detach()` open none: without their own reset «Annulla» stayed enabled with no
    // board on screen, and an undo scheduled a save to `board == ""` (review of ADR-0066).
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let id = controller.addStickyNote("appunto", at: .zero)
    controller.flushPendingSave()
    controller.beginTextEdit(nodeID: id)
    controller.editingTextDraft = "modificato"

    controller.select(nil)

    #expect(!controller.canUndo)
    #expect(!controller.undo())
    #expect(controller.saveState == .saved)

    // A second vault: `createBoard` refuses a name the first one already holds.
    let secondRoot = try CanvasTemporaryRoot()
    let second = try openedWorkspaceController(rootURL: secondRoot.url)
    let secondID = second.addStickyNote("altro", at: .zero)
    second.beginTextEdit(nodeID: secondID)
    second.editingTextDraft = "cambiato"

    second.detach()

    #expect(!second.canUndo)
}

@MainActor
@Test func detachCommitsAPendingTextEditAndClearsTheEditingID() throws {
    // Pre-fix: `detach()` called `endCrop(confirm: true)` alone, so a text-edit draft was
    // lost entirely - neither written nor visible in `document` (which `detach()` wipes).
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let boardPath = controller.board
    let id = controller.addStickyNote("appunto", at: .zero)
    controller.beginTextEdit(nodeID: id)
    controller.editingTextDraft = "modificato"

    controller.detach()

    #expect(controller.editingTextNodeID == nil)
    let store = CanvasStore(root: root.url)
    let onDisk = try store.load(board: boardPath)
    let node = try #require(onDisk.node(id: id))
    #expect(node.kind == .text("modificato"))
}

// MARK: - Item 4: a title edit, then beginTextEdit on another card

@MainActor
@Test func beginTextEditCommitsAnOpenTitleEditFirst() throws {
    // Pre-fix: `beginTextEdit` only closed an open crop, never an open title edit - a
    // rename left mid-edit and abandoned for a sticky note was silently lost.
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let linkID = controller.addLink("https://example.com", at: .zero)
    controller.beginTitleEdit(nodeID: linkID)
    controller.editingTitleDraft = "Documentazione"

    let textID = controller.addStickyNote("appunto", at: CGPoint(x: 300, y: 0))
    controller.beginTextEdit(nodeID: textID)

    #expect(controller.editingTitleNodeID == nil)
    #expect(controller.editingTextNodeID == textID)
    let linkNode = try #require(controller.document.node(id: linkID))
    #expect(LinkCardTitle.read(from: linkNode) == "Documentazione")
    controller.detach()
}

// MARK: - Item 5: delete of a node mid text/title/crop/drawing edit

@MainActor
@Test func deletingANodeInTextEditClearsTheSessionWithoutWritingTheDraft() throws {
    // Pre-fix: `delete(nodeIDs:)` never touched the editing ids, leaving
    // `editingTextNodeID` naming a node the very call being tested just removed.
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let id = controller.addStickyNote("appunto", at: .zero)
    controller.beginTextEdit(nodeID: id)
    controller.editingTextDraft = "scartato"

    controller.delete(nodeIDs: [id])

    #expect(controller.editingTextNodeID == nil)
    #expect(controller.editingTextDraft.isEmpty)
    #expect(controller.document.node(id: id) == nil)
    controller.detach()
}

@MainActor
@Test func deletingANodeInTitleEditClearsTheSessionWithoutWritingTheDraft() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let id = controller.addLink("https://example.com", at: .zero)
    controller.beginTitleEdit(nodeID: id)
    controller.editingTitleDraft = "scartato"

    controller.delete(nodeIDs: [id])

    #expect(controller.editingTitleNodeID == nil)
    #expect(controller.editingTitleDraft.isEmpty)
    #expect(controller.document.node(id: id) == nil)
    controller.detach()
}

@MainActor
@Test func deletingANodeInCropModeEndsTheCropWithoutCommittingIt() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let id = controller.placeFile("img.png", at: .zero)
    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 100, height: 100))
    controller.updateCrop(handle: .bottomRight, translation: CGSize(width: -20, height: -20), lockAspect: false)

    controller.delete(nodeIDs: [id])

    #expect(controller.croppingNodeID == nil)
    #expect(controller.document.node(id: id) == nil)
    controller.detach()
}

@MainActor
@Test func deletingANodeBeingDrawnOnClearsTheDrawingSessionAndDiscardsTheStrokes() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let id = controller.placeFile("A/disegno.svg", at: .zero, creatingOnDisk: nil)
    controller.editingDrawingNodeID = id
    controller.beginStroke(at: .zero, color: "#000000", width: 2, opacity: 1)
    controller.extendStroke(to: CGPoint(x: 10, y: 10))

    controller.delete(nodeIDs: [id])

    #expect(controller.editingDrawingNodeID == nil)
    #expect(controller.activeDrawing.strokes.isEmpty)
    #expect(controller.document.node(id: id) == nil)
    controller.detach()
}

// MARK: - Item 6: isEditingText

@MainActor
@Test func isEditingTextIsTrueWhileATitleEditIsOpen() throws {
    // Pre-fix: `BoardChrome` (and this door, had it existed) checked `editingTextNodeID`
    // only, so a link card's own title field never suspended the bare-key tool shortcuts.
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    #expect(!controller.isEditingText)

    let id = controller.addLink("https://example.com", at: .zero)
    controller.beginTitleEdit(nodeID: id)

    #expect(controller.isEditingText)
    controller.endTitleEdit(commit: false)
    #expect(!controller.isEditingText)
    controller.detach()
}

// MARK: - Item 7: VaultBoundary on subfolder(for:)/editDrawing/commitDrawing

@MainActor
@Test func subfolderRefusesAPathEscapingTheVault() throws {
    // Pre-fix: `subfolder(for:)` resolved `store.root.appending(path:)` directly, with no
    // boundary check.
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let node = CanvasNode(
        id: "escaping", kind: .file(path: "../../x", subpath: nil),
        x: 0, y: 0, width: 10, height: 10
    )

    #expect(controller.subfolder(for: node) == nil)
    controller.detach()
}

@MainActor
@Test func aFileCardWithAnEmptyPathStillResolvesToTheVaultRoot() throws {
    // Pinned separately from the escaping-path test above: `""` is a legitimate folder
    // card (the vault root itself, ADR-0053 §D3, WorkspaceEnterFolderTests:221) and must
    // not be refused by the same boundary check that refuses `../../x`.
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let node = CanvasNode(
        id: "root", kind: .file(path: "", subpath: nil), x: 0, y: 0, width: 10, height: 10
    )

    #expect(controller.subfolder(for: node) == "")
    controller.detach()
}

@MainActor
@Test func editDrawingRefusesAPathEscapingTheVault() throws {
    // Pre-fix: `editDrawing` read `store.root.appending(path:)` directly.
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let id = controller.placeFile("../outside.svg", at: .zero)

    #expect(controller.editDrawing(nodeID: id) == false)
    controller.detach()
}

@MainActor
@Test func commitDrawingRefusesToRepointAPathEscapingTheVaultAndWritesNothingOutsideIt() throws {
    // Pre-fix: `commitDrawing` wrote through `store.root.appending(path: relativePath)`
    // with no boundary check, so a hand-edited node whose `file` climbed out of the vault
    // had its SVG written there.
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let id = controller.placeFile("../../escaped.svg", at: .zero)
    controller.editingDrawingNodeID = id
    controller.beginStroke(at: .zero, color: "#000000", width: 2, opacity: 1)
    controller.extendStroke(to: CGPoint(x: 10, y: 10))

    let result = controller.commitDrawing()

    #expect(result == nil)
    let escaped = root.url.deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "escaped.svg")
    #expect(!FileManager.default.fileExists(atPath: escaped.path(percentEncoded: false)))
    controller.detach()
}

@MainActor
@Test func commitImportRefusesAProposedNameEscapingTheVaultAndWritesNothingOutsideIt() throws {
    // Pre-fix: `commitImport` joined `directory.appending(path: proposal.proposedName)`
    // directly, so an edited proposal spelled to climb out of the folder climbed out of
    // the vault too.
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let sourceURL = root.url.appending(path: "source.txt")
    try Data("hello".utf8).write(to: sourceURL)
    let proposal = WorkspaceController.ImportProposal(
        source: sourceURL, originalName: "source.txt", proposedName: "../../escaped.txt", point: .zero
    )

    let id = controller.commitImport(proposal)

    #expect(id == nil)
    let escaped = root.url.deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "escaped.txt")
    #expect(!FileManager.default.fileExists(atPath: escaped.path(percentEncoded: false)))
    controller.detach()
}

// MARK: - Item 8: detach() cancels a pending refit

@MainActor
@Test func detachCancelsAPendingRefitAndLeavesPanAndZoomUntouched() async throws {
    // Pre-fix: `detach()` cancelled `saveTask` but not `refitTask`/`pendingRefit`, so a
    // debounced refit still fired ~350 ms later against the now-empty document and reset
    // the viewport out from under whatever the person had navigated to next.
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    _ = controller.addStickyNote("a", at: CGPoint(x: 500, y: 500))
    controller.pan = CGSize(width: 123, height: 45)
    controller.zoom = 1.5
    controller.requestRefit(.fit)
    controller.applyPendingRefit(in: CGSize(width: 800, height: 600))
    let panBefore = controller.pan
    let zoomBefore = controller.zoom

    controller.detach()

    try await Task.sleep(for: .milliseconds(400))

    #expect(controller.pan == panBefore)
    #expect(controller.zoom == zoomBefore)
}

// MARK: - Item 9: ImportNaming.uniqueFileName(reserved:) and importFiles collisions

@Test func uniqueFileNameAvoidsNamesAlreadyReservedInTheSameDropCaseInsensitively() throws {
    let root = try CanvasTemporaryRoot()
    // Nothing on disk: the collision is with `reserved` alone.
    let name = ImportNaming.uniqueFileName("Foto.jpg", in: root.url, reserved: ["foto.jpg"])
    #expect(name == "Foto-2.jpg")
}

@MainActor
@Test func importFilesOfTwoSameNamedURLsFromDifferentSourceDirsProducesDistinctNames() throws {
    // Pre-fix: `uniqueFileName` asked disk alone, per file, in the same loop - nothing
    // written yet - so two same-named files in one drop both proposed "Foto.jpg".
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let sourceOne = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-import-one-\(UUID().uuidString)", directoryHint: .isDirectory)
    let sourceTwo = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-import-two-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: sourceOne, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: sourceTwo, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: sourceOne)
        try? FileManager.default.removeItem(at: sourceTwo)
    }
    let urlOne = sourceOne.appending(path: "Foto.jpg")
    let urlTwo = sourceTwo.appending(path: "Foto.jpg")
    try Data("uno".utf8).write(to: urlOne)
    try Data("due".utf8).write(to: urlTwo)

    let proposals = controller.importFiles([urlOne, urlTwo], at: .zero)

    #expect(proposals.count == 2)
    let names = proposals.map(\.proposedName)
    #expect(Set(names).count == 2)
    #expect(names.contains("Foto.jpg"))
    #expect(names.contains("Foto-2.jpg"))
    controller.detach()
}

// MARK: - Item 10: BoardDragPayload requires its separator

@Test func boardDragPayloadRejectsPlainTextWithNoSeparator() {
    // Pre-fix: `init?(text:)` accepted any non-empty string as a bare `path` with no
    // column, so a word dragged in from another app was read as a card to move.
    #expect(BoardDragPayload(text: "word") == nil)
}

@Test func boardDragPayloadStillRoundTripsItsOwnText() throws {
    let payload = BoardDragPayload(path: "Vibrofer/Vibrofer.canvas", column: "In corso")
    let parsed = try #require(BoardDragPayload(text: payload.text))
    #expect(parsed.path == "Vibrofer/Vibrofer.canvas")
    #expect(parsed.column == "In corso")

    let noColumn = BoardDragPayload(path: "Vibrofer/Vibrofer.canvas", column: nil)
    let parsedNoColumn = try #require(BoardDragPayload(text: noColumn.text))
    #expect(parsedNoColumn.path == "Vibrofer/Vibrofer.canvas")
    #expect(parsedNoColumn.column == nil)
}

// MARK: - Item 11: settleForTermination()

@MainActor
@Test func settleForTerminationWritesAPendingEditToDisk() throws {
    // Pre-fix: nothing flushed the autosave debounce on quit (#506) - the controller was
    // unreachable from `AppDelegate`, and this door did not exist.
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let boardPath = controller.board
    let id = controller.addStickyNote("appunto", at: .zero)
    #expect(controller.hasUnsavedChanges)

    controller.settleForTermination()

    #expect(controller.saveState == .saved)
    let store = CanvasStore(root: root.url)
    let onDisk = try store.load(board: boardPath)
    #expect(onDisk.node(id: id) != nil)
    controller.detach()
}

@MainActor
@Test func settleForTerminationDoesNotWriteOverAConflictedBoard() async throws {
    // A conflicted board's write was already refused (ADR-0054 §D5); quitting must not
    // attempt it again and clobber the other writer's bytes.
    let vault = try TemporaryVault()
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)
    let store = CanvasStore(root: vault.root)
    let boardPath = try store.createBoard(named: "board", in: "")
    let controller = WorkspaceController()
    controller.attach(to: store, vault: vaultController)
    controller.open(board: boardPath)
    _ = controller.addStickyNote("nota", at: .zero)

    let externalStore = CanvasStore(root: vault.root)
    var diverged = try externalStore.load(board: boardPath)
    diverged.nodes.append(CanvasNode(
        id: "external", kind: .text("altro"), x: 400, y: 400, width: 100, height: 60
    ))
    try externalStore.save(diverged, board: boardPath)

    controller.flushPendingSave()
    guard case .conflicted = controller.saveState else {
        Issue.record("setup expected .conflicted, got \(controller.saveState)")
        return
    }
    let diskBytesAtConflict = try Data(contentsOf: store.url(forBoard: boardPath))

    controller.settleForTermination()

    let diskBytesAfter = try Data(contentsOf: store.url(forBoard: boardPath))
    #expect(diskBytesAfter == diskBytesAtConflict)
    guard case .conflicted = controller.saveState else {
        Issue.record("expected to remain .conflicted, got \(controller.saveState)")
        return
    }

    controller.detach()
    vaultController.close()
}

// MARK: - PG-288: settleForVerb()

/// A board whose open document has diverged from the disk and whose save was refused into
/// `.conflicted` (ADR-0054 §D5), plus the id of a sticky note on it. Answers nil, having
/// recorded the issue, when the setup does not reach `.conflicted`.
@MainActor
private func conflictedBoard(
    vault: borrowing TemporaryVault, vaultController: VaultController
) throws -> (controller: WorkspaceController, board: String, nodeID: String)? {
    let store = CanvasStore(root: vault.root)
    let boardPath = try store.createBoard(named: "board", in: "")
    let controller = WorkspaceController()
    controller.attach(to: store, vault: vaultController)
    controller.open(board: boardPath)
    let id = controller.addStickyNote("nota", at: .zero)

    let externalStore = CanvasStore(root: vault.root)
    var diverged = try externalStore.load(board: boardPath)
    diverged.nodes.append(CanvasNode(
        id: "external", kind: .text("altro"), x: 400, y: 400, width: 100, height: 60
    ))
    try externalStore.save(diverged, board: boardPath)

    controller.flushPendingSave()
    guard case .conflicted = controller.saveState else {
        Issue.record("setup expected .conflicted, got \(controller.saveState)")
        controller.detach()
        return nil
    }
    return (controller, boardPath, id)
}

@MainActor
@Test func settleForVerbOnAConflictedBoardRefusesAndCommitsNoOpenSession() async throws {
    // Pre-fix (PG-288): the sidebar verbs ran `flushBoard()` - a full settle - before
    // `canLeaveOpenBoardForVerb()`, so a refused verb still merged the open text draft
    // into the conflicted board's document on the way out.
    let vault = try TemporaryVault()
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)
    guard let setup = try conflictedBoard(vault: vault, vaultController: vaultController) else {
        vaultController.close()
        return
    }
    let controller = setup.controller
    let id = setup.nodeID
    controller.beginTextEdit(nodeID: id)
    controller.editingTextDraft = "modificato"

    #expect(controller.settleForVerb() == false)

    #expect(controller.editingTextNodeID == id)
    #expect(controller.editingTextDraft == "modificato")
    let node = try #require(controller.document.node(id: id))
    #expect(node.kind == .text("nota"))
    guard case .conflicted = controller.saveState else {
        Issue.record("expected to remain .conflicted, got \(controller.saveState)")
        return
    }

    controller.detach()
    vaultController.close()
}

@MainActor
@Test func settleForVerbOnACleanBoardCommitsTheOpenSessionAndFlushesIt() throws {
    // The other half of the door: a board that may be left still settles and flushes
    // before the verb touches disk (ADR-0022 §F10, ADR-0066).
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let boardPath = controller.board
    let id = controller.addStickyNote("appunto", at: .zero)
    controller.beginTextEdit(nodeID: id)
    controller.editingTextDraft = "modificato"

    #expect(controller.settleForVerb())

    #expect(controller.editingTextNodeID == nil)
    #expect(controller.saveState == .saved)
    let onDisk = try CanvasStore(root: root.url).load(board: boardPath)
    let node = try #require(onDisk.node(id: id))
    #expect(node.kind == .text("modificato"))
    controller.detach()
}

@MainActor
@Test func settleForVerbRefusesWhenItsOwnFlushEntersConflicted() async throws {
    // The second guard: the board was not conflicted when the verb asked, but the flush's
    // write is refused against another writer's bytes, and the file must not move out
    // from under that fresh conflict.
    let vault = try TemporaryVault()
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)
    let store = CanvasStore(root: vault.root)
    let boardPath = try store.createBoard(named: "board", in: "")
    let controller = WorkspaceController()
    controller.attach(to: store, vault: vaultController)
    controller.open(board: boardPath)
    _ = controller.addStickyNote("nota", at: .zero)
    var diverged = try CanvasStore(root: vault.root).load(board: boardPath)
    diverged.nodes.append(CanvasNode(
        id: "external", kind: .text("altro"), x: 400, y: 400, width: 100, height: 60
    ))
    try CanvasStore(root: vault.root).save(diverged, board: boardPath)
    #expect(controller.saveState != .saved)

    #expect(controller.settleForVerb() == false)

    guard case .conflicted = controller.saveState else {
        Issue.record("expected .conflicted, got \(controller.saveState)")
        return
    }
    controller.detach()
    vaultController.close()
}

// MARK: - Item 12: the two new sticky tokens in both bundled themes

@Test func bothBundledThemesDefineTheTwoNewStickyColorTokens() throws {
    for id in ["pergamenum-light", "pergamenum-dark"] {
        let url = try #require(
            Bundle.pergamenumResources.tokenFileURL(named: id),
            "\(id).json is not in the bundle"
        )
        let document = try DesignTokenDocument(data: try Data(contentsOf: url), fallbackName: id)
        let theme = Theme(document: document, id: id, inheriting: .emergency)

        #expect(!theme.inheritedTokens.contains("color.sticky.orange"), "\(id) should define color.sticky.orange")
        #expect(!theme.inheritedTokens.contains("color.sticky.purple"), "\(id) should define color.sticky.purple")
    }
}
