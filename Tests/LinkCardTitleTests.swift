import Foundation
import Testing
@testable import Pergamenum

// PG-073 (SPEC §6.4 row 7 / §6.5): `LinkCardTitle` reads one prefixed key off
// `CanvasNode.unknown` - `CanvasCrop`/`CardTextStyle`'s pattern, applied to a `.link` card's
// title. A malformed or absent stored value reads as `nil`, never corrected, never removed.
@Suite struct LinkCardTitleTests {
    private func node(unknown: [String: JSONValue] = [:]) -> CanvasNode {
        CanvasNode(id: "l1", kind: .link(url: "https://example.com"), x: 0, y: 0, width: 220, height: 60, unknown: unknown)
    }

    // MARK: R-01 - read

    @Test func aNodeWithNoTitleKeyReadsAsNil() {
        #expect(LinkCardTitle.read(from: node()) == nil)
    }

    @Test func readsANonEmptyStoredTitle() {
        #expect(LinkCardTitle.read(from: node(unknown: [LinkCardTitle.key: .string("Documentazione")])) == "Documentazione")
    }

    @Test func anEmptyStoredTitleReadsAsNil() {
        #expect(LinkCardTitle.read(from: node(unknown: [LinkCardTitle.key: .string("")])) == nil)
    }

    @Test func aNonStringStoredValueReadsAsNil() {
        #expect(LinkCardTitle.read(from: node(unknown: [LinkCardTitle.key: .bool(true)])) == nil)
    }

    // MARK: R-02 - round trip

    @Test func aTitledLinkNodeSurvivesEncodeDecodeEncodeAlongsideForeignKeys() throws {
        let titled = CanvasNode(
            id: "l1", kind: .link(url: "https://example.com"), x: 10, y: 20, width: 220, height: 60,
            unknown: [
                LinkCardTitle.key: .string("Documentazione"),
                "pergamenum-somethingElse": .string("keep-me"),
            ]
        )
        let original = CanvasDocument(nodes: [titled], edges: [], unknown: [:])

        let firstPass = try original.encoded()
        let reDecoded = try CanvasDocument(data: firstPass)
        let secondPass = try reDecoded.encoded()
        #expect(firstPass == secondPass)
        #expect(LinkCardTitle.read(from: try #require(reDecoded.node(id: "l1"))) == "Documentazione")
    }

    // A `.link` node with no `pergamenum-title` key - every existing Link card on disk before
    // this feature shipped - must round-trip byte-identical, with no key ever invented.
    @Test func aLinkNodeWithNoStoredTitleIsByteIdenticalAfterARoundTrip() throws {
        let untitled = CanvasNode(
            id: "l1", kind: .link(url: "https://example.com"), x: 10, y: 20, width: 220, height: 60, unknown: [:]
        )
        let original = CanvasDocument(nodes: [untitled], edges: [], unknown: [:])

        let firstPass = try original.encoded()
        let reDecoded = try CanvasDocument(data: firstPass)
        let secondPass = try reDecoded.encoded()
        #expect(firstPass == secondPass)
        #expect(LinkCardTitle.read(from: try #require(reDecoded.node(id: "l1"))) == nil)
    }
}
