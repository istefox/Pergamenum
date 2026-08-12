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

// MARK: - Board / folder mapping

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

@Test func mapsAFolderToTheBoardFileInsideIt() throws {
    let root = try TemporaryRoot()
    let store = CanvasStore(root: root.url)
    // SPEC §6.1: the board lives inside the folder it describes, named after it.
    #expect(store.boardPath(forFolder: "01 Progetti/vibrofer-emea") == "01 Progetti/vibrofer-emea/vibrofer-emea.canvas")
    // The root board is named after the vault so it cannot collide with a note.
    #expect(store.boardPath(forFolder: "") == "\(root.url.lastPathComponent).canvas")
    #expect(store.boardPath(forFolder: "/01 Progetti/") == "01 Progetti/01 Progetti.canvas")
}

@Test func readingAFolderWithNoBoardDoesNotCreateOne() throws {
    let root = try TemporaryRoot()
    try root.makeDirectory("01 Progetti")
    let store = CanvasStore(root: root.url)

    let board = try store.load(folder: "01 Progetti")
    #expect(board.nodes.isEmpty)
    // Merely looking into a folder must not litter the vault with canvas files.
    #expect(!FileManager.default.fileExists(
        atPath: store.url(forFolder: "01 Progetti").path(percentEncoded: false)
    ))
}

@Test func savesAndReloadsABoard() throws {
    let root = try TemporaryRoot()
    let store = CanvasStore(root: root.url)
    var board = CanvasDocument()
    board.nodes.append(CanvasNode(id: "a", kind: .text("ciao"), x: 10, y: 20, width: 200, height: 100))

    try store.save(board, folder: "01 Progetti")
    let reloaded = try store.load(folder: "01 Progetti")
    #expect(reloaded == board)
}

@Test func listsFolderContentsSplitByWhetherTheBoardShowsThem() throws {
    let root = try TemporaryRoot()
    try root.makeDirectory("01 Progetti/sotto")
    try root.makeFile("01 Progetti/piazzato.md")
    try root.makeFile("01 Progetti/nuovo.pdf")
    try root.makeFile("01 Progetti/.nascosto")

    let store = CanvasStore(root: root.url)
    var board = CanvasDocument()
    board.nodes.append(CanvasNode(
        id: "a", kind: .file(path: "01 Progetti/piazzato.md", subpath: nil),
        x: 0, y: 0, width: 10, height: 10
    ))

    let contents = store.contents(ofFolder: "01 Progetti", board: board)
    #expect(contents.subfolders == ["01 Progetti/sotto"])
    // Already on the board, so not in the tray; the hidden file is never listed.
    #expect(contents.unplaced == ["01 Progetti/nuovo.pdf", "01 Progetti/sotto"])
}

@Test func doesNotListTheBoardsOwnFileAsAnItem() throws {
    let root = try TemporaryRoot()
    try root.makeDirectory("Area")
    let store = CanvasStore(root: root.url)
    try store.save(CanvasDocument(), folder: "Area")

    let board = try store.load(folder: "Area")
    let contents = store.contents(ofFolder: "Area", board: board)
    #expect(contents.unplaced.isEmpty)
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

@Test func generatesIdsInTheShapeObsidianWrites() {
    let id = CanvasID.generate()
    #expect(id.count == 16)
    // Hoisted: `allSatisfy` is rethrows, and inside #expect's autoclosure the
    // compiler stops inferring that a key-path predicate cannot throw.
    let isHexadecimal = id.allSatisfy(\.isHexDigit)
    #expect(isHexadecimal)
    #expect(CanvasID.generate() != id)
}

// MARK: - Workspace controller

@MainActor
@Test func navigatesTheBoardHierarchyWithABreadcrumb() throws {
    let root = try TemporaryRoot()
    try root.makeDirectory("01 Progetti/vibrofer-emea")
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))

    #expect(controller.breadcrumb.map(\.title) == ["Workspace"])

    controller.open(folder: "01 Progetti/vibrofer-emea")
    #expect(controller.breadcrumb.map(\.title) == ["Workspace", "01 Progetti", "vibrofer-emea"])
    #expect(controller.breadcrumb.map(\.folder) == ["", "01 Progetti", "01 Progetti/vibrofer-emea"])
    controller.detach()
}

@MainActor
@Test func writesTheBoardWhenLeavingItEvenBeforeTheAutosaveDelay() throws {
    let root = try TemporaryRoot()
    try root.makeDirectory("A")
    try root.makeDirectory("B")
    let store = CanvasStore(root: root.url)
    let controller = WorkspaceController()
    controller.attach(to: store)

    controller.open(folder: "A")
    _ = controller.addStickyNote("appunto", at: CGPoint(x: 10, y: 10))
    #expect(controller.hasUnsavedChanges)

    // Navigating away must not lose the edit while the debounce is still pending.
    controller.open(folder: "B")
    let saved = try store.load(folder: "A")
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
