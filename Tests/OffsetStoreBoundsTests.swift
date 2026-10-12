import Foundation
import Testing
@testable import Pergamenum

// ADR-0094 §D4 and §D5, plan docs/plans/sublinear-offset-state-pg-405.md, Task 2 (PG-405, R-04, R-05,
// R-06, R-08).
//
// What the shared type costs, as numbers: the probes of an exact lookup, the entries a keystroke touches
// at the same place as the previous one and after a jump, the copy a held value costs, and the identity
// of the values a table carries. The sizes are the line counts of the bench's notes at 50 KB, 200 KB and
// 1 MB; the stores are uniform, so that only the size differs between them.

/// Three stores of `lines` uniform lines of eight units each, and a naive twin of each to count against.
/// A keystroke is the pair the app makes: the edit, then the splice of its line.
struct UniformStores {
    static let pitch = 8
    /// The constant of ADR-0094 §D5.
    static let constant = 64

    private(set) var starts: [Int]
    private(set) var length: Int
    /// Where the last character was typed, in the text as it is now.
    private(set) var lastEdit = 0
    var table: OffsetTable<Int>
    var unspellable: OffsetRanges<NSRange>
    var embeds: OffsetRanges<NSRange>
    private var keysModel: [Int]
    private var unspellableModel: [NSRange]
    private var embedModel: [NSRange]

    init(lines: Int) {
        starts = (0..<lines).map { $0 * Self.pitch }
        length = lines * Self.pitch
        let ranges = (0..<lines).flatMap { line in
            [0, 2, 4].map { NSRange(location: line * Self.pitch + $0, length: 1) }
        }
        let runs = stride(from: 0, to: lines, by: 20).map { NSRange(location: $0 * Self.pitch + 1, length: 5) }
        keysModel = starts
        unspellableModel = ranges
        embedModel = runs
        table = OffsetTable(Dictionary(uniqueKeysWithValues: starts.enumerated().map { ($1, $0) }))
        unspellable = OffsetRanges(sorted: ranges)
        embeds = OffsetRanges(sorted: runs)
    }

    var tallies: [(name: String, tally: StepTally)] {
        [("table", table.tally), ("unspellable", unspellable.tally), ("embeds", embeds.tally)]
    }

    mutating func resetTallies() {
        table.resetTally()
        unspellable.resetTally()
        embeds.resetTally()
    }

    private func end(ofLine line: Int) -> Int {
        (line + 1 < starts.count ? starts[line + 1] : length) - 1
    }

    /// The entries of each store between the place the last character was typed and the end of `line`,
    /// counted on the twins: what a step moved there must cross.
    func crossed(toLine line: Int) -> [Int] {
        let target = end(ofLine: line)
        let low = min(lastEdit, target)
        let high = max(lastEdit, target)
        return [
            keysModel.filter { low <= $0 && $0 <= high }.count,
            unspellableModel.filter { low <= $0.location && $0.location <= high }.count,
            embedModel.filter { low <= $0.location && $0.location <= high }.count,
        ]
    }

    /// One character typed at the end of `line`, and the splice of the line.
    mutating func keystroke(inLine line: Int) {
        let location = end(ofLine: line)
        let edit = StorageEdit(range: NSRange(location: location, length: 1), delta: 1)
        table.apply(edit)
        unspellable.apply(edit, partial: .clip)
        embeds.apply(edit, partial: .drop)
        keysModel = keysModel.map { edit.shiftedKey($0) ?? $0 }
        unspellableModel = OffsetOracle.clip(unspellableModel, by: edit)
        embedModel = OffsetOracle.drop(embedModel, by: edit)
        for index in (line + 1)..<starts.count { starts[index] += 1 }
        length += 1
        lastEdit = location

        let dirty = NSRange(location: starts[line], length: end(ofLine: line) + 1 - starts[line])
        table.replace(in: dirty, with: [starts[line]: line])
        unspellable.spliceMerging([0, 2, 4].map { NSRange(location: starts[line] + $0, length: 1) }, replacing: dirty)
        embeds.splice(line % 20 == 0 ? [NSRange(location: starts[line] + 1, length: 5)] : [], replacing: dirty)
    }
}

/// A table value whose equality is identity (R-08).
final class Box: Equatable {
    static func == (lhs: Box, rhs: Box) -> Bool { lhs === rhs }
}

@Suite struct OffsetStoreBoundsTests {
    /// The line counts of the bench's fence note at 50 KB, 200 KB and 1 MB.
    static let lineCounts: [Int] = RestyleBudget.sizes.map { bytes in
        RestyleBudget.syntheticNote(bytes: bytes, variant: .fences).utf8.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
    }

    private static func probeBound(_ count: Int) -> Int {
        Int(ceil(log2(Double(count + 1)))) + 1
    }

    // MARK: R-04

    // (R-04) An exact lookup in a table of n keys reads at most log2(n + 1) + 1 entries, for every key and for
    // an absent key between two keys, and answers the dictionary's value.
    @Test(arguments: 0..<3)
    func aLookupTakesLogarithmicProbes(sizeIndex: Int) {
        let lines = Self.lineCounts[sizeIndex]
        let table = OffsetTable(Dictionary(uniqueKeysWithValues: (0..<lines).map { ($0 * UniformStores.pitch, $0) }))
        let bound = Self.probeBound(lines)
        var firstFailure: String?
        for line in 0..<lines where firstFailure == nil {
            let key = line * UniformStores.pitch
            let found = table.lookup(key)
            let absent = table.lookup(key + 1)
            if found.value != line || found.probes > bound {
                firstFailure = "key \(key): \(found) against \(line), bound \(bound)"
            }
            if absent.value != nil || absent.probes > bound {
                firstFailure = "absent \(key + 1): \(absent), bound \(bound)"
            }
        }
        #expect(firstFailure == nil, "\(lines) lines: \(firstFailure ?? "")")
        #expect(table[0] == 0 && table[1] == nil)
    }

    // (R-04) A partition of n ranges keeps the same bound, and finds the first entry past the predicate.
    @Test(arguments: 0..<3)
    func aPartitionTakesLogarithmicProbes(sizeIndex: Int) {
        let lines = Self.lineCounts[sizeIndex]
        let ranges = (0..<lines).flatMap { line in
            [0, 2, 4].map { NSRange(location: line * UniformStores.pitch + $0, length: 1) }
        }
        let buffer = StepBuffer(sorted: ranges)
        let bound = Self.probeBound(ranges.count)
        var thresholds = [0, 1, ranges.count * UniformStores.pitch]
        thresholds += (1..<40).map { $0 * lines * UniformStores.pitch / 41 + $0 % 5 }
        var firstFailure: String?
        for threshold in thresholds where firstFailure == nil {
            let answer = buffer.partition { $0.location >= threshold }
            let expected = ranges.partitioningIndex { $0.location >= threshold }
            if answer.index != expected || answer.probes > bound {
                firstFailure = "threshold \(threshold): \(answer) against \(expected), bound \(bound)"
            }
            if buffer.lowerBound(threshold) != expected {
                firstFailure = "lowerBound(\(threshold)) against \(expected)"
            }
        }
        #expect(firstFailure == nil, "\(ranges.count) ranges: \(firstFailure ?? "")")
    }

    // MARK: R-05

    // (R-05) The same keystroke made twice at the middle line: on the second, each store has shifted once,
    // spliced once, copied nothing and touched a number of entries that does not depend on the note's size.
    @Test(.enabled(if: StepTally.isCounting))
    func aKeystrokeAtTheSamePlaceTouchesAConstantNumberOfEntries() {
        var touchedBySize: [[Int]] = []
        for lines in Self.lineCounts {
            var stores = UniformStores(lines: lines)
            stores.keystroke(inLine: lines / 2)
            stores.resetTallies()
            stores.keystroke(inLine: lines / 2)

            for (name, tally) in stores.tallies {
                #expect(tally.touched <= UniformStores.constant, "\(lines) lines, \(name): \(tally)")
                #expect(tally.copies == 0, "\(lines) lines, \(name): \(tally)")
                #expect(tally.shifts == 1, "\(lines) lines, \(name): \(tally)")
                #expect(tally.splices == 1, "\(lines) lines, \(name): \(tally)")
            }
            touchedBySize.append(stores.tallies.map(\.tally.touched))
        }
        #expect(Set(touchedBySize).count == 1, "touched by size: \(touchedBySize)")
    }

    // MARK: R-06

    // (R-06) A keystroke near the top, then one at the middle, and the two again: each touches no more than
    // the entries between the two places plus the constant, whatever the note's size.
    @Test(.enabled(if: StepTally.isCounting), arguments: 0..<3)
    func aJumpTouchesTheEntriesBetweenPlusAConstant(sizeIndex: Int) {
        let lines = Self.lineCounts[sizeIndex]
        var stores = UniformStores(lines: lines)
        let top = lines / 50
        let middle = lines / 2
        stores.keystroke(inLine: middle)
        stores.keystroke(inLine: middle)

        for line in [top, middle, top, middle] {
            let crossed = stores.crossed(toLine: line)
            stores.resetTallies()
            stores.keystroke(inLine: line)
            for ((name, tally), between) in zip(stores.tallies, crossed) {
                #expect(
                    tally.touched <= between + UniformStores.constant,
                    "\(lines) lines, line \(line), \(name): \(tally), crossed \(between)"
                )
                #expect(tally.copies == 0, "\(lines) lines, line \(line), \(name): \(tally)")
                #expect(tally.shifts == 1 && tally.splices == 1, "\(lines) lines, line \(line), \(name): \(tally)")
            }
        }
    }

    // MARK: ADR-0094 §D4

    // (§D4) A copy held across a mutation is counted: one copy, and the whole store touched. Dropped, the
    // next mutation copies nothing.
    @Test(.enabled(if: StepTally.isCounting))
    func aHeldCopyIsCountedAndADroppedOneIsNot() {
        let edit = StorageEdit(range: NSRange(location: 400, length: 1), delta: 1)
        var table = OffsetTable(Dictionary(uniqueKeysWithValues: (0..<200).map { ($0 * 8, $0) }))
        var ranges = OffsetRanges(sorted: (0..<200).map { NSRange(location: $0 * 8, length: 2) })

        do {
            table.resetTally()
            ranges.resetTally()
            let heldTable = table
            let heldRanges = ranges
            table.apply(edit)
            ranges.apply(edit, partial: .clip)
            #expect(table.tally.copies == 1, "\(table.tally)")
            #expect(table.tally.touched >= table.count, "\(table.tally)")
            #expect(ranges.tally.copies == 1, "\(ranges.tally)")
            #expect(ranges.tally.touched >= ranges.count, "\(ranges.tally)")
            withExtendedLifetime((heldTable, heldRanges)) {}
        }

        table.resetTally()
        ranges.resetTally()
        table.apply(edit)
        ranges.apply(edit, partial: .clip)
        #expect(table.tally.copies == 0, "\(table.tally)")
        #expect(ranges.tally.copies == 0, "\(ranges.tally)")
    }

    // MARK: Rebuilds

    // (§D5) `init(_:)` and `init(sorted:)` each count one rebuild.
    @Test(.enabled(if: StepTally.isCounting))
    func buildingAStoreCountsOneRebuild() {
        #expect(OffsetTable([0: 1, 8: 2]).tally.rebuilds == 1)
        #expect(OffsetRanges(sorted: [NSRange(location: 0, length: 1)]).tally.rebuilds == 1)
        #expect(StepBuffer(sorted: [NSRange(location: 0, length: 1)]).tally.rebuilds == 1)
    }

    // MARK: R-08

    // (R-08) After random shifts and replacements every surviving value is the object it was inserted as.
    @Test(arguments: 1...20)
    func theValuesKeepTheirIdentity(seed: Int) {
        var generator = OffsetStoreGenerator(seed: UInt64(seed))
        var text = generator.text(maxLength: 300)
        var dict: [Int: Box] = [:]
        for start in OffsetStoreGenerator.lineStarts(of: text) { dict[start] = Box() }
        var table = OffsetTable(dict)

        for step in 0..<100 {
            let drawn = generator.edit(in: text)
            table.apply(drawn.edit)
            dict = OffsetOracle.shift(dict, by: drawn.edit)
            text = text.replacingCharacters(in: drawn.edit.oldRange, with: drawn.replacement) as NSString
            if generator.chance(50) {
                let dirty = NSRange(location: drawn.edit.range.location, length: drawn.edit.range.length)
                var fresh: [Int: Box] = [:]
                for start in OffsetStoreGenerator.lineStarts(of: text) where NSLocationInRange(start, dirty) {
                    fresh[start] = Box()
                }
                table.replace(in: dirty, with: fresh)
                dict = OffsetOracle.replace(dict, in: dirty, with: fresh)
            }
            #expect(
                table.count == dict.count, "seed \(seed), step \(step): \(table.count) entries against \(dict.count)"
            )
            for (key, value) in dict where table[key] !== value {
                Issue.record("seed \(seed), step \(step): key \(key) lost its object")
                return
            }
        }
    }
}

private extension Array {
    /// The index of the first element for which `isPast` holds (the array is partitioned by it).
    func partitioningIndex(where isPast: (Element) -> Bool) -> Int {
        firstIndex(where: isPast) ?? count
    }
}
