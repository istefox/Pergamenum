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

// MARK: - Folder creation
//
// The five tests that pinned the folder→board mapping (`boardPath(forFolder:)`,
// `load(folder:)`, `save(_:folder:)`, `contents(ofFolder:board:)`) are gone with the API
// they exercised - ADR-0025 §D1 deletes it rather than deprecating it. Their subject is
// re-asserted against the path-addressing shape below. The fixture every store test builds
// on, `CanvasTemporaryRoot`, lives in `CanvasTestSupport.swift`.

@Test func createsARealDirectoryForAFolderCard() throws {
    let root = try CanvasTemporaryRoot()
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
    let root = try CanvasTemporaryRoot()
    let store = CanvasStore(root: root.url)

    var failed = false
    do {
        _ = try store.createFolder(named: "Nuova", in: "cartella inesistente")
    } catch {
        failed = true
    }
    #expect(failed)
}
