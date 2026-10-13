import Foundation

// ADR-0094 §D2 (the range-list shape) and §D3 (the window, the splices and the end-anchored rule).
//
// An ordered list of ranges over a `StepBuffer`, sorted by location with ends that do not decrease
// (disjoint or touching ranges), so the entries an edit reaches are one contiguous window found by two
// searches with `StorageEdit`'s predicates. Each entry in the window goes through `StorageEdit`'s own
// rule; every entry after it moves with the step's pending delta.
//
// Foundation only (ADR-0091 §D1, R-15).

/// An ordered list of disjoint ranges (unspellable ranges, embed runs, the structure map's run lists),
/// a `RandomAccessCollection` in location order.
struct OffsetRanges<Entry: RangedEntry>: RandomAccessCollection, Equatable {
    /// What an edit does to a range it cuts: keep the parts outside it, or lose the range.
    enum Partial: Sendable {
        case clip, drop
    }

    private var buffer: StepBuffer<Entry>

    init() {
        buffer = StepBuffer()
    }

    /// The list of `entries`: ascending locations, and ends that do not decrease (asserted in Debug).
    init(sorted entries: [Entry]) {
        #if DEBUG
        assert(
            zip(entries, entries.dropFirst()).allSatisfy { NSMaxRange($0.range) <= NSMaxRange($1.range) },
            "OffsetRanges.init(sorted:) was handed ranges whose ends decrease"
        )
        #endif
        buffer = StepBuffer(sorted: entries)
    }

    var startIndex: Int { buffer.startIndex }
    var endIndex: Int { buffer.endIndex }

    subscript(index: Int) -> Entry { buffer[index] }

    // MARK: Edits

    /// `.clip` is `StorageEdit.clipped`, `.drop` is `StorageEdit.shifted`.
    mutating func apply(_ edit: StorageEdit, partial: Partial) {
        let window = reach(of: edit)
        let fresh: [Entry] = switch partial {
        case .clip:
            buffer[window].flatMap { entry in edit.clipped(entry.range).map { entry.with(range: $0) } }
        case .drop:
            buffer[window].compactMap { entry in edit.shifted(entry.range).map { entry.with(range: $0) } }
        }
        buffer.replace(window, with: fresh, movingTheRestBy: edit.delta, as: .shift)
    }

    /// The map's fence rule, `StorageEdit.shifted(_:anchoringTheEndOf:)`: an entry that reached `oldLength`
    /// and starts at or before the edit still reaches the new end; every other entry takes the dropping
    /// rule. The anchored entries end the list, so they sit next to the window (ADR-0094 §D3).
    mutating func apply(_ edit: StorageEdit, anchoringTheEndOf oldLength: Int) {
        var window = reach(of: edit)
        let anchoredStart = buffer.partition { NSMaxRange($0.range) >= oldLength }.index
        let anchoredEnd = buffer.partition { $0.range.location > edit.oldRange.location }.index
        if anchoredStart < anchoredEnd {
            window = Swift.min(window.lowerBound, anchoredStart)..<Swift.max(window.upperBound, anchoredEnd)
        }
        let fresh = buffer[window].compactMap { entry in
            edit.shifted(entry.range, anchoringTheEndOf: oldLength).map { entry.with(range: $0) }
        }
        buffer.replace(window, with: fresh, movingTheRestBy: edit.delta, as: .shift)
    }

    /// `StructureMap.spliced`'s partition: the entries that end at or before `dirty`, `fragment`, and
    /// the entries that start at or after its end (and end after its start). Anything else is dropped.
    mutating func splice(_ fragment: [Entry], replacing dirty: NSRange) {
        let end = NSMaxRange(dirty)
        let low = buffer.partition { NSMaxRange($0.range) > dirty.location }.index
        let high = buffer.partition { $0.range.location >= end && NSMaxRange($0.range) > dirty.location }.index
        buffer.replace(low..<Swift.max(low, high), with: fragment, movingTheRestBy: 0, as: .splice)
    }

    /// The entries an edit reaches: those that neither precede nor follow its old range, `precedes`
    /// winning when both hold. Contiguous, because the ends do not decrease.
    private func reach(of edit: StorageEdit) -> Range<Int> {
        let low = buffer.partition { !edit.precedes($0.range) }.index
        let high = buffer.partition { edit.follows($0.range) && !edit.precedes($0.range) }.index
        return low..<Swift.max(low, high)
    }

    // MARK: Queries

    /// Whether any entry intersects `range`: shares at least one unit with it.
    func intersects(_ range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        return indices(intersecting: range).contains { NSIntersectionRange(buffer[$0].range, range).length > 0 }
    }

    /// How many entries end at or before `offset`.
    func count(endingAtOrBefore offset: Int) -> Int {
        buffer.partition { NSMaxRange($0.range) > offset }.index
    }

    /// The entries with `location < NSMaxRange(range)` and an end after `range.location`.
    func indices(intersecting range: NSRange) -> Range<Int> {
        let low = buffer.partition { NSMaxRange($0.range) > range.location }.index
        let high = buffer.partition { $0.range.location >= NSMaxRange(range) }.index
        return low..<Swift.max(low, high)
    }

    /// The entries with `location <= NSMaxRange(range)` and an end at or after `range.location`.
    func indices(touching range: NSRange) -> Range<Int> {
        let low = buffer.partition { NSMaxRange($0.range) >= range.location }.index
        let high = buffer.partition { $0.range.location > NSMaxRange(range) }.index
        return low..<Swift.max(low, high)
    }

    /// The entries whose location lies in `range` (`NSLocationInRange`), in order.
    func entries(startingIn range: NSRange) -> [Entry] {
        let low = buffer.partition { $0.range.location >= range.location }.index
        let high = buffer.partition { $0.range.location >= NSMaxRange(range) }.index
        return Array(buffer[low..<Swift.max(low, high)])
    }

    static func == (lhs: OffsetRanges, rhs: [Entry]) -> Bool {
        lhs.buffer.count == rhs.count && lhs.buffer.elementsEqual(rhs)
    }

    static func == (lhs: [Entry], rhs: OffsetRanges) -> Bool {
        rhs == lhs
    }

    var tally: StepTally { buffer.tally }

    mutating func resetTally() { buffer.resetTally() }
}

extension OffsetRanges where Entry == NSRange {
    /// `MarkdownStyler.spliced`: `fragment` (merged) in place of `dirty`, re-merged at the two seams. It runs
    /// `MarkdownStyler.spliced` itself on the window: the entries that reach into `dirty`, one entry before
    /// it, and the entries after it for as long as the seam merges. It equals the whole-list splice while
    /// the entries after `dirty` are merged among themselves (ADR-0094 §D3), which a shift leaves true
    /// everywhere but at an edit point, and `dirty` covers every edit since the last splice.
    mutating func spliceMerging(_ fragment: [NSRange], replacing dirty: NSRange) {
        let end = NSMaxRange(dirty)
        let reached = count(endingAtOrBefore: dirty.location)
        let low = Swift.max(0, reached - 1)
        var high = buffer.partition { $0.location >= end && NSMaxRange($0) > dirty.location }.index
        var result = MarkdownStyler.spliced(Array(buffer[low..<high]), replacing: dirty, with: fragment)
        while high < buffer.count, let last = result.last, buffer[high].location <= NSMaxRange(last) {
            let merged = Swift.max(NSMaxRange(last), NSMaxRange(buffer[high]))
            result[result.count - 1] = NSRange(location: last.location, length: merged - last.location)
            high += 1
        }
        buffer.replace(low..<high, with: result, movingTheRestBy: 0, as: .splice)
    }
}

extension OffsetRanges: Sendable where Entry: Sendable {}
