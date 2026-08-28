import Foundation
import Testing
@testable import Pergamenum

// ADR-0027 §D4, plan 2026-08-28-unificare-nota-e-testo-in-un-solo-strume, Task 3 (R-06, R-07,
// R-10): `CardTextStyle` reads two prefixed keys off `CanvasNode.unknown` - never through an
// edit to `Sources/Core/Canvas/JSONCanvas.swift` itself (C5) - and never mutates what it reads.
// This is TDD's red step: `CardTextStyle.read(from:)` and `CardTextStyle.rgba(for:)` are both
// `fatalError` stubs until the coder fills them in, so every `@Test` below that calls either one
// is expected to crash the run, not merely fail an assertion, until that happens.
@Suite struct CardTextStyleTests {
    private func node(unknown: [String: JSONValue] = [:]) -> CanvasNode {
        CanvasNode(id: "a1", kind: .text("hello"), x: 0, y: 0, width: 220, height: 60, unknown: unknown)
    }

    // MARK: R-07 - a node with neither key is exactly today's plain-text card

    @Test func aNodeWithNeitherKeyReadsBothPropertiesAsNil() {
        let style = CardTextStyle.read(from: node())
        #expect(style.color == nil)
        #expect(style.alignment == nil)
    }

    // MARK: Colour decoding

    @Test func readsAPresetColorFromTheColorKey() {
        let style = CardTextStyle.read(from: node(unknown: [CardTextStyle.colorKey: .string("3")]))
        #expect(style.color == .preset(3))
    }

    @Test func readsAHexColorFromTheColorKey() {
        let style = CardTextStyle.read(from: node(unknown: [CardTextStyle.colorKey: .string("#A03060")]))
        #expect(style.color == .hex("#A03060"))
    }

    // MARK: Malformed / out-of-range input is rejected, not corrected (CanvasCrop.read's rule)

    @Test func anOutOfRangePresetReadsAsNilWithoutRemovingOrRewritingTheKey() {
        let original = node(unknown: [CardTextStyle.colorKey: .string("9")])
        let style = CardTextStyle.read(from: original)
        #expect(style.color == nil)
        // Non-destructive: the malformed value is neither corrected nor removed - a fresh
        // read of the same node still finds the original raw string.
        #expect(original.unknown[CardTextStyle.colorKey] == .string("9"))
    }

    @Test func aMalformedHexReadsAsNilWithoutRemovingOrRewritingTheKey() {
        let original = node(unknown: [CardTextStyle.colorKey: .string("#ZZZZZZ")])
        let style = CardTextStyle.read(from: original)
        #expect(style.color == nil)
        #expect(original.unknown[CardTextStyle.colorKey] == .string("#ZZZZZZ"))
    }

    // MARK: Alignment decoding

    @Test func decodesEachOfTheFourAlignmentStrings() {
        let cases: [(String, CardTextStyle.Alignment)] = [
            ("left", .left), ("center", .center), ("right", .right), ("justify", .justify),
        ]
        for (raw, expected) in cases {
            let style = CardTextStyle.read(from: node(unknown: [CardTextStyle.alignKey: .string(raw)]))
            #expect(style.alignment == expected, "\"\(raw)\" should decode to \(expected)")
        }
    }

    @Test func anUnknownAlignmentStringDecodesToNilWithoutRemovingOrRewritingTheKey() {
        let original = node(unknown: [CardTextStyle.alignKey: .string("diagonal")])
        let style = CardTextStyle.read(from: original)
        #expect(style.alignment == nil)
        #expect(original.unknown[CardTextStyle.alignKey] == .string("diagonal"))
    }

    // MARK: rgba(for:) - the fixed preset table and the verbatim hex parse (ADR-0027 §D4)

    @Test func rgbaForAHexColorParsesItVerbatim() {
        #expect(CardTextStyle.rgba(for: .hex("#A03060")) == RGBA(hex: "#A03060"))
    }

    @Test func rgbaForAMalformedHexColorIsNil() {
        #expect(CardTextStyle.rgba(for: .hex("not-a-color")) == nil)
    }

    @Test func rgbaForEachValidPresetIsAFixedFullyOpaqueColor() {
        for preset in 1...6 {
            let rgba = CardTextStyle.rgba(for: .preset(preset))
            #expect(rgba != nil, "preset \(preset) should map to a fixed sRGB value")
            #expect(rgba?.alpha == 1, "preset \(preset) should be fully opaque")
        }
    }

    @Test func rgbaForAnOutOfRangePresetIsNil() {
        #expect(CardTextStyle.rgba(for: .preset(0)) == nil)
        #expect(CardTextStyle.rgba(for: .preset(9)) == nil)
        #expect(CardTextStyle.rgba(for: .preset(-3)) == nil)
    }

    // MARK: Writing - the CanvasCrop / endCrop precedent: no default is ever written

    @Test func settingAlignmentAddsExactlyOneKeyAndLeavesOtherUnknownEntriesUntouched() {
        var card = node(unknown: [
            CanvasCrop.key: .string("0.1000 0.1000 0.5000 0.5000"),
            "someOtherApp.flag": .bool(true),
        ])
        card.unknown[CardTextStyle.alignKey] = .string(CardTextStyle.Alignment.center.rawValue)

        #expect(card.unknown.count == 3)
        #expect(card.unknown[CanvasCrop.key] == .string("0.1000 0.1000 0.5000 0.5000"))
        #expect(card.unknown["someOtherApp.flag"] == .bool(true))
        #expect(card.unknown[CardTextStyle.alignKey] == .string("center"))
        #expect(CardTextStyle.read(from: card).alignment == .center)
    }

    @Test func clearingAlignmentRemovesTheKeyRatherThanWritingADefault() {
        var card = node(unknown: [
            CardTextStyle.alignKey: .string("center"),
            CanvasCrop.key: .string("0.0000 0.0000 1.0000 1.0000"),
        ])
        card.unknown.removeValue(forKey: CardTextStyle.alignKey)

        #expect(card.unknown[CardTextStyle.alignKey] == nil)
        #expect(card.unknown.count == 1)
        #expect(card.unknown[CanvasCrop.key] == .string("0.0000 0.0000 1.0000 1.0000"))
        #expect(CardTextStyle.read(from: card).alignment == nil)
    }

    // MARK: R-06 / R-10 - round trip through the codec

    @Test func aStyledNodeSurvivesEncodeDecodeEncodeAlongsideForeignKeys() throws {
        let styled = CanvasNode(
            id: "a1", kind: .text("Nota"), x: 10, y: 20, width: 220, height: 60,
            unknown: [
                CardTextStyle.colorKey: .string("#A03060"),
                CardTextStyle.alignKey: .string("right"),
                "pergamenum-somethingElse": .string("keep-me"),
            ]
        )
        let original = CanvasDocument(nodes: [styled], edges: [], unknown: ["someOtherApp.metadata": .bool(true)])

        let firstPass = try original.encoded()
        let reDecoded = try CanvasDocument(data: firstPass)
        let secondPass = try reDecoded.encoded()
        #expect(firstPass == secondPass)

        let style = CardTextStyle.read(from: try #require(reDecoded.node(id: "a1")))
        #expect(style.color == .hex("#A03060"))
        #expect(style.alignment == .right)
    }

    /// A realistic Obsidian-authored `.canvas`, adapted from `Tests/CanvasTests.swift`'s own
    /// `obsidianCanvas` fixture: every node type this app draws, an edge, preset and hex
    /// colours - none of it touched by this feature (R-10: no corruption, no unexpected keys).
    private static let untouchedObsidianCanvas = """
    {
      "nodes": [
        {"id":"a1","type":"text","x":-260,"y":-120,"width":250,"height":60,"text":"Nota adesiva","color":"3"},
        {"id":"b2","type":"file","x":40,"y":-120,"width":400,"height":400,"file":"01 Progetti/Nota.md"},
        {"id":"e5","type":"group","x":-300,"y":-160,"width":800,"height":600,"label":"Zona","color":"#FF0000"}
      ],
      "edges": [
        {"id":"x1","fromNode":"a1","fromSide":"right","toNode":"b2","toSide":"left","label":"porta a","color":"2"}
      ]
    }
    """

    @Test func aNodeThisFeatureNeverTouchedIsByteIdenticalAfterARoundTrip() throws {
        let original = try CanvasDocument(data: Data(Self.untouchedObsidianCanvas.utf8))
        let firstPass = try original.encoded()
        let reDecoded = try CanvasDocument(data: firstPass)
        let secondPass = try reDecoded.encoded()
        #expect(firstPass == secondPass)

        // None of these nodes carry either prefixed key - `CardTextStyle` must not invent a
        // colour or an alignment where the file never set one.
        for node in reDecoded.nodes {
            let style = CardTextStyle.read(from: node)
            #expect(style.color == nil, "node \(node.id) should read no text colour")
            #expect(style.alignment == nil, "node \(node.id) should read no text alignment")
        }
    }
}
