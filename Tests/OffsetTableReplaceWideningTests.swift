import Foundation
import Testing
@testable import Pergamenum

// ADR-0094 §D3, plan docs/plans/sublinear-offset-state-pg-405.md, Task 3 and Task 7 ((coverage), PG-405, R-02).
//
// `OffsetTable.replace(in:with:)` widens its window to the fresh keys' span when one falls outside `dirty`.
// The editor never hands it such a key (the fresh markers of a ranged restyle lie inside its dirty range), so
// the random run of `OffsetStoreModelTests` never reaches the widening. The contract is the plan's: the keys
// inside `dirty` are dropped, the fresh ones merged in, a fresh key winning, and an old key outside `dirty`
// stays even when it falls inside the widened window.

@Suite struct OffsetTableReplaceWideningTests {
    // (coverage) Fresh keys anywhere, over a table of keys at every fifth offset: the table equals the
    // dictionary rule after each replacement, and so do the values.
    @Test(arguments: 1...20)
    func aFreshKeyOutsideTheDirtyRangeIsMergedAndNothingOutsideItIsLost(_ seed: Int) {
        var generator = SplitMix64(seed: UInt64(seed) &* 104_729)
        var dict: [Int: Int] = Dictionary(uniqueKeysWithValues: stride(from: 0, through: 400, by: 5).map { ($0, $0) })
        var table = OffsetTable(dict)
        var nextValue = 10_000

        for step in 0..<50 {
            let location = Int(generator.next() % 380)
            let dirty = NSRange(location: location, length: Int(generator.next() % 40))
            var fresh: [Int: Int] = [:]
            for _ in 0..<Int(generator.next() % 8) {
                // Anywhere from before the table to past its end, so some keys are inside `dirty`, some
                // outside it, some on an old key and some on a new offset.
                fresh[Int(generator.next() % 440)] = nextValue
                nextValue += 1
            }

            table.replace(in: dirty, with: fresh)
            dict = OffsetOracle.replace(dict, in: dirty, with: fresh)

            #expect(table == dict, "seed \(seed) step \(step): \(dirty) with \(fresh.keys.sorted())")
            #expect(Array(table.keys) == dict.keys.sorted(), "seed \(seed) step \(step): keys")
            #expect(Array(table.values) == dict.keys.sorted().map { dict[$0]! }, "seed \(seed) step \(step): values")
        }
    }

    // (coverage) The hand case: a fresh key below the dirty range replaces the old key it lands on, a fresh key
    // above it is added, an old key between them and outside `dirty` stays, and the ones inside go.
    @Test func aFreshKeyOnAnOldKeyOutsideTheDirtyRangeWinsAndTheOtherOldKeysStay() {
        var table = OffsetTable([0: 0, 10: 1, 20: 2, 30: 3, 40: 4, 50: 5])

        table.replace(in: NSRange(location: 20, length: 20), with: [10: 100, 35: 101, 45: 102])

        #expect(table == [0: 0, 10: 100, 35: 101, 40: 4, 45: 102, 50: 5])
        #expect(Array(table.keys) == [0, 10, 35, 40, 45, 50])
    }

    // (coverage) An empty fresh set drops what lies in the dirty range and moves nothing else; an empty table
    // takes the fresh keys as they are.
    @Test func anEmptyReplacementDropsTheDirtyKeysAndAnEmptyTableTakesTheFreshOnes() {
        var table = OffsetTable([0: 0, 10: 1, 20: 2, 30: 3])
        table.replace(in: NSRange(location: 10, length: 15), with: [:])
        #expect(table == [0: 0, 30: 3])

        var empty = OffsetTable<Int>()
        empty.replace(in: NSRange(location: 5, length: 5), with: [7: 1, 3: 2])
        #expect(empty == [7: 1, 3: 2])
        #expect(Array(empty.keys) == [3, 7])
    }
}
