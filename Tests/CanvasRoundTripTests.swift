import Foundation
import Testing
@testable import Pergamenum

// ADR-0065 §D5-§D6, plan docs/plans/format-edge-hardening.md, Task 3 - R-06, R-07, R-08, R-23.
//
// JSON Canvas carries what it cannot read. "Round-trips" for `.canvas` means identical to the
// codec's canonical encoding of the same JSON value (ADR-0065 §Context): a fixture is
// canonicalised once, with the codec's options, and compared to `encoded()`.

private func decoded(_ json: String) throws -> CanvasDocument {
    try CanvasDocument(data: Data(json.utf8))
}

private func expectRoundTrip(_ json: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
    #expect(
        try decoded(json).encoded() == (try FormatEdgeCorpus.canonicalCanvas(json)),
        sourceLocation: sourceLocation
    )
}

private func encodedArray(_ key: String, of document: CanvasDocument) throws -> [Any] {
    let object = try JSONSerialization.jsonObject(with: try document.encoded()) as? [String: Any]
    return object?[key] as? [Any] ?? []
}

private func node(_ id: String, _ text: String) -> CanvasNode {
    CanvasNode(id: id, kind: .text(text), x: 0, y: 0, width: 100, height: 50)
}

// MARK: - R-06

@Test func anUnknownTypeNodeKeepsEveryPayloadKey() throws {
    let json = #"{"nodes":[{"id":"e","type":"embed","url":"https://x","label":"L","text":"T","x":0,"y":0,"width":100,"height":50}],"edges":[]}"#
    #expect(try decoded(json).nodes.first?.kind == .unknown(type: "embed"))
    try expectRoundTrip(json)
}

@Test func aKnownKindKeepsAnotherKindsKey() throws {
    let json = #"{"nodes":[{"id":"t","type":"text","text":"T","url":"https://x","x":0,"y":0,"width":100,"height":50}],"edges":[]}"#
    #expect(try decoded(json).nodes.first?.unknown["url"] == .string("https://x"))
    try expectRoundTrip(json)
}

// MARK: - R-07

@Test(arguments: ["7", "#GGG", "red"])
func anUnrecognisedNodeColourRoundTrips(_ colour: String) throws {
    let json = #"{"nodes":[{"id":"n","type":"text","text":"N","color":"\#(colour)","x":0,"y":0,"width":100,"height":50}],"edges":[]}"#
    let node = try #require(try decoded(json).nodes.first)
    #expect(node.color == .unrecognised(colour))
    #expect(node.isNote)
    try expectRoundTrip(json)
}

@Test(arguments: ["7", "#GGG", "red"])
func anUnrecognisedEdgeColourRoundTrips(_ colour: String) throws {
    let json = #"{"nodes":[],"edges":[{"id":"e","fromNode":"a","toNode":"b","color":"\#(colour)"}]}"#
    #expect(try decoded(json).edges.first?.color == .unrecognised(colour))
    try expectRoundTrip(json)
}

@Test func anUnderstoodColourStillParses() throws {
    #expect(CanvasColor("3") == .preset(3))
    #expect(CanvasColor("#FF0000") == .hex("#FF0000"))
    let json = #"{"nodes":[{"id":"n","type":"text","text":"N","color":"3","x":0,"y":0,"width":100,"height":50}],"edges":[]}"#
    #expect(try decoded(json).nodes.first?.color == .preset(3))
}

@Test func aNonStringColourOrLabelIsKept() throws {
    let json = #"{"nodes":[{"id":"n","type":"text","text":"N","color":3,"x":0,"y":0,"width":100,"height":50}],"# +
        #""edges":[{"id":"e","fromNode":"n","toNode":"n","label":7}]}"#
    let document = try decoded(json)
    #expect(document.nodes.first?.color == nil)
    #expect(document.nodes.first?.unknown["color"] == .number(3))
    #expect(document.edges.first?.unknown["label"] == .number(7))
    try expectRoundTrip(json)
}

@Test func anUnrecognisedEdgeSideOrEndIsKept() throws {
    let json = #"{"nodes":[],"edges":[{"id":"e","fromNode":"a","toNode":"b","fromSide":"centre","toEnd":"diamond"}]}"#
    try expectRoundTrip(json)
}

// MARK: - R-08

@Test func aNodeWithoutIdOrTypeIsWrittenBackInPlace() throws {
    let json = #"{"nodes":[\#(FormatEdgeCorpus.nodeA),{"type":"text","text":"x"},{"id":"z"},\#(FormatEdgeCorpus.nodeB)],"edges":[]}"#
    let document = try decoded(json)
    #expect(document.nodes.map(\.id) == ["a", "b"])
    #expect(document.opaqueNodes.map(\.index) == [1, 2])
    try expectRoundTrip(json)
}

@Test func anEdgeWithoutEndpointsIsWrittenBackInPlace() throws {
    let json = #"{"nodes":[],"edges":[{"id":"e0"},\#(FormatEdgeCorpus.edgeAB),{"fromNode":"a","toNode":"b"}]}"#
    let document = try decoded(json)
    #expect(document.edges.map(\.id) == ["e1"])
    #expect(document.opaqueEdges.map(\.index) == [0, 2])
    try expectRoundTrip(json)
}

@Test func aNonObjectElementDoesNotEmptyTheBoard() throws {
    let json = #"{"nodes":[\#(FormatEdgeCorpus.nodeA),42,\#(FormatEdgeCorpus.nodeB)],"edges":[]}"#
    let document = try decoded(json)
    #expect(document.nodes.map(\.id) == ["a", "b"])
    let encoded = try encodedArray("nodes", of: document)
    #expect(encoded.count == 3)
    #expect((encoded[1] as? NSNumber)?.intValue == 42)
    try expectRoundTrip(json)
}

@Test func opaqueElementsSurviveAnEdit() throws {
    let json = #"{"nodes":[\#(FormatEdgeCorpus.nodeA),42,{"id":"z"},\#(FormatEdgeCorpus.nodeB)],"edges":[]}"#
    var document = try decoded(json)
    document.nodes.removeAll { $0.id == "a" }
    document.nodes.append(node("c", "C"))

    let encoded = try encodedArray("nodes", of: document)
    let opaqueNumber = encoded.firstIndex { ($0 as? NSNumber)?.intValue == 42 }
    let opaqueObject = encoded.firstIndex { ($0 as? [String: Any]).map { $0.count == 1 && $0["id"] as? String == "z" } ?? false }
    let ids = encoded.compactMap { ($0 as? [String: Any])?["type"] != nil ? ($0 as? [String: Any])?["id"] as? String : nil }
    #expect(encoded.count == 4)
    #expect(ids == ["b", "c"])
    let number = try #require(opaqueNumber)
    let object = try #require(opaqueObject)
    #expect(number < object)
}

// MARK: - R-23, G1.6: a non-array `nodes`/`edges` refuses the open

@Test func aNodesValueThatIsNotAListIsRefused() throws {
    #expect {
        try decoded(#"{"nodes":{}}"#)
    } throws: { error in
        guard case CanvasDocument.DecodingError.notAList(let key) = error else { return false }
        return key == "nodes"
    }
    #expect {
        try decoded(#"{"edges":"x"}"#)
    } throws: { error in
        guard case CanvasDocument.DecodingError.notAList(let key) = error else { return false }
        return key == "edges"
    }
    #expect(try decoded("{}") == .empty)
}

@MainActor
@Test func aBoardWhoseNodesAreNotAListRecordsAProblem() async throws {
    let vault = try TemporaryVault()
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)
    try vault.write(#"{"nodes":{}}"#, to: "Rotta.canvas")
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: vault.root), vault: vaultController)
    let problemsBefore = vaultController.problems.count

    controller.open(board: "Rotta.canvas")

    #expect(vaultController.problems.count == problemsBefore + 1)
    #expect(vaultController.problems.last?.contains("Rotta.canvas") == true)
    #expect(vaultController.problems.last?.contains("nodes") == true)
    controller.detach()
    vaultController.close()
}

// MARK: - Duplicate ids open normally (SPEC decision), pins

@Test func aDuplicateIdBoardOpensAndReencodes() throws {
    let json = #"{"nodes":[\#(FormatEdgeCorpus.nodeA),{"id":"a","type":"text","text":"A2","x":10,"y":10,"width":100,"height":50}],"edges":[]}"#
    #expect(try decoded(json).nodes.map(\.id) == ["a", "a"])
    #expect(try encodedArray("nodes", of: try decoded(json)).count == 2)
    try expectRoundTrip(json)
}

// MARK: - ADR §D6: reconciliation and opaque elements

@Test func anOpaqueChangeByTheirsDiverges() {
    let base = CanvasDocument(nodes: [node("a", "A")], opaqueNodes: [CanvasOpaqueElement(index: 1, value: .number(42))])
    let theirs = CanvasDocument(nodes: [node("a", "A")], opaqueNodes: [CanvasOpaqueElement(index: 1, value: .number(43))])

    #expect(CanvasDocument.reconcile(mine: base, base: base, theirs: theirs) == .diverged(["nodes[1]"]))
}

@Test func aReencodingOnlyRefusalStillAdopts() {
    let duplicated = CanvasDocument(nodes: [node("a", "A"), node("a", "A2")])
    let mine = CanvasDocument(nodes: [node("a", "A"), node("a", "A2"), node("c", "C")])

    #expect(CanvasDocument.reconcile(mine: mine, base: duplicated, theirs: duplicated) == .adopted(mine))
}
