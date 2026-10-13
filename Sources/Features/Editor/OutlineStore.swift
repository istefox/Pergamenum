import Foundation
import Observation

// ADR-0096 §D6 and §D7, plan Task 4 (PG-406).
//
// The outline of one column as an observable value: the map that moves with the edits, the rows the
// sidebar draws from it, and the revision the map was last known to describe. A view that reads `rows`
// is invalidated only when a row changes, not on every keystroke.

/// One row of the sidebar's index.
struct OutlineRow: Equatable, Sendable {
    var kind: NoteOutline.Entry.Kind
    var title: String
    var level: Int
    var isFoldable: Bool
}

/// Where a set of rows came from, so a view can compare the source and not the rows.
enum OutlineRowsSource: Equatable {
    /// The store's own rows, at this generation.
    case store(ObjectIdentifier, generation: Int)
    /// Rows parsed from the text of this revision because the store did not describe it.
    case fresh(TextRevision)
}

/// How the store reached its present state: whole rebuilds, line splices and shifts.
struct OutlineTally: Equatable, Sendable {
    var rebuilds: Int
    var splices: Int
    var shifts: Int
}

@MainActor
@Observable
final class OutlineStore {
    private(set) var rows: [OutlineRow] = []
    /// Bumped each time `rows` changes.
    private(set) var generation = 0

    @ObservationIgnored private var storedMap = OutlineMap()
    @ObservationIgnored private var stamped: TextRevision?
    @ObservationIgnored private var counts = OutlineTally(rebuilds: 0, splices: 0, shifts: 0)

    var map: OutlineMap { storedMap }
    /// The revision the map was last stamped with; nil until stamped.
    var describes: TextRevision? { stamped }
    var tally: OutlineTally { counts }

    /// The lowest ordinal a shift reached since the rows were last brought level with the map, nil
    /// when nothing was shifted: every row before it is known unchanged.
    @ObservationIgnored private var shiftedFrom: Int?

    init() {}

    init(text: String) {
        rebuild(text: text)
    }

    func rebuild(text: String) {
        counts.rebuilds += 1
        storedMap.rebuild(text: text)
        shiftedFrom = nil
        publish(Self.rows(of: storedMap, in: 0..<storedMap.entries.count), replacing: 0..<rows.count)
    }

    func apply(_ edit: StorageEdit) {
        counts.shifts += 1
        let entries = storedMap.entries
        let reached = Self.firstIndex(in: entries) { !edit.precedes($0.range) }
        shiftedFrom = Swift.min(shiftedFrom ?? reached, reached)
        storedMap.apply(edit)
    }

    func splice(_ text: NSString, in dirty: NSRange, fences: OffsetRanges<StructureMap.Fence>) {
        counts.splices += 1
        storedMap.splice(text, in: dirty, fences: fences)
        // The entries outside the splice kept their kind and title (a shift moves them, a clip cuts only
        // what the splice re-reads), so the rows change at most from the entry before the window to the
        // next heading after it: the levels of the embeds below follow the heading above them.
        let entries = storedMap.entries
        let window = Self.spliced(in: entries, around: dirty, text: text)
        let low = Swift.min(window.lowerBound, shiftedFrom ?? window.lowerBound)
        shiftedFrom = nil
        let suffix = entries.count - window.upperBound
        guard rows.count - suffix >= low else {
            publish(Self.rows(of: storedMap, in: 0..<entries.count), replacing: 0..<rows.count)
            return
        }
        let start = Swift.max(0, low - 1)
        var end = window.upperBound
        while end < entries.count, case .embed = entries[end].kind { end += 1 }
        publish(Self.rows(of: storedMap, in: start..<end), replacing: start..<(end - entries.count + rows.count))
    }

    /// Says which revision the map now describes.
    func stamp(_ revision: TextRevision?) {
        stamped = revision
    }

    /// The rows for the note at `revision`: the store's when it describes that revision, parsed fresh
    /// from `text` otherwise, and without changing the store either way.
    func rows(describing revision: TextRevision, text: String) -> (rows: [OutlineRow], source: OutlineRowsSource) {
        // Read on both paths, so a view that asked observes the rows whichever answer it got.
        let current = rows
        if stamped == revision { return (current, .store(ObjectIdentifier(self), generation: generation)) }
        let fresh = OutlineMap(text: text)
        return (Self.rows(of: fresh, in: 0..<fresh.entries.count), .fresh(revision))
    }

    /// `foldedOrdinals(ofOffsets:in:)`, from the map when it describes `revision`.
    func foldedOrdinals(ofOffsets offsets: Set<Int>, describing revision: TextRevision, text: String) -> Set<Int> {
        guard !offsets.isEmpty else { return [] }
        if stamped == revision { return storedMap.ordinals(ofOffsets: offsets) }
        return Pergamenum.foldedOrdinals(ofOffsets: offsets, in: text)
    }

    /// The heading's UTF-16 offset when the entry can be folded; nil for an embed or a heading with
    /// nothing under it.
    func foldableOffset(ofEntry ordinal: Int) -> Int? {
        guard storedMap.isFoldable(ordinal) else { return nil }
        return storedMap.entries[ordinal].range.location
    }

    /// The entry's line, without its terminator: the range a click on the row puts the caret on.
    func lineRange(ofEntry ordinal: Int) -> NSRange? {
        guard storedMap.entries.indices.contains(ordinal) else { return nil }
        return storedMap.entries[ordinal].range
    }

    // MARK: The rows

    /// Replaces `old` in `rows` with `fresh`, and only when a value differs: an equal window leaves the
    /// observed property and the generation alone.
    private func publish(_ fresh: [OutlineRow], replacing old: Range<Int>) {
        guard !rows[old].elementsEqual(fresh) else { return }
        rows.replaceSubrange(old, with: fresh)
        generation += 1
    }

    /// The rows of the entries in `range`, the level of an embed read from the nearest heading above.
    private static func rows(of map: OutlineMap, in range: Range<Int>) -> [OutlineRow] {
        guard !range.isEmpty else { return [] }
        let entries = map.entries
        var enclosing: Int?
        return range.map { ordinal in
            let entry = entries[ordinal]
            let level: Int
            switch entry.kind {
            case .heading(let own):
                enclosing = own
                level = own
            case .embed:
                level = enclosing.map { Swift.min($0 + 1, 6) } ?? map.level(ofEntry: ordinal)
            }
            return OutlineRow(kind: entry.kind, title: entry.title, level: level, isFoldable: map.isFoldable(ordinal))
        }
    }

    /// The ordinals the splice over `dirty` wrote, in the map as it now is: from the first entry ending
    /// after the window's start to the first one starting at or after its end.
    private static func spliced(
        in entries: OffsetRanges<OutlineMap.Entry>, around dirty: NSRange, text: NSString
    ) -> Range<Int> {
        let window = OutlineMap.lineWindow(of: dirty, in: text)
        let low = firstIndex(in: entries) { NSMaxRange($0.range) > window.location }
        let high = firstIndex(in: entries) { $0.range.location >= NSMaxRange(window) }
        return low..<Swift.max(low, high)
    }

    /// One binary search: `isPast` false for a prefix of `entries` and true for the rest.
    private static func firstIndex(
        in entries: OffsetRanges<OutlineMap.Entry>, where isPast: (OutlineMap.Entry) -> Bool
    ) -> Int {
        var low = 0
        var high = entries.count
        while low < high {
            let middle = (low + high) / 2
            if isPast(entries[middle]) { high = middle } else { low = middle + 1 }
        }
        return low
    }
}
