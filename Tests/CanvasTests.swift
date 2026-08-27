import Foundation
import Testing
@testable import Pergamenum

/// A canvas as Obsidian writes one: every node type, an edge, preset and hex colours.
private let obsidianCanvas = """
{
  "nodes": [
    {"id":"a1","type":"text","x":-260,"y":-120,"width":250,"height":60,"text":"Nota adesiva","color":"3"},
    {"id":"b2","type":"file","x":40,"y":-120,"width":400,"height":400,"file":"01 Progetti/Nota.md"},
    {"id":"c3","type":"file","x":40,"y":320,"width":400,"height":400,"file":"03 Risorse/doc.pdf","subpath":"#Sezione"},
    {"id":"d4","type":"link","x":-260,"y":40,"width":250,"height":80,"url":"https://jsoncanvas.org"},
    {"id":"e5","type":"group","x":-300,"y":-160,"width":800,"height":600,"label":"Zona","color":"#FF0000"}
  ],
  "edges": [
    {"id":"x1","fromNode":"a1","fromSide":"right","toNode":"b2","toSide":"left","label":"porta a","color":"2"}
  ]
}
"""

@Test func decodesEveryNodeTypeOfTheSpec() throws {
    let canvas = try CanvasDocument(data: Data(obsidianCanvas.utf8))
    #expect(canvas.nodes.count == 5)
    #expect(canvas.edges.count == 1)

    #expect(canvas.node(id: "a1")?.kind == .text("Nota adesiva"))
    #expect(canvas.node(id: "a1")?.color == .preset(3))
    #expect(canvas.node(id: "b2")?.kind == .file(path: "01 Progetti/Nota.md", subpath: nil))
    #expect(canvas.node(id: "c3")?.kind == .file(path: "03 Risorse/doc.pdf", subpath: "#Sezione"))
    #expect(canvas.node(id: "d4")?.kind == .link(url: "https://jsoncanvas.org"))
    #expect(canvas.node(id: "e5")?.kind == .group(label: "Zona"))
    #expect(canvas.node(id: "e5")?.color == .hex("#FF0000"))

    let edge = try #require(canvas.edges.first)
    #expect(edge.fromSide == .right)
    #expect(edge.toSide == .left)
    #expect(edge.label == "porta a")
}

@Test func roundTripsAnObsidianCanvasWithoutLosingAnything() throws {
    // The M2 acceptance criterion in one test: what Obsidian wrote must survive a
    // decode/encode cycle here, property for property.
    let original = try CanvasDocument(data: Data(obsidianCanvas.utf8))
    let reDecoded = try CanvasDocument(data: try original.encoded())
    #expect(reDecoded == original)
}

@Test func preservesPropertiesItDoesNotUnderstand() throws {
    // SPEC §6.2: another app's extra keys are ignored, never dropped.
    let canvas = """
    {
      "nodes": [{"id":"a","type":"text","x":0,"y":0,"width":10,"height":10,"text":"t",
                 "someOtherApp.flag":true,"styleAttributes":{"opacity":0.5}}],
      "edges": [{"id":"e","fromNode":"a","toNode":"a","futureProperty":42}],
      "metadata": {"createdBy": "another tool"}
    }
    """
    let decoded = try CanvasDocument(data: Data(canvas.utf8))
    #expect(decoded.nodes[0].unknown["someOtherApp.flag"] == .bool(true))
    #expect(decoded.edges[0].unknown["futureProperty"] == .number(42))
    #expect(decoded.unknown["metadata"] != nil)

    let written = try JSONSerialization.jsonObject(with: try decoded.encoded()) as? [String: Any]
    let node = (written?["nodes"] as? [[String: Any]])?.first
    #expect(node?["someOtherApp.flag"] as? Bool == true)
    #expect(node?["styleAttributes"] != nil)
    #expect(written?["metadata"] != nil)
}

@Test func keepsNodesOfAnUnknownType() throws {
    // A canvas from a newer tool must not lose nodes just because this app does not
    // know how to draw them.
    let canvas = """
    {"nodes":[{"id":"z","type":"futuretype","x":1,"y":2,"width":3,"height":4,"payload":"x"}],"edges":[]}
    """
    let decoded = try CanvasDocument(data: Data(canvas.utf8))
    #expect(decoded.nodes.count == 1)
    #expect(decoded.nodes[0].kind == .unknown(type: "futuretype"))

    let reDecoded = try CanvasDocument(data: try decoded.encoded())
    #expect(reDecoded.nodes[0].typeName == "futuretype")
    #expect(reDecoded.nodes[0].unknown["payload"] == .string("x"))
}

@Test func treatsAnEmptyFileAsAnEmptyCanvas() throws {
    // Obsidian creates a new canvas as a zero-byte file; refusing it would strand
    // the board.
    let canvas = try CanvasDocument(data: Data())
    #expect(canvas.nodes.isEmpty)
    #expect(canvas.edges.isEmpty)
}

@Test func rejectsAFileThatIsNotACanvas() {
    #expect(throws: CanvasDocument.DecodingError.self) {
        _ = try CanvasDocument(data: Data("[1,2,3]".utf8))
    }
    #expect(throws: CanvasDocument.DecodingError.self) {
        _ = try CanvasDocument(data: Data("non json".utf8))
    }
}

@Test func dropsOnlyMalformedEntries() throws {
    // A node with no id cannot be addressed by an edge and cannot be written back
    // meaningfully; the rest of the canvas still opens.
    let canvas = """
    {"nodes":[{"type":"text","x":0,"y":0,"width":1,"height":1,"text":"senza id"},
              {"id":"ok","type":"text","x":0,"y":0,"width":1,"height":1,"text":"buono"}],
     "edges":[{"id":"bad","fromNode":"ok"}]}
    """
    let decoded = try CanvasDocument(data: Data(canvas.utf8))
    #expect(decoded.nodes.map(\.id) == ["ok"])
    #expect(decoded.edges.isEmpty)
}

@Test(arguments: ["0", "7", "-1", "abc", "#GGGGGG", ""])
func rejectsInvalidColours(_ raw: String) {
    // The spec allows presets 1 to 6 or a hex value; anything else is not a colour.
    #expect(CanvasColor(raw) == nil)
}

@Test func acceptsValidColours() {
    #expect(CanvasColor("1") == .preset(1))
    #expect(CanvasColor("6") == .preset(6))
    #expect(CanvasColor("#9A5B1F") == .hex("#9A5B1F"))
}

@Test func distinguishesBooleanFromNumberOnRoundTrip() throws {
    // NSNumber carries both; writing `1` where the file had `true` would corrupt
    // another app's settings.
    let canvas = """
    {"nodes":[{"id":"a","type":"text","x":0,"y":0,"width":1,"height":1,"text":"t","flag":true,"count":1}],"edges":[]}
    """
    let decoded = try CanvasDocument(data: Data(canvas.utf8))
    #expect(decoded.nodes[0].unknown["flag"] == .bool(true))
    #expect(decoded.nodes[0].unknown["count"] == .number(1))

    let written = try JSONSerialization.jsonObject(with: try decoded.encoded()) as? [String: Any]
    let node = (written?["nodes"] as? [[String: Any]])?.first
    #expect(node?["flag"] as? Bool == true)
    #expect((node?["count"] as? NSNumber)?.doubleValue == 1)
}

// MARK: - Folder creation, and the fixture every store test builds on
//
// The five tests that pinned the folder→board mapping (`boardPath(forFolder:)`,
// `load(folder:)`, `save(_:folder:)`, `contents(ofFolder:board:)`) are gone with the API
// they exercised - ADR-0025 §D1 deletes it rather than deprecating it. Their subject is
// re-asserted against the path-addressing shape below.

private struct TemporaryRoot: ~Copyable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-canvas-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func makeDirectory(_ relativePath: String) throws {
        try FileManager.default.createDirectory(
            at: url.appending(path: relativePath, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }

    func makeFile(_ relativePath: String, _ contents: String = "x") throws {
        let fileURL = url.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: fileURL)
    }
}

@Test func createsARealDirectoryForAFolderCard() throws {
    let root = try TemporaryRoot()
    try root.makeDirectory("01 Progetti")
    let store = CanvasStore(root: root.url)

    let path = try store.createFolder(named: "Nuova", in: "01 Progetti")
    #expect(path == "01 Progetti/Nuova")

    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(
        atPath: root.url.appending(path: path).path(percentEncoded: false), isDirectory: &isDirectory
    )
    #expect(exists)
    #expect(isDirectory.boolValue)

    // Creating it twice must fail rather than silently succeed on an existing
    // folder, which would let two cards claim the same directory.
    var secondAttemptFailed = false
    do {
        _ = try store.createFolder(named: "Nuova", in: "01 Progetti")
    } catch is CanvasStore.StoreError {
        secondAttemptFailed = true
    }
    #expect(secondAttemptFailed)
}

@Test func refusesAFolderWhoseParentDoesNotExist() throws {
    // `createFolder` deliberately does not create intermediate directories: a card
    // dropped on a board whose folder vanished must fail loudly, not resurrect it.
    let root = try TemporaryRoot()
    let store = CanvasStore(root: root.url)

    var failed = false
    do {
        _ = try store.createFolder(named: "Nuova", in: "cartella inesistente")
    } catch {
        failed = true
    }
    #expect(failed)
}

// MARK: - `CanvasStore` path-addressing API (ADR-0025 §D1, "A folder is a container, a
// board is a file, and neither is named after the other").
// Plan `docs/superpowers/plans/2026-08-27-workspace-folder-board-separation.md`, Task 1.
//
// `CanvasStore` is told a board's own path: `url(forBoard:)`, `load(board:)`,
// `save(_:board:)`, `contents(ofBoard:document:)`, `createBoard(named:in:)`,
// `boardNameIsAvailable(_:in:)`, `allFolders()` and `StoreError.missing(String)`. The
// folder-derived API these replace - `boardPath(forFolder:)`, `url(forFolder:)`,
// `load(folder:)`, `save(_:folder:)`, `contents(ofFolder:board:)` - is deleted, not
// deprecated: a rule that still exists is a rule a caller can still ask, and the failure
// it produces is a board that opens the wrong file, silently.

@Test func loadingAMissingBoardThrowsRatherThanReturningEmpty() throws {
    let root = try TemporaryRoot()
    let store = CanvasStore(root: root.url)

    do {
        _ = try store.load(board: "01 Progetti/assente.canvas")
        Issue.record("expected load(board:) to throw for a file that does not exist")
    } catch CanvasStore.StoreError.missing(let path) {
        #expect(path == "01 Progetti/assente.canvas")
    } catch {
        Issue.record("expected StoreError.missing, got \(error)")
    }
}

@Test func loadRoundTripsADocumentSavedAtAnArbitraryBoardPath() throws {
    let root = try TemporaryRoot()
    try root.makeDirectory("A")
    let store = CanvasStore(root: root.url)
    var board = CanvasDocument()
    board.nodes.append(CanvasNode(id: "a", kind: .text("ciao"), x: 10, y: 20, width: 200, height: 100))

    // The board's name carries no relationship to its folder's name (R-06) - the shape
    // this addressing model exists for.
    try store.save(board, board: "A/qualsiasi-nome.canvas")
    do {
        let reloaded = try store.load(board: "A/qualsiasi-nome.canvas")
        #expect(reloaded == board)
    } catch {
        Issue.record("expected load(board:) to round-trip what save(_:board:) just wrote, got \(error)")
    }
}

@Test func createBoardWritesAnEmptyCanvasAtTheChosenNameAndRefusesADuplicate() throws {
    let root = try TemporaryRoot()
    try root.makeDirectory("A")
    let store = CanvasStore(root: root.url)

    let path = try store.createBoard(named: "qualsiasi-nome", in: "A")
    #expect(path == "A/qualsiasi-nome.canvas")

    let fileURL = root.url.appending(path: "A/qualsiasi-nome.canvas", directoryHint: .notDirectory)
    #expect(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    if let data = try? Data(contentsOf: fileURL) {
        let written = try CanvasDocument(data: data)
        #expect(written == .empty)
    } else {
        Issue.record("expected createBoard to write an empty .canvas at \(fileURL.path(percentEncoded: false))")
    }

    // createBoard writes the file directly; it does not create a folder named after
    // the board (R-02's "does not create or require a same-named folder").
    let existsAtBareName = FileManager.default.fileExists(
        atPath: root.url.appending(path: "A/qualsiasi-nome").path(percentEncoded: false)
    )
    #expect(!existsAtBareName)

    do {
        _ = try store.createBoard(named: "qualsiasi-nome", in: "A")
        Issue.record("expected createBoard to refuse a name a .canvas in that folder already has")
    } catch CanvasStore.StoreError.alreadyExists(let existing) {
        #expect(existing.hasSuffix("qualsiasi-nome.canvas"))
    } catch {
        Issue.record("expected StoreError.alreadyExists, got \(error)")
    }
}

@Test func createBoardSucceedsBesideALikeNamedFolder() throws {
    let root = try TemporaryRoot()
    try root.makeDirectory("prova")
    let store = CanvasStore(root: root.url)

    // A folder and a sibling `.canvas` may share a name in the same parent (R-04) -
    // the pre-existing `prova/prova.canvas` shape, generalised to the vault root.
    let path = try store.createBoard(named: "prova", in: "")
    #expect(path == "prova.canvas")

    var isDirectory: ObjCBool = false
    let folderExists = FileManager.default.fileExists(
        atPath: root.url.appending(path: "prova").path(percentEncoded: false), isDirectory: &isDirectory
    )
    #expect(folderExists)
    #expect(isDirectory.boolValue)

    let boardExists = FileManager.default.fileExists(
        atPath: root.url.appending(path: "prova.canvas").path(percentEncoded: false)
    )
    #expect(boardExists)
}

@Test func boardNameIsAvailableAgreesWithCreateBoardWithoutWriting() throws {
    let root = try TemporaryRoot()
    try root.makeDirectory("A")
    let store = CanvasStore(root: root.url)
    _ = try store.createBoard(named: "occupato", in: "A")

    #expect(store.boardNameIsAvailable("occupato", in: "A") == false)
    #expect(store.boardNameIsAvailable("libero", in: "A") == true)

    // Checked live, without writing (the same relationship `FolderFileOperations
    // .nameIsAvailable` has to `createFolder`, ADR-0022 §D11): asking must not create
    // a file.
    #expect(!FileManager.default.fileExists(
        atPath: root.url.appending(path: "A/libero.canvas").path(percentEncoded: false)
    ))
}

@Test func allFoldersListsEveryDirectoryExcludingReservedOnesAndIncludingEmptyOnes() throws {
    let root = try TemporaryRoot()
    try root.makeDirectory("01 Progetti/vibrofer-emea")
    try root.makeDirectory("Vuota")
    try root.makeFile(".obsidian/config.json")
    try root.makeFile(".git/HEAD")
    try root.makeFile(".trash/nota.md")
    try root.makeFile(".pergamenum/state.json")
    let store = CanvasStore(root: root.url)

    let folders = store.allFolders()
    #expect(folders.contains("01 Progetti"))
    #expect(folders.contains("01 Progetti/vibrofer-emea"))
    // "Vuota" holds no `.canvas` at all - the assertion that proves the tree is not
    // built from `allBoards()` alone (R-10's precondition, checked here at the store
    // level).
    #expect(folders.contains("Vuota"))
    #expect(!folders.contains(".obsidian"))
    #expect(!folders.contains(".git"))
    #expect(!folders.contains(".trash"))
    #expect(!folders.contains(".pergamenum"))
    #expect(!folders.contains(where: { $0.hasPrefix(".obsidian/") }))
}

@Test func contentsOfBoardDerivesTheContainingFolderAndListsItsEntries() throws {
    let root = try TemporaryRoot()
    try root.makeDirectory("A/sotto")
    try root.makeFile("A/nota.md")
    try root.makeFile("A/uno.canvas")
    let store = CanvasStore(root: root.url)

    // A dropped file still lands beside the open board, in its containing folder (R-06).
    let contents = store.contents(ofBoard: "A/uno.canvas", document: .empty)
    #expect(contents.subfolders == ["A/sotto"])
    #expect(contents.unplaced.contains("A/nota.md"))
}

@Test func contentsOfBoardExcludesEveryCanvasFileNotOnlyTheOpenOne() throws {
    let root = try TemporaryRoot()
    try root.makeDirectory("A")
    try root.makeFile("A/uno.canvas")
    try root.makeFile("A/due.canvas")
    try root.makeFile("A/nota.md")
    let store = CanvasStore(root: root.url)

    let contents = store.contents(ofBoard: "A/uno.canvas", document: .empty)
    // A real, non-canvas entry proves the exclusion below is meaningful and not a
    // vacuously empty result.
    #expect(contents.unplaced.contains("A/nota.md"))
    // ADR-0025 §D10: the tray shows unplaced items, not a board switcher. Neither the
    // open board's own file nor a sibling `.canvas` belongs in `unplaced` (R-07) -
    // assert the sibling explicitly, since it already reaches the tray today (F5).
    #expect(!contents.unplaced.contains("A/uno.canvas"))
    #expect(!contents.unplaced.contains("A/due.canvas"))
}

@Test func createFolderStillCreatesADirectoryAndNoBoard() throws {
    let root = try TemporaryRoot()
    let store = CanvasStore(root: root.url)

    let path = try store.createFolder(named: "Nuova", in: "")
    #expect(path == "Nuova")

    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(
        atPath: root.url.appending(path: path).path(percentEncoded: false), isDirectory: &isDirectory
    )
    #expect(exists)
    #expect(isDirectory.boolValue)

    // R-01's store half: creating a folder must not implicitly write a same-named
    // board (the view half - deleting `WorkspaceView+FolderVerbs.swift`'s implicit
    // `save(.empty, folder:)` call - is Task 6).
    #expect(!FileManager.default.fileExists(
        atPath: root.url.appending(path: "Nuova.canvas").path(percentEncoded: false)
    ))
    #expect(!FileManager.default.fileExists(
        atPath: root.url.appending(path: "Nuova/Nuova.canvas").path(percentEncoded: false)
    ))
}

@Test func generatesIdsInTheShapeObsidianWrites() {
    let id = CanvasID.generate()
    #expect(id.count == 16)
    // Hoisted: `allSatisfy` is rethrows, and inside #expect's autoclosure the
    // compiler stops inferring that a key-path predicate cannot throw.
    let isHexadecimal = id.allSatisfy(\.isHexDigit)
    #expect(isHexadecimal)
    #expect(CanvasID.generate() != id)
}

// MARK: - `CanvasStore.allBoards()` (ADR-0021 "A task carries its Workspace and its place in a
// project as caret markers in its own line, and nothing new is stored anywhere else", §D10, R-01).
// Plan `docs/superpowers/plans/2026-08-24-workspace-tasks-notes-integration.md`, Task 6: the
// Workspace folder browser. D10 rejects putting `.canvas` files into `IndexSnapshot` (a version
// bump and a change to what every consumer of "a note" means) and enumerates them on demand
// instead, walking the vault the same way `VaultScanner.scan()` does and skipping the same
// excluded directories through `VaultLayout.isExcludedDirectory`.
//
// `CanvasStore.allBoards()` is a signature-only stub returning `[]` as of this commit: every
// test below is expected to fail red on its assertions, not to fail to compile.

@Test func allBoardsFindsNestedCanvasFilesAsSortedVaultRelativePaths() throws {
    let root = try TemporaryRoot()
    try root.makeFile("root.canvas")
    try root.makeFile("01 Progetti/vibrofer-emea/vibrofer-emea.canvas")
    try root.makeFile("02 Aree/area.canvas")
    let store = CanvasStore(root: root.url)

    #expect(store.allBoards() == [
        "01 Progetti/vibrofer-emea/vibrofer-emea.canvas",
        "02 Aree/area.canvas",
        "root.canvas",
    ])
}

@Test func allBoardsSkipsExcludedDirectories() throws {
    // Mirrors `VaultLayout.isExcludedDirectory`'s own dot-prefix rule (`.obsidian`, `.git`,
    // `.pergamenum` and any other dot-directory), the same rule `VaultScanner.scan()` applies
    // to notes.
    let root = try TemporaryRoot()
    try root.makeFile(".obsidian/hidden.canvas")
    try root.makeFile(".git/hidden.canvas")
    try root.makeFile(".pergamenum/hidden.canvas")
    try root.makeFile(".trash/hidden.canvas")
    try root.makeFile("01 Progetti/visibile.canvas")
    let store = CanvasStore(root: root.url)

    #expect(store.allBoards() == ["01 Progetti/visibile.canvas"])
}

@Test func allBoardsIgnoresEverythingThatIsNotACanvasFile() throws {
    let root = try TemporaryRoot()
    try root.makeFile("Nota.md")
    try root.makeFile("documento.pdf")
    try root.makeFile("immagine.png")
    try root.makeFile("01 Progetti/altra nota.md")
    let store = CanvasStore(root: root.url)

    #expect(store.allBoards().isEmpty)
}

@Test func allBoardsReturnsEmptyForAVaultWithNoBoards() throws {
    let root = try TemporaryRoot()
    try root.makeDirectory("01 Progetti")
    try root.makeFile("01 Progetti/nota.md")
    let store = CanvasStore(root: root.url)

    #expect(store.allBoards() == [])
}

// MARK: - Workspace controller

@MainActor
@Test func navigatesTheBoardHierarchyWithABreadcrumb() throws {
    // ADR-0025 §D3/§D4 (plan Task 3): a board is opened by its own path, not derived
    // from its folder. The existing vault's own convention - a board named after the
    // folder holding it - is kept here so the on-disk fixture matches R-13's "the
    // existing vault behaves exactly as it did before".
    let root = try TemporaryRoot()
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
    let root = try TemporaryRoot()
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

@MainActor
@Test func deletingANodeAlsoRemovesItsEdges() throws {
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))

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
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))

    let a = controller.addStickyNote("a", at: .zero)
    #expect(controller.connect(from: a, to: a) == nil)
    #expect(controller.connect(from: a, to: "inesistente") == nil)
    controller.detach()
}

@MainActor
@Test func keepsNodesGrabbableWhenResizedToNothing() throws {
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))

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
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))

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
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))

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
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))

    controller.zoomToFit(in: CGSize(width: 800, height: 600))
    #expect(controller.zoom == 1)
    #expect(controller.pan == .zero)
    controller.detach()
}

@MainActor
@Test func excludesTheFormsToolFromV1() {
    // SPEC §6.4 keeps the slot in the layout but not the feature.
    #expect(WorkspaceController.Tool.allCases.count == 11)
    #expect(WorkspaceController.Tool.forms.isAvailable == false)
    #expect(WorkspaceController.Tool.allCases.filter(\.isAvailable).count == 10)
    #expect(WorkspaceController.Tool.allCases.filter { $0.shortcut != nil }.count == 10)
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

// MARK: - Dragging

@MainActor
@Test func aDragMovesByTheTotalTranslationNotByEachStep() throws {
    // Found by dragging a card with a real mouse: the drag state lived in view
    // `@State`, which a gesture callback cannot reliably read back, so every event
    // restarted from the already-moved position and a 100-point drag threw the card
    // thousands of units away.
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))

    let id = controller.addStickyNote("a", at: CGPoint(x: 100, y: 100))
    controller.selection = [id]
    controller.beginDrag(nodeIDs: [id])

    // A gesture reports the translation from its own start, so these are cumulative
    // reports of one 60x30 drag, not three separate moves.
    controller.updateDrag(translation: CGSize(width: 20, height: 10))
    controller.updateDrag(translation: CGSize(width: 40, height: 20))
    controller.updateDrag(translation: CGSize(width: 60, height: 30))
    controller.endDrag()

    let node = try #require(controller.document.node(id: id))
    #expect(node.x == 160)
    #expect(node.y == 130)
    controller.detach()
}

@MainActor
@Test func aDragMovesEverySelectedCardTogether() throws {
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))

    let first = controller.addStickyNote("a", at: .zero)
    let second = controller.addStickyNote("b", at: CGPoint(x: 300, y: 0))
    let untouched = controller.addStickyNote("c", at: CGPoint(x: 600, y: 0))

    controller.selection = [first, second]
    controller.beginDrag(nodeIDs: controller.selection)
    controller.updateDrag(translation: CGSize(width: 50, height: 50))
    controller.endDrag()

    #expect(controller.document.node(id: first)?.x == 50)
    #expect(controller.document.node(id: second)?.x == 350)
    #expect(controller.document.node(id: untouched)?.x == 600)
    controller.detach()
}

@MainActor
@Test func updatingADragOutsideOneDoesNothing() throws {
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))
    let id = controller.addStickyNote("a", at: CGPoint(x: 10, y: 10))

    // A stray callback after the gesture ended must not move anything.
    controller.updateDrag(translation: CGSize(width: 999, height: 999))
    #expect(controller.document.node(id: id)?.x == 10)
    controller.detach()
}

@MainActor
@Test func beginningADragTwiceKeepsTheOriginalOrigins() throws {
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))
    let id = controller.addStickyNote("a", at: .zero)

    controller.beginDrag(nodeIDs: [id])
    controller.updateDrag(translation: CGSize(width: 100, height: 0))
    // A second begin mid-gesture must not re-anchor to the moved position.
    controller.beginDrag(nodeIDs: [id])
    controller.updateDrag(translation: CGSize(width: 100, height: 0))
    controller.endDrag()

    #expect(controller.document.node(id: id)?.x == 100)
    controller.detach()
}

// MARK: - The Freccia tool (SPEC §6.4, tool 11)

@MainActor
@Test func theArrowToolConnectsTheCardItIsReleasedOn() throws {
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))

    let a = controller.addStickyNote("a", at: .zero)
    let b = controller.addStickyNote("b", at: CGPoint(x: 400, y: 0))
    let source = try #require(controller.document.node(id: a))
    let target = try #require(controller.document.node(id: b))

    controller.tool = .arrow
    controller.beginArrow(from: a)
    controller.updateArrow(translation: CGSize(
        width: target.frame.midX - source.frame.midX,
        height: target.frame.midY - source.frame.midY
    ))
    #expect(controller.endArrow() != nil)
    #expect(controller.document.edges.count == 1)
    #expect(controller.document.edges.first?.fromNode == a)
    #expect(controller.document.edges.first?.toNode == b)
    // One-shot, like every other tool: back to Seleziona once the arrow is drawn.
    #expect(controller.tool == .select)
    controller.detach()
}

@MainActor
@Test func anArrowReleasedOverEmptyBoardDrawsNothing() throws {
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))

    let a = controller.addStickyNote("a", at: .zero)
    controller.tool = .arrow
    controller.beginArrow(from: a)
    controller.updateArrow(translation: CGSize(width: 4000, height: 4000))

    // JSON Canvas has no dangling edge, so an arrow to nowhere is not written.
    #expect(controller.endArrow() == nil)
    #expect(controller.document.edges.isEmpty)
    #expect(controller.arrowSourceID == nil)
    controller.detach()
}

@MainActor
@Test func anArrowInFlightTracksThePointerWithoutTouchingTheDocument() throws {
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))

    let a = controller.addStickyNote("a", at: CGPoint(x: 100, y: 100))
    let source = try #require(controller.document.node(id: a))
    controller.beginArrow(from: a)
    controller.updateArrow(translation: CGSize(width: 60, height: 30))

    #expect(controller.arrowEndPoint == CGPoint(x: source.frame.midX + 60, y: source.frame.midY + 30))
    // Nothing is committed until the gesture ends, the same rule the drag follows.
    #expect(controller.document.edges.isEmpty)
    controller.endArrow()
    controller.detach()
}

@MainActor
@Test func anArrowFromACardThatIsGoneNeverStarts() throws {
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))

    controller.beginArrow(from: "inesistente")
    #expect(controller.arrowSourceID == nil)
    #expect(controller.arrowEndPoint == nil)
    controller.detach()
}

// MARK: - ADR-0020, Task 3: crop mode transitions

@MainActor
@Test func confirmingACropWritesExactlyOneKeyAndOneHistoryStep() throws {
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))
    let id = controller.placeFile("foto.png", at: .zero)

    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    controller.updateCrop(handle: .bottomRight, translation: CGSize(width: -400, height: -200), lockAspect: false)
    controller.endCrop(confirm: true)

    let node = try #require(controller.document.node(id: id))
    #expect(CanvasCrop.read(from: node) != nil)
    #expect(controller.canUndo)
    // Exactly one history step for the crop: undoing once removes the crop and nothing
    // else - the node itself, placed by `placeFile` before the crop, is still there.
    controller.undo()
    let afterUndo = try #require(controller.document.node(id: id))
    #expect(CanvasCrop.read(from: afterUndo) == nil)
    #expect(afterUndo.id == id)
    controller.detach()
}

@MainActor
@Test func cancellingACropWritesNothingAndLeavesUnsavedChangesAlone() throws {
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))
    let id = controller.placeFile("foto.png", at: .zero)
    controller.flushPendingSave()
    #expect(!controller.hasUnsavedChanges)
    let undoDepthBefore = controller.canUndo

    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    controller.updateCrop(handle: .bottomRight, translation: CGSize(width: -400, height: -200), lockAspect: false)
    controller.endCrop(confirm: false)

    #expect(!controller.hasUnsavedChanges)
    #expect(controller.canUndo == undoDepthBefore)
    #expect(CanvasCrop.read(from: try #require(controller.document.node(id: id))) == nil)
    #expect(controller.croppingNodeID == nil)
    controller.detach()
}

@MainActor
@Test func croppingBackToTheWholeImageRemovesTheKeyRatherThanWritingAWholeRectangle() throws {
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))
    let id = controller.placeFile("foto.png", at: .zero)

    // First crop it, confirmed, then drag every grip back out to the full image.
    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    controller.updateCrop(handle: .bottomRight, translation: CGSize(width: -400, height: -200), lockAspect: false)
    controller.endCrop(confirm: true)
    #expect(CanvasCrop.read(from: try #require(controller.document.node(id: id))) != nil)

    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    controller.updateCrop(handle: .topLeft, translation: CGSize(width: -800, height: -400), lockAspect: false)
    controller.endCrop(confirm: true)

    let node = try #require(controller.document.node(id: id))
    #expect(CanvasCrop.read(from: node) == nil)
    #expect(node.unknown[CanvasCrop.key] == nil)
    controller.detach()
}

@MainActor
@Test func undoRestoresTheUncroppedNodeAndCancelsAnInFlightCrop() throws {
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))
    let id = controller.placeFile("foto.png", at: .zero)
    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    controller.updateCrop(handle: .bottomRight, translation: CGSize(width: -400, height: -200), lockAspect: false)
    controller.endCrop(confirm: true)
    #expect(CanvasCrop.read(from: try #require(controller.document.node(id: id))) != nil)

    // A second, still-open crop gesture on the same node when undo fires - undo must
    // cancel it rather than let its stale draft overwrite the just-restored document.
    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    #expect(controller.croppingNodeID == id)

    controller.undo()

    #expect(controller.croppingNodeID == nil)
    #expect(CanvasCrop.read(from: try #require(controller.document.node(id: id))) == nil)
    controller.detach()
}

@MainActor
@Test func navigatingAwayEndsAnOpenCropMode() throws {
    let root = try TemporaryRoot()
    try root.makeDirectory("Altra")
    let store = CanvasStore(root: root.url)
    let boardPath = try store.createBoard(named: "Altra", in: "Altra")
    let controller = WorkspaceController()
    controller.attach(to: store)
    let id = controller.placeFile("foto.png", at: .zero)

    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    #expect(controller.croppingNodeID == id)

    controller.open(board: boardPath)
    #expect(controller.croppingNodeID == nil)
    controller.detach()
}

@MainActor
@Test func removingACropOutsideTheModeClearsTheKeyInOneMutation() throws {
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))
    let id = controller.placeFile("foto.png", at: .zero)
    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    controller.updateCrop(handle: .bottomRight, translation: CGSize(width: -400, height: -200), lockAspect: false)
    controller.endCrop(confirm: true)
    #expect(CanvasCrop.read(from: try #require(controller.document.node(id: id))) != nil)

    controller.removeCrop(nodeIDs: [id])
    #expect(CanvasCrop.read(from: try #require(controller.document.node(id: id))) == nil)

    // A no-op removal on a node that carries no crop must not touch history.
    let historyDepthBefore = controller.canUndo
    controller.removeCrop(nodeIDs: [id])
    #expect(controller.canUndo == historyDepthBefore)
    controller.detach()
}

@MainActor
@Test func aNonCroppableFileNeverEntersCropMode() throws {
    let root = try TemporaryRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))
    let id = controller.placeFile("documento.pdf", at: .zero)

    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    #expect(controller.croppingNodeID == nil)
    controller.detach()
}
