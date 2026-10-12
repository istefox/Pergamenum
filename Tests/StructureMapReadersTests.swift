import Foundation
import Testing
@testable import Pergamenum

// ADR-0094 §D6, plan docs/plans/sublinear-offset-state-pg-405.md, Task 7 ((coverage), PG-405, R-07).
//
// `fenceParity(before:)`, `nearestBracketLine(before:)` and `hasClosingBracket(after:)` answer by search in
// the map's three mark sets what `RestyleScope.renumberWindow` and `pendingOpener` used to answer by
// walking the lines. The oracle here is that walk, written out over the map's own `lines`, so the marks
// are checked against the lines they are meant to summarise, on a map built from text and on one kept
// current through random edits (`apply`), and on one that took a `splice`.

private enum Walk {
    /// The old `renumberWindow` sum: the delimiters above line `index`, modulo 2.
    static func fenceParity(_ map: StructureMap, before index: Int) -> Bool {
        map.lines[..<index].reduce(0) { $0 + $1.listFacts.fenceDelimiters } % 2 == 1
    }

    /// The old `pendingOpener` back-walk: the nearest line above `index` holding a bracket token.
    static func nearestBracketLine(_ map: StructureMap, before index: Int) -> Int? {
        var line = index - 1
        while line >= 0, map.lines[line].signature.brackets.isEmpty { line -= 1 }
        return line >= 0 ? line : nil
    }

    /// The old `pendingOpener` forward scan: a `]]` on any line after `index`.
    static func hasClosingBracket(_ map: StructureMap, after index: Int) -> Bool {
        map.lines[(index + 1)...].contains { $0.signature.brackets.contains(.close) }
    }

    /// Every question the three readers answer, against the walk. Nil when they agree.
    static func disagreement(_ map: StructureMap) -> String? {
        for index in 0...map.lines.count {
            if map.fenceParity(before: index) != fenceParity(map, before: index) {
                return "fenceParity(before: \(index))"
            }
            if map.nearestBracketLine(before: index) != nearestBracketLine(map, before: index) {
                return "nearestBracketLine(before: \(index))"
            }
        }
        for index in map.lines.indices
        where map.hasClosingBracket(after: index) != hasClosingBracket(map, after: index) {
            return "hasClosingBracket(after: \(index))"
        }
        return nil
    }
}

/// Text from the tokens that put marks on a line: fence delimiters, brackets, list items, plain words.
private func randomText(_ generator: inout SplitMix64, lines count: Int) -> String {
    let tokens = ["```", "```swift", "~~~", "[[Nota", "Nota]]", "[[a]]", "]]", "![[x", "- ", "1. ", "testo", "a", ""]
    return (0..<count).map { _ in
        (0..<Int(generator.next() % 3) + 1).map { _ in tokens[Int(generator.next() % UInt64(tokens.count))] }
            .joined(separator: " ")
    }.joined(separator: "\n")
}

private let edits = ["a", "\n", "```", "[[", "]]", "- ", "\n\n", "[[x]]", "~~~\n"]

@Suite struct StructureMapReadersTests {
    // (coverage) A map built from text: the three readers agree with the walk at every line, including the
    // index one past the last, which `pendingOpener` and `renumberWindow` may pass.
    @Test(arguments: 1...20)
    func theReadersAgreeWithTheWalkOnAMapBuiltFromText(_ seed: Int) {
        var generator = SplitMix64(seed: UInt64(seed))
        let text = randomText(&generator, lines: 5 + seed * 3)
        let map = StructureMap(text: text)

        let disagreement = Walk.disagreement(map)
        #expect(disagreement == nil, "seed \(seed): \(disagreement ?? "")")
    }

    // (coverage) Random edits through `apply`: the marks the map keeps ride along, and the readers stay equal
    // to the walk over the map's own lines after every edit.
    @Test(arguments: 1...20)
    func theReadersAgreeWithTheWalkAfterRandomEdits(_ seed: Int) {
        var generator = SplitMix64(seed: UInt64(seed) &* 7919)
        var text = randomText(&generator, lines: 12 + seed * 2) as NSString
        var map = StructureMap(text: text as String)

        for step in 0..<60 {
            let location = Int(generator.next() % UInt64(text.length + 1))
            let length = generator.next() % 4 == 0 ? Int(generator.next() % 6) : 0
            let old = NSRange(location: location, length: min(length, text.length - location))
            let replacement = edits[Int(generator.next() % UInt64(edits.count))]
            text = text.replacingCharacters(in: old, with: replacement) as NSString
            let edit = StorageEdit(
                range: NSRange(location: location, length: (replacement as NSString).length),
                delta: (replacement as NSString).length - old.length
            )
            map.apply(edit, in: text)

            let disagreement = Walk.disagreement(map)
            #expect(disagreement == nil, "seed \(seed) step \(step): \(disagreement ?? "")")
        }
    }

    // (coverage) A fence opened above a long stretch flips the parity of every line below it, and closing it
    // flips them back: the SPEC's edge case, read through the map.
    @Test func openingAFenceAboveFlipsEveryParityBelowAndClosingItFlipsThemBack() {
        let body = (1...30).map { "riga \($0)" }.joined(separator: "\n")
        var text = ("testa\n" + body) as NSString
        var map = StructureMap(text: text as String)
        #expect((0...map.lines.count).allSatisfy { !map.fenceParity(before: $0) })

        text = text.replacingCharacters(in: NSRange(location: 0, length: 0), with: "```\n") as NSString
        map.apply(StorageEdit(range: NSRange(location: 0, length: 4), delta: 4), in: text)
        #expect(!map.fenceParity(before: 0))
        #expect(
            (1...map.lines.count).allSatisfy { map.fenceParity(before: $0) }, "the fence is open below its delimiter"
        )
        #expect(Walk.disagreement(map) == nil)

        let closingAt = (text as String).range(of: "riga 10")!.lowerBound
        let closing = NSRange(closingAt..<closingAt, in: text as String)
        text = text.replacingCharacters(in: closing, with: "```\n") as NSString
        map.apply(StorageEdit(range: NSRange(location: closing.location, length: 4), delta: 4), in: text)
        let closedLine = map.lineIndex(containing: closing.location)
        #expect(map.fenceParity(before: closedLine))
        #expect(!map.fenceParity(before: closedLine + 1), "the fence is shut again below its closing delimiter")
        #expect(Walk.disagreement(map) == nil)
    }

    // (coverage) A spliced fragment replaces the marks inside its dirty range, and the readers follow.
    @Test func aSpliceReplacesTheMarksInsideTheDirtyRange() {
        let text = "uno\n[[a\ndue\ntre]]\nquattro\n"
        var map = StructureMap(text: text)
        let ns = text as NSString
        let dirty = ns.range(of: "due\n")
        #expect(map.nearestBracketLine(before: 3) == 1)

        let replacement = "```\n"
        let new = ns.replacingCharacters(in: dirty, with: replacement) as NSString
        map.apply(StorageEdit(range: NSRange(location: dirty.location, length: 4), delta: 0), in: new)
        let fragmentRange = NSRange(location: dirty.location, length: 4)
        map.splice(
            StructureMap(text: new.substring(with: fragmentRange)), at: fragmentRange.location, replacing: fragmentRange
        )

        #expect(map.fenceParity(before: 3), "the line after the new delimiter is inside a fence")
        #expect(Walk.disagreement(map) == nil)
    }

    // (coverage) The edges the walk gives: no bracket above, nothing after the last line.
    @Test func theReadersAnswerAtTheEdges() {
        let map = StructureMap(text: "uno\ndue\n[[a\ntre]]")
        #expect(map.nearestBracketLine(before: 0) == nil)
        #expect(map.nearestBracketLine(before: 2) == nil)
        #expect(map.nearestBracketLine(before: 3) == 2)
        #expect(map.nearestBracketLine(before: map.lines.count) == 3)
        #expect(map.hasClosingBracket(after: 2))
        #expect(!map.hasClosingBracket(after: map.lines.count - 1))
        #expect(!map.fenceParity(before: 0))
    }
}
