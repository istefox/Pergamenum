import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// ADR-0065 §D5.4 and §D13.4, plan docs/plans/pg-277-canvas-wrong-type-required-keys.md,
// Tasks 1-2 - R-01 to R-09 (PG-277, #616).
//
// A JSON Canvas required key present with a wrong JSON type (`"x": "12"`, `"text": 42`) used to
// be replaced by its default and the default written back over the file's value. The element is
// now kept opaque at its index, like every other element the codec cannot read (§D5.4). An absent
// required key still takes its default, and a wrong-typed optional key still leaves its element
// readable (§D5.3).

private func decoded(_ json: String) throws -> CanvasDocument {
    try CanvasDocument(data: Data(json.utf8))
}

private func expectRoundTrip(_ json: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
    #expect(
        try decoded(json).encoded() == (try FormatEdgeCorpus.canonicalCanvas(json)),
        sourceLocation: sourceLocation
    )
}

/// The element of `key` whose `id` is `id` in an encoded canvas, as a `JSONValue`.
private func element(_ id: String, in key: String, of data: Data) throws -> JSONValue? {
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let list = root?[key] as? [Any] ?? []
    let match = list.compactMap { $0 as? [String: Any] }.first { $0["id"] as? String == id }
    return match.flatMap { JSONValue($0) }
}

/// One JSON object literal as a `JSONValue`, for comparing an element with its fixture.
private func value(_ json: String) throws -> JSONValue? {
    JSONValue(try JSONSerialization.jsonObject(with: Data(json.utf8)))
}

private let nodeA = FormatEdgeCorpus.nodeA
private let nodeB = FormatEdgeCorpus.nodeB

/// A node with id `m` whose one required key is present with a wrong JSON type.
struct MalformedNode: Sendable, CustomStringConvertible {
    let name: String
    let json: String
    var description: String { name }
}

private let geometry = #""x":0,"y":0,"width":100,"height":50"#
private let textM = #""id":"m","type":"text","text":"M""#
/// The case most tests reach for: a text node whose `x` is a string.
private let malformedX = #"{\#(textM),"x":"12","y":0,"width":100,"height":50}"#

private let malformedNodes: [MalformedNode] = [
    MalformedNode(name: "xString", json: malformedX),
    MalformedNode(name: "yArray", json: #"{\#(textM),"x":0,"y":[],"width":100,"height":50}"#),
    MalformedNode(name: "widthBool", json: #"{\#(textM),"x":0,"y":0,"width":true,"height":50}"#),
    MalformedNode(name: "heightNull", json: #"{\#(textM),"x":0,"y":0,"width":100,"height":null}"#),
    MalformedNode(name: "unknownKindXObject", json: #"{"id":"m","type":"embed","x":{},"y":0,"width":100,"height":50}"#),
    MalformedNode(name: "textNumber", json: #"{"id":"m","type":"text","text":42,\#(geometry)}"#),
    MalformedNode(name: "textNull", json: #"{"id":"m","type":"text","text":null,\#(geometry)}"#),
    MalformedNode(name: "fileNumber", json: #"{"id":"m","type":"file","file":7,\#(geometry)}"#),
    MalformedNode(name: "urlArray", json: #"{"id":"m","type":"link","url":[],\#(geometry)}"#),
]

// MARK: - Codec (Task 1)

// R-01: the malformed node is opaque at its own index, its neighbours still decode, and the whole
// board re-encodes to its canonical form.
@Test(arguments: malformedNodes)
func aWrongTypedRequiredKeyKeepsTheNodeOpaque(_ malformed: MalformedNode) throws {
    let json = #"{"nodes":[\#(nodeA),\#(malformed.json),\#(nodeB)],"edges":[]}"#
    let document = try decoded(json)

    #expect(document.nodes.map(\.id) == ["a", "b"])
    #expect(document.opaqueNodes.map(\.index) == [1])
    try expectRoundTrip(json)
}

// R-01: an edit elsewhere on the board rewrites the readable nodes and carries the malformed one.
@Test func aMalformedNodeSurvivesAnEditElsewhere() throws {
    let malformed = malformedX
    var document = try decoded(#"{"nodes":[\#(nodeA),\#(malformed),\#(nodeB)],"edges":[]}"#)

    document.nodes.removeAll { $0.id == "b" }
    document.nodes.append(CanvasNode(id: "c", kind: .text("C"), x: 400, y: 0, width: 100, height: 50))
    let data = try document.encoded()

    #expect(try element("m", in: "nodes", of: data) == (try value(malformed)))
    #expect(try element("b", in: "nodes", of: data) == nil)
    #expect(try element("c", in: "nodes", of: data) != nil)
}

// R-03: a wrong-typed identity key was already opaque before PG-277, on nodes and on edges.
@Test func aWrongTypedIdentityKeyWasAlreadyOpaque() throws {
    let nodes = [
        nodeA,
        #"{"id":7,"type":"text","text":"N",\#(geometry)}"#,
        #"{"id":"t","type":1,"text":"T",\#(geometry)}"#,
        nodeB,
    ]
    let edges = [
        #"{"id":"e1","fromNode":3,"toNode":"b"}"#,
        #"{"id":"e2","fromNode":"a","toNode":null}"#,
        #"{"id":5,"fromNode":"a","toNode":"b"}"#,
        #"{"id":"e4","fromNode":"a","toNode":"b"}"#,
    ]
    let json = #"{"nodes":[\#(nodes.joined(separator: ","))],"edges":[\#(edges.joined(separator: ","))]}"#
    let document = try decoded(json)

    #expect(document.nodes.map(\.id) == ["a", "b"])
    #expect(document.opaqueNodes.map(\.index) == [1, 2])
    #expect(document.edges.map(\.id) == ["e4"])
    #expect(document.opaqueEdges.map(\.index) == [0, 1, 2])
    try expectRoundTrip(json)
}

// R-05: geometry accepts any JSON number, fractional, negative, exponent form and zero.
@Test func everyJSONNumberFormIsReadableGeometry() throws {
    let json = #"{"nodes":[{"id":"n","type":"text","text":"N","x":12.5,"y":-3,"width":1e2,"height":0}],"edges":[]}"#
    let document = try decoded(json)

    #expect(document.nodes.first?.frame == CGRect(x: 12.5, y: -3, width: 100, height: 0))
    #expect(document.opaqueNodes.isEmpty)
    try expectRoundTrip(json)
}

// R-01: `NSNumber` carries a JSON boolean too, and a boolean is not a number. The file's `true`
// is written back as `true`, not as `1`.
@Test func aBooleanIsNotANumber() throws {
    let malformed = #"{"id":"m","type":"text","text":"M","x":0,"y":0,"width":true,"height":50}"#
    let document = try decoded(#"{"nodes":[\#(nodeA),\#(malformed)],"edges":[]}"#)

    #expect(document.opaqueNodes.map(\.index) == [1])
    let root = try JSONSerialization.jsonObject(with: try document.encoded()) as? [String: Any]
    let written = (root?["nodes"] as? [[String: Any]])?.first { $0["id"] as? String == "m" }
    let width = written?["width"] as? NSNumber
    #expect(width.map { CFGetTypeID($0) == CFBooleanGetTypeID() } == true)
    #expect(width?.boolValue == true)
}

// R-06: an absent required key keeps its default. Not a round-trip: the encode adds the key with
// the value the card was drawn with, which is a repair rather than a loss.
@Test func anAbsentRequiredKeyKeepsItsDefault() throws {
    let json = #"{"nodes":[{"id":"n","type":"text"},{"id":"f","type":"file"},{"id":"l","type":"link"}],"edges":[]}"#
    let document = try decoded(json)

    #expect(document.opaqueNodes.isEmpty)
    #expect(document.nodes.map(\.frame) == Array(repeating: CGRect(x: 0, y: 0, width: 260, height: 120), count: 3))
    #expect(document.node(id: "n")?.kind == .text(""))
    #expect(document.node(id: "f")?.kind == .file(path: "", subpath: nil))
    #expect(document.node(id: "l")?.kind == .link(url: ""))
}

// R-08: a wrong-typed optional key never makes its element opaque (ADR-0065 §D5.3), and another
// kind's payload key stays foreign whatever its type (§D5.1).
@Test func aWrongTypedOptionalKeyStaysReadable() throws {
    let nodes = [
        #"{"id":"f","type":"file","file":"Nota.md","subpath":3,\#(geometry)}"#,
        #"{"id":"i","type":"file","file":"foto.png","pergamenum-crop":5,\#(geometry)}"#,
        #"{"id":"t","type":"text","text":"T","file":7,\#(geometry)}"#,
    ]
    let json = #"{"nodes":[\#(nodes.joined(separator: ","))],"edges":[]}"#
    let document = try decoded(json)

    #expect(document.opaqueNodes.isEmpty)
    #expect(document.node(id: "f")?.kind == .file(path: "Nota.md", subpath: nil))
    #expect(document.node(id: "f")?.unknown["subpath"] == .number(3))
    #expect(document.node(id: "i")?.unknown["pergamenum-crop"] == .number(5))
    #expect(document.node(id: "t")?.kind == .text("T"))
    #expect(document.node(id: "t")?.unknown["file"] == .number(7))
    try expectRoundTrip(json)
}

// R-07: an edge naming an opaque node stays a readable edge and is written back unchanged, and
// so is the opaque node, after an edit elsewhere.
@Test func anEdgeToAnOpaqueNodeIsKeptAndWrittenBack() throws {
    let malformed = malformedX
    let edge = #"{"id":"e","fromNode":"a","toNode":"m"}"#
    var document = try decoded(#"{"nodes":[\#(nodeA),\#(malformed)],"edges":[\#(edge)]}"#)

    #expect(document.edges.map(\.id) == ["e"])
    document.nodes[0].x += 10
    let data = try document.encoded()

    #expect(try element("e", in: "edges", of: data) == (try value(edge)))
    #expect(try element("m", in: "nodes", of: data) == (try value(malformed)))
}

// R-09: a node `base` reads and `theirs` has made malformed diverges, naming both the node's id
// and the opaque index, and `mine` is never adopted over the external value.
@Test func aNodeMadeMalformedByTheirsDiverges() throws {
    let readable = #"{"id":"m","type":"text","text":"M","x":40,"y":0,"width":100,"height":50}"#
    let malformed = malformedX
    let base = try decoded(#"{"nodes":[\#(nodeA),\#(readable)],"edges":[]}"#)
    let theirs = try decoded(#"{"nodes":[\#(nodeA),\#(malformed)],"edges":[]}"#)
    var mine = base
    mine.nodes.append(CanvasNode(id: "c", kind: .text("C"), x: 400, y: 0, width: 100, height: 50))

    guard case .diverged(let reasons) = CanvasDocument.reconcile(mine: mine, base: base, theirs: theirs) else {
        Issue.record("expected .diverged")
        return
    }
    #expect(reasons.contains("m"))
    #expect(reasons.contains("nodes[1]"))
}

// MARK: - The two write paths (Task 2)

private let boardWithMalformedNode = #"{"nodes":[\#(nodeA),\#(malformedX)],"# +
    #""edges":[{"id":"e","fromNode":"a","toNode":"m"}]}"#

// R-02, R-07: the Workspace's own autosave of another node's move writes the malformed node and
// its edge back unchanged.
@MainActor
@Test func aWorkspaceSaveOfAnotherEditKeepsTheMalformedNode() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeFile("Board.canvas", boardWithMalformedNode)
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root.url))
    controller.open(board: "Board.canvas")

    controller.move(nodeIDs: ["a"], by: CGSize(width: 10, height: 0))
    controller.flushPendingSave()

    let data = try Data(contentsOf: root.url.appending(path: "Board.canvas"))
    guard case .object(let nodeAOnDisk)? = try element("a", in: "nodes", of: data) else {
        Issue.record("node a is missing on disk")
        controller.detach()
        return
    }
    #expect(nodeAOnDisk["x"] == .number(10))
    let malformed = malformedX
    #expect(try element("m", in: "nodes", of: data) == (try value(malformed)))
    #expect(try element("e", in: "edges", of: data) == (try value(#"{"id":"e","fromNode":"a","toNode":"m"}"#)))

    #expect(controller.document.opaqueNodes.count == 1)
    #expect(controller.saveState == .saved)
    controller.detach()
}

// R-02: a board the person never opened, repointed by a note rename, keeps its malformed node.
@MainActor
@Test func aNoteRenameRepointsABoardWithoutRewritingItsMalformedNode() async throws {
    let vault = try TemporaryVault()
    try vault.write("---\ndate: 2026-09-28\ntags:\n  - type-note\n---\n\nCorpo.\n", to: "Vecchio titolo.md")
    let malformed = #"{"id":"m","type":"text","text":42,"x":300,"y":0,"width":100,"height":50}"#
    let fileNode = #"{"id":"a","type":"file","file":"Vecchio titolo.md","x":0,"y":0,"width":260,"height":180}"#
    let board = #"{"nodes":[\#(fileNode),\#(malformed)],"edges":[]}"#
    try vault.write(board, to: "Labs.canvas")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()

    _ = try await session.renameNote(at: "Vecchio titolo.md", to: "Nuovo titolo")

    let data = try Data(contentsOf: vault.root.appending(path: "Labs.canvas"))
    guard case .object(let repointed)? = try element("a", in: "nodes", of: data) else {
        Issue.record("the file node is missing on disk")
        return
    }
    #expect(repointed["file"] == .string("Nuovo titolo.md"))
    #expect(try element("m", in: "nodes", of: data) == (try value(malformed)))
}
