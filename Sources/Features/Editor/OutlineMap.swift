import Foundation

// ADR-0096 §D6, plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 4 (PG-406).
//
// The note's outline as offsets that move with an edit, in the shape of ADR-0094's holders: one
// `OffsetRanges` of the lines that are a heading or an embed, shifted by `apply(_:)` and re-read over
// the dirty range by `splice(_:in:fences:)`, so a keystroke costs the line it touched and not the note.
// Foundation only: the map reads `NoteOutline.entry(inLine:)`, the one rule `entries(in:)` also applies.
//
// The coordinator drives it from the three places ADR-0091 §D6 already uses: `apply` with every other
// holder, `splice` over a `.lines` decision with the absorbed structure map's fences, `rebuild` on every
// full pass and under the kill switch. `OutlineMapTests` and `OutlineMapPropertyTests` hold it equal to
// `NoteOutline.entries(in:)`, `foldedOrdinals(ofOffsets:in:)` and `NoteFolding.foldableEntries(in:)`.

struct OutlineMap: Equatable, Sendable {
    /// One heading or embed line.
    struct Entry: RangedEntry, Sendable {
        /// The line, without its terminator.
        var range: NSRange
        var kind: NoteOutline.Entry.Kind
        var title: String
        /// The length of the line break that ends the line: 0 for the last line, 1 for LF, 2 for CRLF.
        var terminatorLength: Int

        var position: Int { range.location }

        func moved(by delta: Int) -> Entry {
            with(range: NSRange(location: range.location + delta, length: range.length))
        }

        func with(range: NSRange) -> Entry {
            Entry(range: range, kind: kind, title: title, terminatorLength: terminatorLength)
        }
    }

    /// An entry as the consumers read it: `NoteOutline.Entry` with its range in UTF-16 units and its
    /// level resolved (a heading's own, an embed's one below the heading above it, at most 6).
    struct Item: Equatable, Sendable {
        var range: NSRange
        var kind: NoteOutline.Entry.Kind
        var title: String
        var level: Int
    }

    private(set) var entries = OffsetRanges<Entry>()

    init() {}

    init(text: String) {
        rebuild(text: text)
    }

    /// Every entry, with its level: a heading's own, an embed's one below the heading above it.
    var items: [Item] {
        var enclosing = 1
        return entries.map { entry in
            let level: Int
            switch entry.kind {
            case .heading(let own):
                enclosing = own
                level = own
            case .embed:
                level = Swift.min(enclosing + 1, 6)
            }
            return Item(range: entry.range, kind: entry.kind, title: entry.title, level: level)
        }
    }

    /// Reads the whole text again, through the parse itself.
    mutating func rebuild(text: String) {
        let units = text as NSString
        let fresh = NoteOutline.entries(in: text).map { entry -> Entry in
            let range = NSRange(entry.range, in: text)
            return Entry(
                range: range, kind: entry.kind, title: entry.title,
                terminatorLength: Self.terminatorLength(after: NSMaxRange(range), in: units)
            )
        }
        entries = OffsetRanges(sorted: fresh)
    }

    /// Moves the entries past a storage edit; an entry the edit cuts is clipped until the next splice.
    mutating func apply(_ edit: StorageEdit) {
        entries.apply(edit, partial: .clip)
    }

    /// Reads the lines of `dirty` again, skipping the lines a fence covers, and replaces the entries
    /// that lay there. `dirty` is widened to whole lines as the outline counts them, on U+000A.
    mutating func splice(_ text: NSString, in dirty: NSRange, fences: OffsetRanges<StructureMap.Fence>) {
        let window = Self.lineWindow(of: dirty, in: text)
        var fragment: [Entry] = []
        var lineStart = window.location
        let end = NSMaxRange(window)
        while lineStart < end {
            let (content, terminator) = Self.line(at: lineStart, in: text)
            defer { lineStart = NSMaxRange(content) + terminator }
            guard content.length > 0, !fences.intersects(content) else { continue }
            let trimmed = text.substring(with: content).trimmingCharacters(in: .whitespaces)
            guard let entry = NoteOutline.entry(inLine: trimmed) else { continue }
            fragment.append(Entry(range: content, kind: entry.kind, title: entry.title, terminatorLength: terminator))
        }
        entries.splice(fragment, replacing: window)
    }

    /// The ordinal of the last entry that starts at or before `offset`.
    func lastEntry(atOrBefore offset: Int) -> Int? {
        let after = firstEntry { $0.range.location > offset }
        return after == 0 ? nil : after - 1
    }

    /// `foldedOrdinals(ofOffsets:in:)` over the map: the ordinals of the entries that start at
    /// `offsets`; an offset that names no entry is dropped.
    func ordinals(ofOffsets offsets: Set<Int>) -> Set<Int> {
        var ordinals: Set<Int> = []
        for offset in offsets {
            let index = firstEntry { $0.range.location >= offset }
            if index < entries.count, entries[index].range.location == offset { ordinals.insert(index) }
        }
        return ordinals
    }

    /// The level of the entry at `ordinal`, as `items` resolves it: a heading's own, or one below the
    /// nearest heading above an embed (level 2 when none precedes it), at most 6; 1 for an ordinal
    /// outside the map.
    func level(ofEntry ordinal: Int) -> Int {
        guard entries.indices.contains(ordinal) else { return 1 }
        if case .heading(let level) = entries[ordinal].kind { return level }
        for index in stride(from: ordinal - 1, through: 0, by: -1) {
            if case .heading(let level) = entries[index].kind { return Swift.min(level + 1, 6) }
        }
        return 2
    }

    /// Whether the entry at `ordinal` is a heading with at least one line under it (ADR-0096 §D7's
    /// local rule): followed by another entry, unless that entry is a heading of the same or a higher
    /// level on the very next line; the last entry, when its line ends with a terminator.
    func isFoldable(_ ordinal: Int) -> Bool {
        guard entries.indices.contains(ordinal), case .heading(let level) = entries[ordinal].kind else { return false }
        let entry = entries[ordinal]
        guard ordinal + 1 < entries.count else { return entry.terminatorLength > 0 }
        let next = entries[ordinal + 1]
        if case .heading(let nextLevel) = next.kind, nextLevel <= level,
           next.range.location == NSMaxRange(entry.range) + entry.terminatorLength {
            return false
        }
        return true
    }

    // MARK: Lines and searches

    /// The first index whose entry satisfies `isPast`, which must be false for a prefix and true for
    /// the rest: one binary search.
    private func firstEntry(where isPast: (Entry) -> Bool) -> Int {
        var low = 0
        var high = entries.count
        while low < high {
            let middle = (low + high) / 2
            if isPast(entries[middle]) { high = middle } else { low = middle + 1 }
        }
        return low
    }

    private static let lineFeed = unichar(0x0A)
    private static let carriageReturn = unichar(0x0D)

    /// `dirty` widened to whole lines: back to the start of its first line, forward past the
    /// terminator of its last one. A range ending right after a line feed already ends a line. Not
    /// `private`: `OutlineStore` finds the ordinals a splice wrote from the same window.
    static func lineWindow(of dirty: NSRange, in text: NSString) -> NSRange {
        var start = Swift.min(dirty.location, text.length)
        while start > 0, text.character(at: start - 1) != lineFeed { start -= 1 }
        var end = Swift.min(NSMaxRange(dirty), text.length)
        if dirty.length == 0 || end == 0 || text.character(at: end - 1) != lineFeed {
            while end < text.length, text.character(at: end) != lineFeed { end += 1 }
            if end < text.length { end += 1 }
        }
        return NSRange(location: start, length: end - start)
    }

    /// The line starting at `start`: its content, and its terminator's length (0 at the end of the
    /// text, 1 for LF, 2 for CRLF, which is one `Character` in `NoteOutline`'s reading).
    private static func line(at start: Int, in text: NSString) -> (content: NSRange, terminator: Int) {
        var end = start
        while end < text.length, text.character(at: end) != lineFeed { end += 1 }
        guard end < text.length else { return (NSRange(location: start, length: end - start), 0) }
        if end > start, text.character(at: end - 1) == carriageReturn {
            return (NSRange(location: start, length: end - 1 - start), 2)
        }
        return (NSRange(location: start, length: end - start), 1)
    }

    /// The length of the line break at `offset`, where an entry's line ends.
    private static func terminatorLength(after offset: Int, in text: NSString) -> Int {
        guard offset < text.length else { return 0 }
        return text.character(at: offset) == carriageReturn ? 2 : 1
    }
}
