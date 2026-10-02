import Foundation
import Testing
@testable import Pergamenum

// PG-280 (ADR-0065 §D13.7): a `.canvas` starting with a UTF-8 BOM. The BOM belongs to the file:
// the decode skips it, the hash skips it, and a save keeps it.

private let bom = Data([0xEF, 0xBB, 0xBF])
private let oneNode = Data("""
{"nodes":[{"id":"a1","type":"text","x":0,"y":0,"width":100,"height":50,"text":"A"}],"edges":[]}
""".utf8)

private func temporaryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("canvas-bom-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func aCanvasWithABOMDecodesLikeOneWithout() throws {
    let document = try CanvasDocument(data: bom + oneNode)
    #expect(document.nodes.map(\.id) == ["a1"])
    #expect(document == (try CanvasDocument(data: oneNode)))
}

@Test func aBOMOnlyFileIsAnEmptyCanvas() throws {
    #expect(try CanvasDocument(data: bom) == .empty)
}

@Test func theHashSkipsTheBOM() {
    #expect(NoteStore.hash(bom + oneNode) == NoteStore.hash(oneNode))
}

@Test func aSaveKeepsTheFilesBOM() throws {
    let root = try temporaryRoot()
    let store = CanvasStore(root: root)
    try (bom + oneNode).write(to: root.appendingPathComponent("Board.canvas"))
    let (document, hash) = try store.read(board: "Board.canvas")
    try store.save(document, board: "Board.canvas", expecting: hash)
    let saved = try Data(contentsOf: root.appendingPathComponent("Board.canvas"))
    #expect(saved.starts(with: bom))
    #expect(try CanvasDocument(data: saved) == document)
}

@Test func aSaveNeverAddsABOM() throws {
    let root = try temporaryRoot()
    let store = CanvasStore(root: root)
    try oneNode.write(to: root.appendingPathComponent("Board.canvas"))
    try store.save(try store.load(board: "Board.canvas"), board: "Board.canvas")
    let saved = try Data(contentsOf: root.appendingPathComponent("Board.canvas"))
    #expect(!saved.starts(with: bom))
    try store.save(.empty, board: "New.canvas")
    #expect(!(try Data(contentsOf: root.appendingPathComponent("New.canvas"))).starts(with: bom))
}
