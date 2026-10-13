import Foundation
@testable import Pergamenum

// ADR-0094 §D3, plan docs/plans/sublinear-offset-state-pg-405.md, Task 2 (PG-405, R-01, R-02).
//
// The model the shared type is checked against: today's code, written out here so that it survives the
// day the app stops using it (Task 6 removes `StructureMap`'s private copies). The oracle holds the
// naive implementations, the generator draws edits and range lists from `SplitMix64`, and `OffsetStoreRun`
// keeps a text, a store of every shape and the naive twin of each, and says where they part.

// MARK: - The oracle

enum OffsetOracle {
    /// A keyed table, shifted: `StorageEdit.shiftedKeys`.
    static func shift<Value>(_ table: [Int: Value], by edit: StorageEdit) -> [Int: Value] {
        edit.shiftedKeys(table)
    }

    /// The delegate's splice (`EditorDecorationDelegate.splice`): the keys inside `dirty` are dropped and the
    /// fresh entries merged in, a fresh key winning.
    static func replace<Value>(_ table: [Int: Value], in dirty: NSRange, with fresh: [Int: Value]) -> [Int: Value] {
        var result = table.filter { !NSLocationInRange($0.key, dirty) }
        result.merge(fresh) { _, new in new }
        return result
    }

    /// The unspellable ranges' shift (`shiftStyledRanges`): `StorageEdit.clipped`.
    static func clip(_ ranges: [NSRange], by edit: StorageEdit) -> [NSRange] {
        ranges.flatMap { edit.clipped($0) }
    }

    /// The embed runs' shift: `StorageEdit.shifted`, dropping what the edit cut.
    static func drop(_ ranges: [NSRange], by edit: StorageEdit) -> [NSRange] {
        ranges.compactMap { edit.shifted($0) }
    }

    /// The map's fence shift, `StructureMap.shifted(_:by:oldLength:newLength:)` copied verbatim
    /// (`StructureMap.swift:266-271`): `StorageEdit.shifted`, except that a range that reached the end of
    /// the old text still does. Like the old rule it takes `newLength`, the real length of the text after
    /// the edit, where `StorageEdit.shifted(_:anchoringTheEndOf:)` computes `oldLength + delta`. A caller
    /// hands it the edited text's own length, which equals `oldLength + delta` by construction, so the two
    /// coincide here and this does not check the substitution: that invariant is carried by the Debug
    /// assert in `StructureMap.applying` (ADR-0094 §D3).
    static func anchor(_ ranges: [NSRange], by edit: StorageEdit, oldLength: Int, newLength: Int) -> [NSRange] {
        ranges.compactMap { range in
            if NSMaxRange(range) == oldLength, edit.oldRange.location >= range.location {
                return NSRange(location: range.location, length: newLength - range.location)
            }
            return edit.shifted(range)
        }
    }

    /// `StructureMap.spliced` copied verbatim (`StructureMap.swift:274-281`), for ranges.
    static func splice(_ runs: [NSRange], dirty: NSRange, with fragment: [NSRange]) -> [NSRange] {
        let end = NSMaxRange(dirty)
        let before = runs.filter { NSMaxRange($0) <= dirty.location }
        let after = runs.filter { $0.location >= end && NSMaxRange($0) > dirty.location }
        return before + fragment + after
    }

    /// The embed runs' splice (`NoteTextView+Coordinator.swift:811-813`). It parts from `splice` only for
    /// an empty run at an empty dirty range, which an embed run never is.
    static func embedSplice(_ runs: [NSRange], dirty: NSRange, with fragment: [NSRange]) -> [NSRange] {
        runs.filter { NSMaxRange($0) <= dirty.location } + fragment + runs.filter { $0.location >= NSMaxRange(dirty) }
    }

    /// The unspellable ranges' splice: `MarkdownStyler.spliced` itself.
    static func spliceMerging(_ ranges: [NSRange], dirty: NSRange, with fragment: [NSRange]) -> [NSRange] {
        MarkdownStyler.spliced(ranges, replacing: dirty, with: fragment)
    }
}

// MARK: - The generator

struct OffsetStoreGenerator {
    var random: SplitMix64

    init(seed: UInt64) { random = SplitMix64(seed: seed) }

    mutating func int(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &random) }

    mutating func chance(_ percent: Int) -> Bool { int(1...100) <= percent }

    /// A text of up to `maxLength` UTF-16 units, split into random lines.
    mutating func text(maxLength: Int) -> NSString {
        var result = ""
        for _ in 0..<int(0...maxLength) { result += chance(18) ? "\n" : (chance(20) ? " " : "a") }
        return result as NSString
    }

    private mutating func replacement() -> String {
        var result = ""
        for _ in 0..<int(1...4) { result += chance(20) ? "\n" : "b" }
        return result
    }

    /// An edit of the text: an insertion, a deletion, a replacement, the deletion of the whole text, or one
    /// at 0 or at the end. `range` is in the text as it will be, as `StorageEdit` has it.
    mutating func edit(in text: NSString) -> (edit: StorageEdit, replacement: String) {
        let length = text.length
        var old = NSRange(location: 0, length: 0)
        var new = ""
        switch int(0...6) {
        case 0:
            old = NSRange(location: int(0...length), length: 0)
            new = replacement()
        case 1 where length > 0:
            let location = int(0...(length - 1))
            old = NSRange(location: location, length: int(1...min(6, length - location)))
        case 2 where length > 0:
            let location = int(0...(length - 1))
            old = NSRange(location: location, length: int(1...min(6, length - location)))
            new = replacement()
        case 3 where length > 0:
            old = NSRange(location: 0, length: length)
        case 4:
            new = replacement()
        case 5:
            old = NSRange(location: length, length: 0)
            new = replacement()
        default:
            if length > 0 { old = NSRange(location: length - 1, length: 1) } else { new = replacement() }
        }
        let units = (new as NSString).length
        return (StorageEdit(range: NSRange(location: old.location, length: units), delta: units - old.length), new)
    }

    /// The offsets at which a line of `text` starts.
    static func lineStarts(of text: NSString) -> [Int] {
        guard text.length > 0 else { return [] }
        var starts = [0]
        for index in 0..<text.length - 1 where text.character(at: index) == 10 { starts.append(index + 1) }
        return starts
    }

    /// Sorted, disjoint, non-empty ranges inside `bounds`, with a gap of zero between some of them when
    /// `touching` is true.
    mutating func ranges(in bounds: NSRange, touching: Bool) -> [NSRange] {
        var result: [NSRange] = []
        var position = bounds.location + int(0...3)
        while position < NSMaxRange(bounds) {
            let end = min(NSMaxRange(bounds), position + int(1...6))
            result.append(NSRange(location: position, length: end - position))
            position = end + (touching && chance(30) ? 0 : int(1...8))
        }
        return result
    }

    /// A non-empty range of a text of `length` units, or nil for an empty text.
    mutating func range(in length: Int) -> NSRange? {
        guard length > 0 else { return nil }
        let location = int(0...(length - 1))
        return NSRange(location: location, length: int(1...min(8, length - location)))
    }
}

// MARK: - A run: a text, a store of every shape, and the naive twin of each

struct OffsetStoreRun {
    var generator: OffsetStoreGenerator
    var text: NSString
    private var nextValue = 1_000
    /// The first and last offset every edit since the last splice touched, in the text as it is now.
    private var dirty: (start: Int, end: Int)?

    var table: OffsetTable<Int>
    var dict: [Int: Int]
    var clip: OffsetRanges<NSRange>
    var clipModel: [NSRange]
    var drop: OffsetRanges<NSRange>
    var dropModel: [NSRange]
    var anchored: OffsetRanges<NSRange>
    var anchoredModel: [NSRange]
    var merging: OffsetRanges<NSRange>
    var mergingModel: [NSRange]
    /// What the embed filter would have left of `drop`, which must equal what `splice` left.
    private var embedModel: [NSRange]
    /// Set when the run itself leaves the preconditions of ADR-0094 §D3: a list out of order, or a seam
    /// the splice would merge across more than the window. The generator is the test's to keep honest.
    private(set) var violation: String?

    init(seed: UInt64, text given: String? = nil, populated: Bool = true) {
        var generator = OffsetStoreGenerator(seed: seed)
        let text = given.map { $0 as NSString } ?? generator.text(maxLength: 300)
        let whole = NSRange(location: 0, length: text.length)
        var values: [Int: Int] = [:]
        var lists: [[NSRange]] = [[], [], [], []]
        if populated {
            for (index, start) in OffsetStoreGenerator.lineStarts(of: text).enumerated() { values[start] = index }
            lists = [
                generator.ranges(in: whole, touching: true), generator.ranges(in: whole, touching: true),
                generator.ranges(in: whole, touching: true), generator.ranges(in: whole, touching: false),
            ]
            if let last = lists[2].last, generator.chance(50), last.location < text.length {
                lists[2][lists[2].count - 1] = NSRange(location: last.location, length: text.length - last.location)
            }
        }
        self.generator = generator
        self.text = text
        dict = values
        table = OffsetTable(values)
        clipModel = lists[0]
        clip = OffsetRanges(sorted: lists[0])
        dropModel = lists[1]
        drop = OffsetRanges(sorted: lists[1])
        embedModel = lists[1]
        anchoredModel = lists[2]
        anchored = OffsetRanges(sorted: lists[2])
        mergingModel = lists[3]
        merging = OffsetRanges(sorted: lists[3])
    }

    var length: Int { text.length }

    /// One random operation: an edit, or the splice that follows the edits so far.
    mutating func step() {
        if dirty != nil, generator.chance(45) {
            splice()
        } else {
            let drawn = generator.edit(in: text)
            apply(drawn.edit, replacement: drawn.replacement)
        }
    }

    /// An edit of `range` into `replacement`, applied to every store and its twin.
    mutating func replace(_ range: NSRange, with replacement: String) {
        let units = (replacement as NSString).length
        apply(
            StorageEdit(range: NSRange(location: range.location, length: units), delta: units - range.length),
            replacement: replacement
        )
    }

    mutating func apply(_ edit: StorageEdit, replacement: String) {
        let oldLength = text.length
        let edited = text.replacingCharacters(in: edit.oldRange, with: replacement) as NSString
        table.apply(edit)
        dict = OffsetOracle.shift(dict, by: edit)
        clip.apply(edit, partial: .clip)
        clipModel = OffsetOracle.clip(clipModel, by: edit)
        drop.apply(edit, partial: .drop)
        dropModel = OffsetOracle.drop(dropModel, by: edit)
        embedModel = OffsetOracle.drop(embedModel, by: edit)
        anchored.apply(edit, anchoringTheEndOf: oldLength)
        anchoredModel = OffsetOracle.anchor(anchoredModel, by: edit, oldLength: oldLength, newLength: edited.length)
        merging.apply(edit, partial: .clip)
        mergingModel = OffsetOracle.clip(mergingModel, by: edit)
        text = edited
        let models = [("clip", clipModel), ("drop", dropModel), ("anchored", anchoredModel), ("merging", mergingModel)]
        for (name, list) in models
        where !zip(list, list.dropFirst()).allSatisfy({
            $0.location <= $1.location && NSMaxRange($0) <= NSMaxRange($1)
        }) {
            violation = violation ?? "\(name) model out of order after \(edit): \(describe(list))"
        }
        if let current = dirty {
            dirty = (
                min(edit.shifted(current.start), edit.range.location),
                max(edit.shifted(current.end), NSMaxRange(edit.range))
            )
        } else {
            dirty = (edit.range.location, NSMaxRange(edit.range))
        }
    }

    /// The ranged restyle's splice, over a dirty range that covers every edit since the last one
    /// (ADR-0094 §D3's precondition), with fresh entries drawn inside it.
    mutating func splice() {
        guard let pending = dirty else { return }
        let range = NSRange(location: pending.start, length: pending.end - pending.start)
        // The window version of `spliceMerging` equals `MarkdownStyler.spliced` only while the entries after the
        // dirty range are merged among themselves (ADR-0094 §D3): a shift leaves two ranges touching only at
        // an edit point, and the dirty range covers every edit since the last splice.
        let after = mergingModel.filter { $0.location >= NSMaxRange(range) }
        if !zip(after, after.dropFirst()).allSatisfy({ NSMaxRange($0) < $1.location }) {
            violation = violation ?? "merging model has touching entries after \(range): \(describe(mergingModel))"
        }
        var fresh: [Int: Int] = [:]
        for start in OffsetStoreGenerator.lineStarts(of: text) where NSLocationInRange(start, range) {
            if generator.chance(70) { fresh[start] = nextValue; nextValue += 1 }
        }
        table.replace(in: range, with: fresh)
        dict = OffsetOracle.replace(dict, in: range, with: fresh)

        let dropFragment = generator.ranges(in: range, touching: true)
        drop.splice(dropFragment, replacing: range)
        embedModel = OffsetOracle.embedSplice(embedModel, dirty: range, with: dropFragment)
        dropModel = OffsetOracle.splice(dropModel, dirty: range, with: dropFragment)

        let anchoredFragment = generator.ranges(in: range, touching: true)
        anchored.splice(anchoredFragment, replacing: range)
        anchoredModel = OffsetOracle.splice(anchoredModel, dirty: range, with: anchoredFragment)

        let mergedFragment = MarkdownStyler.merged(generator.ranges(in: range, touching: false))
        merging.spliceMerging(mergedFragment, replacing: range)
        mergingModel = OffsetOracle.spliceMerging(mergingModel, dirty: range, with: mergedFragment)
        dirty = nil
    }

    /// The first place a store and its twin part, or nil.
    func firstDisagreement() -> String? {
        if let violation { return "the run broke its own preconditions: \(violation)" }
        if !(table == dict) { return "table \(Array(table.keys)) against \(dict.keys.sorted())" }
        if Array(table.values) != table.keys.map({ dict[$0] ?? -1 }) { return "table values" }
        let pairs: [(String, [NSRange], [NSRange])] = [
            ("clip", Array(clip), clipModel), ("drop", Array(drop), dropModel),
            ("embed splice", Array(drop), embedModel),
            ("anchored", Array(anchored), anchoredModel), ("merging", Array(merging), mergingModel),
        ]
        for (name, actual, expected) in pairs where actual != expected {
            return "\(name): \(describe(actual)) against \(describe(expected))"
        }
        return nil
    }

    private func describe(_ ranges: [NSRange]) -> String {
        ranges.prefix(12).map { "(\($0.location),\($0.length))" }.joined()
            + (ranges.count > 12 ? "... \(ranges.count)" : "")
    }

    /// The first query on which a store parts from a scan of its twin, or nil.
    mutating func firstQueryDisagreement() -> String? {
        let reach = length + 2
        for _ in 0..<6 {
            let offset = generator.int(0...reach)
            let sorted = dict.keys.sorted()
            let before = sorted.last { $0 <= offset }
            if table.entry(atOrBefore: offset)?.key != before { return "entry(atOrBefore: \(offset))" }
            if let found = table.entry(atOrBefore: offset), found.value != dict[found.key] {
                return "entry value at \(offset)"
            }
            let window = NSRange(location: generator.int(0...reach), length: generator.int(0...12))
            let expectedKeys = sorted.filter { NSLocationInRange($0, window) }
            if table.entries(in: window).map(\.key) != expectedKeys { return "entries(in: \(window))" }
            if table.entries(in: window).map(\.value) != expectedKeys.map({ dict[$0] ?? -1 }) {
                return "entries(in:) values"
            }
            if let message = rangeQueries(clip, clipModel, offset: offset, window: window, name: "clip") {
                return message
            }
            if let message = rangeQueries(merging, mergingModel, offset: offset, window: window, name: "merging") {
                return message
            }
        }
        for key in dict.keys.sorted() {
            if table[key] != dict[key] || table[key + 1] != dict[key + 1] { return "subscript at \(key)" }
        }
        if table.count != dict.count || table.isEmpty != dict.isEmpty { return "count" }
        if Array(table.keys) != dict.keys.sorted() { return "keys" }
        return nil
    }

    private func rangeQueries(
        _ store: OffsetRanges<NSRange>, _ model: [NSRange], offset: Int, window: NSRange, name: String
    ) -> String? {
        if store.count(endingAtOrBefore: offset) != model.filter({ NSMaxRange($0) <= offset }).count {
            return "\(name).count(endingAtOrBefore: \(offset))"
        }
        let touching = model.indices.filter {
            model[$0].location <= NSMaxRange(window) && NSMaxRange(model[$0]) >= window.location
        }
        if Array(store.indices(touching: window)) != touching { return "\(name).indices(touching: \(window))" }
        if store.entries(startingIn: window) != model.filter({ NSLocationInRange($0.location, window) }) {
            return "\(name).entries(startingIn: \(window))"
        }
        guard window.length > 0 else { return nil }
        let hits = model.indices.filter { NSIntersectionRange(model[$0], window).length > 0 }
        if store.intersects(window) != !hits.isEmpty { return "\(name).intersects(\(window))" }
        let overlapping = model.indices.filter {
            model[$0].location < NSMaxRange(window) && NSMaxRange(model[$0]) > window.location
        }
        if Array(store.indices(intersecting: window)) != overlapping {
            return "\(name).indices(intersecting: \(window))"
        }
        return nil
    }
}
