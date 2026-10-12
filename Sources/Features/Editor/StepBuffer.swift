import Foundation

// ADR-0094 §D1 (the step buffer), §D2 (the entry protocols), §D4 (the copy counter) and §D5 (the tally).
//
// Entries sorted by position and split at one index, the step: the ones before it are stored with their
// absolute position, the ones after it relative to a pending delta added on read. An edit at the place
// of the previous one moves nothing but its own window; a far one moves the step across the entries in
// between, once. Prior art: Scintilla's `Partitioning`.
//
// Foundation only (ADR-0091 §D1, R-15).

/// One entry of a `StepBuffer`: something at an offset that can be moved by a delta.
protocol OffsetEntry: Equatable {
    /// The entry's current offset: a key, or a range's location.
    var position: Int { get }
    func moved(by delta: Int) -> Self
}

/// An entry that occupies a range of the text.
protocol RangedEntry: OffsetEntry {
    var range: NSRange { get }
    func with(range: NSRange) -> Self
}

extension NSRange: RangedEntry {
    var position: Int { location }
    var range: NSRange { self }

    func moved(by delta: Int) -> NSRange {
        NSRange(location: location + delta, length: length)
    }

    func with(range: NSRange) -> NSRange { range }
}

/// What a buffer's mutations touched since `resetTally()` (ADR-0094 §D5). The counting compiles only
/// under `#if DEBUG`; the reading API exists in every configuration.
struct StepTally: Equatable, Sendable {
    /// Entries the step crossed, entries removed, inserted or rewritten, and a whole store on a copy.
    var touched = 0
    /// Mutations that found the storage shared with another value and so copied it whole (§D4).
    var copies = 0
    var shifts = 0
    var splices = 0
    /// Whole-content builds: `init(sorted:)` and `rebuild(sorted:)`.
    var rebuilds = 0

    enum Operation: Sendable {
        case shift, splice
    }

    /// Whether this build counts at all. A Release build reads zeros, so the counter tests do not run.
    static var isCounting: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

/// A keyed entry: the offset-keyed table's element.
struct Keyed<Value: Equatable>: OffsetEntry {
    var position: Int
    var value: Value

    func moved(by delta: Int) -> Keyed<Value> {
        Keyed(position: position + delta, value: value)
    }
}

extension Keyed: Sendable where Value: Sendable {}

/// Entries sorted by position and split at a step (ADR-0094 §D1).
///
/// `front` holds the entries before the step, ascending, with their absolute positions. `back` holds the
/// entries after it in descending order, so the one next to the step is `back.last`, each stored
/// `pendingDelta` behind where it is. Reads never mutate, so a value held by TextKit's layout callback
/// stays safe to read.
struct StepBuffer<Entry: OffsetEntry>: RandomAccessCollection, Equatable {
    private var front: [Entry] = []
    private var back: [Entry] = []
    private var pendingDelta = 0

    #if DEBUG
    /// The copy detector of §D4: a value with no state whose reference count says whether this buffer's
    /// storage is shared with another value.
    private final class Owner: Sendable {}

    private var owner = Owner()
    private var counts = StepTally()
    #endif

    init() {}

    /// A buffer of `entries`, which must be in ascending position order.
    init(sorted entries: [Entry]) {
        rebuild(sorted: entries)
    }

    var startIndex: Int { 0 }
    var endIndex: Int { front.count + back.count }

    subscript(index: Int) -> Entry {
        if index < front.count { return front[index] }
        let entry = back[back.count - 1 - (index - front.count)]
        return pendingDelta == 0 ? entry : entry.moved(by: pendingDelta)
    }

    /// The index of the first entry for which `isPast` holds, and how many entries the search read. The
    /// buffer must be partitioned by `isPast`: false for a prefix, true for the rest. The only binary
    /// search of the type: every positional question of the two shapes goes through it.
    func partition(_ isPast: (Entry) -> Bool) -> (index: Int, probes: Int) {
        var low = 0
        var high = count
        var probes = 0
        while low < high {
            let middle = (low + high) / 2
            probes += 1
            if isPast(self[middle]) { high = middle } else { low = middle + 1 }
        }
        return (low, probes)
    }

    /// The index of the first entry whose position is at or after `position`.
    func lowerBound(_ position: Int) -> Int {
        partition { $0.position >= position }.index
    }

    /// Replaces the entries of `window` with `fresh`, and moves every entry after it by `delta`: the step
    /// moves to the window's end, the delta joins the pending one, and the window is swapped at the end of
    /// `front`. `fresh` is in the coordinates the entries have after the move.
    mutating func replace(
        _ window: Range<Int>, with fresh: [Entry], movingTheRestBy delta: Int, as operation: StepTally.Operation
    ) {
        precondition(window.lowerBound >= 0 && window.upperBound <= count, "window \(window) outside 0..<\(count)")
        noteMutation()
        moveStep(to: window.upperBound)
        pendingDelta += delta
        front.removeLast(window.count)
        front.append(contentsOf: fresh)
        if back.isEmpty { pendingDelta = 0 }
        #if DEBUG
        counts.touched += window.count + fresh.count
        switch operation {
        case .shift: counts.shifts += 1
        case .splice: counts.splices += 1
        }
        #endif
    }

    /// Replaces the whole contents in one build. `entries` must be in ascending position order.
    mutating func rebuild(sorted entries: [Entry]) {
        #if DEBUG
        assert(
            zip(entries, entries.dropFirst()).allSatisfy { $0.position <= $1.position },
            "StepBuffer.rebuild(sorted:) was handed entries out of order"
        )
        noteMutation()
        counts.rebuilds += 1
        counts.touched += entries.count
        #endif
        front = entries
        back = []
        pendingDelta = 0
    }

    static func == (lhs: StepBuffer, rhs: StepBuffer) -> Bool {
        lhs.count == rhs.count && lhs.elementsEqual(rhs)
    }

    var tally: StepTally {
        #if DEBUG
        counts
        #else
        StepTally()
        #endif
    }

    mutating func resetTally() {
        #if DEBUG
        counts = StepTally()
        #endif
    }

    // MARK: The step

    /// Moves the step to `index`, one entry at a time, each gaining or shedding the pending delta.
    private mutating func moveStep(to index: Int) {
        #if DEBUG
        counts.touched += abs(index - front.count)
        #endif
        while front.count > index {
            let entry = front.removeLast()
            back.append(pendingDelta == 0 ? entry : entry.moved(by: -pendingDelta))
        }
        while front.count < index {
            let entry = back.removeLast()
            front.append(pendingDelta == 0 ? entry : entry.moved(by: pendingDelta))
        }
    }

    /// Counts a copy when the storage is shared with another value (§D4): the mutation about to run
    /// copies every entry.
    private mutating func noteMutation() {
        #if DEBUG
        if !isKnownUniquelyReferenced(&owner) {
            counts.copies += 1
            counts.touched += count
            owner = Owner()
        }
        #endif
    }
}

extension StepBuffer: Sendable where Entry: Sendable {}
