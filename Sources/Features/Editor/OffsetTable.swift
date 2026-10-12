import Foundation

// ADR-0094 §D2 (the keyed shape) and §D3 (the window and the collision).
//
// A table keyed by offset over a `StepBuffer`. An edit reaches only the keys between the first that does
// not precede its old range and the first that follows it, by `StorageEdit`'s own predicates; every key
// after them moves with the step's pending delta. The rule each key in the window obeys is
// `StorageEdit.shiftedKey`, and the table equals `StorageEdit.shiftedKeys` of the dictionary.
//
// Foundation only (ADR-0091 §D1, R-15).

/// A table keyed by offset whose values ride along unchanged (hidden markers by paragraph start).
/// It is not a `Collection`: a table whose keys are `Int` would answer `table[5]` both by position and
/// by key, and every reader means the key.
struct OffsetTable<Value: Equatable>: Equatable {
    private var buffer: StepBuffer<Keyed<Value>>

    init() {
        buffer = StepBuffer()
    }

    /// The table of `table`, in one sort.
    init(_ table: [Int: Value]) {
        buffer = StepBuffer(
            sorted: table.map { Keyed(position: $0.key, value: $0.value) }.sorted { $0.position < $1.position }
        )
    }

    var count: Int { buffer.count }
    var isEmpty: Bool { buffer.isEmpty }

    /// The keys, in ascending order.
    var keys: some RandomAccessCollection<Int> { buffer.lazy.map(\.position) }

    /// The values, in key order.
    var values: some RandomAccessCollection<Value> { buffer.lazy.map(\.value) }

    subscript(key: Int) -> Value? { lookup(key).value }

    /// The value at exactly `key`, and the entries the search read (R-04).
    func lookup(_ key: Int) -> (value: Value?, probes: Int) {
        let (index, probes) = buffer.partition { $0.position >= key }
        guard index < buffer.count else { return (nil, probes) }
        let entry = buffer[index]
        return (entry.position == key ? entry.value : nil, probes + 1)
    }

    /// The entry at the greatest key at or before `offset`.
    func entry(atOrBefore offset: Int) -> (key: Int, value: Value)? {
        let index = buffer.partition { $0.position > offset }.index
        guard index > 0 else { return nil }
        let entry = buffer[index - 1]
        return (entry.position, entry.value)
    }

    /// The entries whose key lies in `range` (`NSLocationInRange`), in key order.
    func entries(in range: NSRange) -> [(key: Int, value: Value)] {
        let low = buffer.lowerBound(range.location)
        let high = max(low, buffer.lowerBound(NSMaxRange(range)))
        return buffer[low..<high].map { ($0.position, $0.value) }
    }

    /// `StorageEdit.shiftedKeys`. A key is the empty range at its offset: the ones that precede the old
    /// range stay, the ones that follow it move by the delta, `precedes` winning when both hold, and the
    /// ones strictly inside it are dropped. Where a moved key lands on one that stayed (a deletion from a
    /// key to the next), the moved key wins; both sit at the window's left edge. `fresh` is built from the
    /// window before `low -= 1` widens it over the stayed key: built after, it would carry that key too.
    mutating func apply(_ edit: StorageEdit) {
        func key(_ entry: Keyed<Value>) -> NSRange { NSRange(location: entry.position, length: 0) }
        var low = buffer.partition { !edit.precedes(key($0)) }.index
        let high = max(low, buffer.partition { edit.follows(key($0)) && !edit.precedes(key($0)) }.index)
        let fresh = buffer[low..<high].compactMap { entry in
            edit.shiftedKey(entry.position).map { Keyed(position: $0, value: entry.value) }
        }
        if low > 0, high < buffer.count, buffer[low - 1].position == buffer[high].position + edit.delta {
            low -= 1
        }
        buffer.replace(low..<high, with: fresh, movingTheRestBy: edit.delta, as: .shift)
    }

    /// The keys inside `dirty` are dropped and `fresh` merged in, a fresh key winning. The window widens to
    /// the fresh keys' span when one falls outside `dirty`; inside it, an old key outside `dirty` stays.
    mutating func replace(in dirty: NSRange, with fresh: [Int: Value]) {
        let incoming = fresh.map { Keyed(position: $0.key, value: $0.value) }.sorted { $0.position < $1.position }
        var lowest = dirty.location
        var highest = NSMaxRange(dirty)
        if let first = incoming.first, let last = incoming.last {
            lowest = min(lowest, first.position)
            highest = max(highest, last.position + 1)
        }
        let low = buffer.lowerBound(lowest)
        let high = max(low, buffer.lowerBound(highest))

        var merged: [Keyed<Value>] = []
        merged.reserveCapacity(incoming.count + high - low)
        var cursor = 0
        for entry in buffer[low..<high]
        where !NSLocationInRange(entry.position, dirty) && fresh[entry.position] == nil {
            while cursor < incoming.count, incoming[cursor].position < entry.position {
                merged.append(incoming[cursor])
                cursor += 1
            }
            merged.append(entry)
        }
        merged.append(contentsOf: incoming[cursor...])
        buffer.replace(low..<high, with: merged, movingTheRestBy: 0, as: .splice)
    }

    static func == (lhs: OffsetTable, rhs: [Int: Value]) -> Bool {
        lhs.buffer.count == rhs.count && lhs.buffer.allSatisfy { rhs[$0.position] == $0.value }
    }

    var tally: StepTally { buffer.tally }

    mutating func resetTally() { buffer.resetTally() }
}

extension OffsetTable: Sendable where Value: Sendable {}
