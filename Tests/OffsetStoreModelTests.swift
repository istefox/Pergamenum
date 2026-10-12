import Foundation
import Testing
@testable import Pergamenum

// ADR-0094 §D2 and §D3, plan docs/plans/sublinear-offset-state-pg-405.md, Task 2 (PG-405, R-01, R-02).
//
// The shared type against a naive implementation of the `StorageEdit` rule, after every operation of a
// random sequence and on each of the SPEC's edge cases. The oracle is `OffsetStoreModel.swift`.

@Suite struct OffsetStoreModelTests {
    // MARK: R-01 and R-02, random sequences

    // (R-01, R-02) Seeds 1 to 20, 200 operations each: edits and the splices that follow them, over a keyed
    // table and four range lists. After every operation each store equals its twin.
    @Test(arguments: 1...20)
    func theStoresEqualTheirOraclesAfterEveryOperation(seed: Int) {
        var run = OffsetStoreRun(seed: UInt64(seed))
        for step in 0..<200 {
            run.step()
            if let message = run.firstDisagreement() {
                Issue.record("seed \(seed), operation \(step): \(message)")
                return
            }
        }
    }

    // (R-01) The lookups answer what a scan of the twin answers, after every operation.
    @Test(arguments: 1...20)
    func theQueriesAnswerWhatAScanOfTheOracleAnswers(seed: Int) {
        var run = OffsetStoreRun(seed: UInt64(seed))
        for step in 0..<100 {
            run.step()
            if let message = run.firstQueryDisagreement() {
                Issue.record("seed \(seed), operation \(step): \(message)")
                return
            }
        }
    }

    // MARK: The SPEC's edge cases, one argument each

    enum Edge: String, CaseIterable, CustomStringConvertible {
        case emptyStore, editAtZero, editAtTheEnd, wholeNoteDeleted, lineSplit, linesJoined
        case jumpThenAlternation, collisionOfAMovedKey, rangesCutOnBothSides, rangeStretched, rangeLostInsideAnEdit

        var description: String { rawValue }
    }

    private static let note = "alpha beta\ngamma delta\nepsilon zeta\neta theta\niota kappa\nlambda mu\n"

    /// The edits of one edge case, applied one after the other with a splice after each.
    private static func script(_ edge: Edge, length: Int) -> [(NSRange, String)] {
        switch edge {
        case .emptyStore: [(NSRange(location: 0, length: 0), "ab\ncd")]
        case .editAtZero: [(NSRange(location: 0, length: 0), "x"), (NSRange(location: 0, length: 1), "")]
        case .editAtTheEnd:
            [(NSRange(location: length, length: 0), "x"), (NSRange(location: length, length: 1), ""),
             (NSRange(location: length - 1, length: 1), "")]
        case .wholeNoteDeleted:
            [(NSRange(location: 0, length: length), ""), (NSRange(location: 0, length: 0), "new\ntext")]
        case .lineSplit: [(NSRange(location: 5, length: 0), "\n")]
        case .linesJoined: [(NSRange(location: 10, length: 1), "")]
        case .jumpThenAlternation:
            [(NSRange(location: 3, length: 0), "x"), (NSRange(location: length - 8, length: 0), "y"),
             (NSRange(location: 4, length: 0), "x"), (NSRange(location: length - 6, length: 0), "y"),
             (NSRange(location: 5, length: 0), "x"), (NSRange(location: length - 4, length: 0), "y")]
        case .collisionOfAMovedKey: [(NSRange(location: 11, length: 12), "")]
        case .rangesCutOnBothSides: [(NSRange(location: 8, length: 9), ""), (NSRange(location: 4, length: 14), "Q")]
        case .rangeStretched: [(NSRange(location: 9, length: 0), "123"), (NSRange(location: 7, length: 4), "QQ")]
        case .rangeLostInsideAnEdit: [(NSRange(location: 3, length: 20), "")]
        }
    }

    @Test(arguments: Edge.allCases, 1...6)
    func theEdgeCasesEqualTheirOracles(edge: Edge, seed: Int) {
        var run = OffsetStoreRun(
            seed: UInt64(seed), text: edge == .emptyStore ? "" : Self.note, populated: edge != .emptyStore
        )
        #expect(run.firstDisagreement() == nil, "\(edge): the stores are not built as their twins")
        for (index, edit) in Self.script(edge, length: run.length).enumerated() {
            run.replace(edit.0, with: edit.1)
            if let message = run.firstDisagreement() {
                Issue.record("\(edge), seed \(seed), edit \(index): \(message)")
                return
            }
            run.splice()
            if let message = run.firstDisagreement() {
                Issue.record("\(edge), seed \(seed), splice after edit \(index): \(message)")
                return
            }
            if let message = run.firstQueryDisagreement() {
                Issue.record("\(edge), seed \(seed), query after edit \(index): \(message)")
                return
            }
        }
    }

    // (R-01) A deletion that lands a moved key on a stayed key: the moved key wins.
    @Test func aMovedKeyWinsOverAStayedKey() {
        var table = OffsetTable([0: 10, 3: 11, 6: 12, 9: 13])
        let edit = StorageEdit(range: NSRange(location: 3, length: 0), delta: -3)

        table.apply(edit)

        #expect(table == [0: 10, 3: 12, 6: 13])
        #expect(table[3] == 12)
        #expect(table == edit.shiftedKeys([0: 10, 3: 11, 6: 12, 9: 13]))
    }

    // (R-01) The three cases where the map's fence rule parts from `StorageEdit.shifted` (ADR-0094 §D3).
    @Test func theEndAnchoredRuleHoldsInItsThreeCases() {
        let fences = [NSRange(location: 0, length: 4), NSRange(location: 6, length: 6)]

        var atTheEnd = OffsetRanges(sorted: fences)
        atTheEnd.apply(StorageEdit(range: NSRange(location: 12, length: 2), delta: 2), anchoringTheEndOf: 12)
        #expect(atTheEnd == [NSRange(location: 0, length: 4), NSRange(location: 6, length: 8)])

        var atTheFenceStart = OffsetRanges(sorted: fences)
        atTheFenceStart.apply(StorageEdit(range: NSRange(location: 6, length: 2), delta: 2), anchoringTheEndOf: 12)
        #expect(atTheFenceStart == [NSRange(location: 0, length: 4), NSRange(location: 6, length: 8)])

        var deleted = OffsetRanges(sorted: fences)
        deleted.apply(StorageEdit(range: NSRange(location: 6, length: 0), delta: -6), anchoringTheEndOf: 12)
        #expect(deleted == [NSRange(location: 0, length: 4), NSRange(location: 6, length: 0)])

        // And the dropping rule, which the same three edits would have applied.
        var dropping = OffsetRanges(sorted: fences)
        dropping.apply(StorageEdit(range: NSRange(location: 6, length: 0), delta: -6), partial: .drop)
        #expect(dropping == [NSRange(location: 0, length: 4)])
    }

    // (R-01) What an edit does to a range it reaches: the parts outside it stay, the range it contains
    // stretches, the range inside it is lost.
    @Test func aRangeIsCutStretchedOrLostAsStorageEditSays() {
        let cut = [NSRange(location: 0, length: 5), NSRange(location: 7, length: 5), NSRange(location: 14, length: 2)]
        let deletion = StorageEdit(range: NSRange(location: 3, length: 0), delta: -6)
        var clipped = OffsetRanges(sorted: cut)
        clipped.apply(deletion, partial: .clip)
        #expect(clipped == [
            NSRange(location: 0, length: 3), NSRange(location: 3, length: 3), NSRange(location: 8, length: 2),
        ])
        var dropped = OffsetRanges(sorted: cut)
        dropped.apply(deletion, partial: .drop)
        #expect(dropped == [NSRange(location: 8, length: 2)])

        for partial in [OffsetRanges<NSRange>.Partial.clip, .drop] {
            var stretched = OffsetRanges(sorted: [NSRange(location: 2, length: 10)])
            stretched.apply(StorageEdit(range: NSRange(location: 5, length: 3), delta: 3), partial: partial)
            #expect(stretched == [NSRange(location: 2, length: 13)])

            var lost = OffsetRanges(sorted: [NSRange(location: 4, length: 2)])
            lost.apply(StorageEdit(range: NSRange(location: 3, length: 1), delta: -5), partial: partial)
            #expect(lost.isEmpty)
        }
    }

    // (R-01) The window predicates and the end-anchored rule are `StorageEdit`'s own (ADR-0094 §D3).
    @Test(arguments: 1...20)
    func theWindowPredicatesAndTheAnchoredRuleFollowTheirDefinitions(seed: Int) {
        var generator = OffsetStoreGenerator(seed: UInt64(seed))
        var firstFailure: String?
        var comparisons = 0
        for _ in 0..<50 where firstFailure == nil {
            let text = generator.text(maxLength: 40)
            let drawn = generator.edit(in: text)
            let edit = drawn.edit
            // The text's own length after the edit, the value the old rule took. It coincides with
            // `text.length + delta` by construction, so this compares nothing about the substitution
            // `shifted(_:anchoringTheEndOf:)` makes: that invariant is carried by the Debug assert in
            // `StructureMap.applying` (ADR-0094 §D3).
            let newLength = text.replacingCharacters(in: edit.oldRange, with: drawn.replacement).utf16.count
            for _ in 0..<10 {
                guard let range = generator.range(in: text.length) else { continue }
                comparisons += 1
                if edit.precedes(range) != (NSMaxRange(range) <= edit.oldRange.location) {
                    firstFailure = firstFailure ?? "precedes \(range) by \(edit)"
                }
                if edit.follows(range) != (range.location >= NSMaxRange(edit.oldRange)) {
                    firstFailure = firstFailure ?? "follows \(range) by \(edit)"
                }
                let anchored = OffsetOracle.anchor([range], by: edit, oldLength: text.length, newLength: newLength)
                if edit.shifted(range, anchoringTheEndOf: text.length) != anchored.first {
                    firstFailure = firstFailure ?? "anchored \(range) by \(edit)"
                }
            }
        }
        #expect(firstFailure == nil, "seed \(seed): \(firstFailure ?? "")")
        #expect(comparisons > 0, "seed \(seed): every text was empty, so nothing was compared")
    }

    // MARK: R-02 at the boundaries

    private static func hasNoTouchingNeighbours(_ ranges: OffsetRanges<NSRange>) -> Bool {
        zip(ranges, ranges.dropFirst()).allSatisfy { NSMaxRange($0) < $1.location }
    }

    // (R-02) A deletion leaves two unspellable ranges touching at the edit point; the splice covering that
    // point merges them, as `MarkdownStyler.spliced` does.
    @Test func aDeletionThatLeavesTwoRangesTouchingIsMergedBySpliceMerging() {
        let current = [NSRange(location: 2, length: 3), NSRange(location: 8, length: 3)]
        var ranges = OffsetRanges(sorted: current)
        let edit = StorageEdit(range: NSRange(location: 5, length: 0), delta: -3)

        ranges.apply(edit, partial: .clip)
        #expect(ranges == [NSRange(location: 2, length: 3), NSRange(location: 5, length: 3)])
        let dirty = NSRange(location: 5, length: 0)
        ranges.spliceMerging([], replacing: dirty)

        let expected = MarkdownStyler.spliced(OffsetOracle.clip(current, by: edit), replacing: dirty, with: [])
        #expect(ranges == expected)
        #expect(ranges == [NSRange(location: 2, length: 6)])
        #expect(Self.hasNoTouchingNeighbours(ranges))
    }

    // (R-02) A head entry that crosses `dirty.location`, and a tail entry that crosses the dirty range's end.
    @Test(arguments: [
        (NSRange(location: 0, length: 10), NSRange(location: 4, length: 4), [NSRange(location: 4, length: 3)]),
        (NSRange(location: 0, length: 10), NSRange(location: 4, length: 4), []),
        (NSRange(location: 0, length: 10), NSRange(location: 4, length: 4), [NSRange(location: 5, length: 2)]),
        (NSRange(location: 0, length: 10), NSRange(location: 4, length: 4),
         [NSRange(location: 4, length: 1), NSRange(location: 7, length: 1)]),
        (NSRange(location: 2, length: 10), NSRange(location: 0, length: 5), [NSRange(location: 0, length: 5)]),
        (NSRange(location: 2, length: 10), NSRange(location: 0, length: 5), [NSRange(location: 1, length: 2)]),
        (NSRange(location: 2, length: 10), NSRange(location: 0, length: 5), []),
    ])
    func aRangeCrossingADirtyEndIsMergedAtTheSeam(
        current: NSRange, dirty: NSRange, fragment: [NSRange]
    ) {
        var ranges = OffsetRanges(sorted: [current])

        ranges.spliceMerging(fragment, replacing: dirty)

        let expected = MarkdownStyler.spliced([current], replacing: dirty, with: fragment)
        #expect(ranges == expected)
        #expect(Self.hasNoTouchingNeighbours(ranges))
    }

    // MARK: Logical equality

    // (R-01) A buffer brought to some entries through many edits, with its step in the middle, equals one
    // built from the same entries, and the tally takes no part.
    @Test(arguments: 1...10)
    func aBufferEqualsOneBuiltFromItsEntries(seed: Int) {
        var run = OffsetStoreRun(seed: UInt64(seed))
        for _ in 0..<120 { run.step() }

        #expect(run.table == OffsetTable(run.dict))
        #expect(run.clip == OffsetRanges(sorted: run.clipModel))
        #expect(OffsetRanges(sorted: Array(run.clip)) == run.clip)
        #expect(OffsetRanges(sorted: run.clipModel) == run.clipModel)
        #expect(run.clipModel == OffsetRanges(sorted: run.clipModel))
        var fresh = OffsetRanges(sorted: run.mergingModel)
        fresh.resetTally()
        #expect(run.merging == fresh)
    }
}
