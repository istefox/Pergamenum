import Foundation

/// The offset-keyed derived state a restyle decision needs, kept for the whole note
/// (ADR-0091 §D2): one signature per styler line, the fence regions, the table runs, the closed
/// view-block runs and the frontmatter zone.
///
/// Built by `init(text:)` at every full restyle; `apply` shifts it at each edit and recomputes the
/// signatures of the lines the edit touched; `splice` replaces the runs inside a restyled range with
/// the ones the fragment produced. After an edit and its restyle the map equals `StructureMap(text:)`
/// of the new text, which the property test proves.
///
/// Foundation only (ADR-0091 §D1).
struct StructureMap: Equatable, Sendable {
    struct Line: Equatable, Sendable {
        /// The UTF-16 offset of the line's first character.
        var start: Int
        var signature: MarkdownLineSignature
    }

    struct Fence: Equatable, Sendable {
        /// The whole block, opening and closing lines included.
        var range: NSRange
        var language: String?
        var isClosed: Bool
    }

    private(set) var lines: [Line] = []
    private(set) var fences: [Fence] = []
    private(set) var tableRuns: [NSRange] = []
    private(set) var viewBlockRuns: [NSRange] = []
    private(set) var frontmatterZoneEnd: Int?
    /// The fences two other readers see where they part from `fences`: the block tokenizer's own
    /// walk, which starts after the frontmatter, and `WikilinkParser.codeRanges`, which also takes
    /// `~~~` and closes only on a bare delimiter. A restyled range must not cut one of these either,
    /// or the fragment reads its lines in another state than the note does.
    private(set) var codeBlocks: [NSRange] = []
    /// The UTF-16 length of the text the map describes.
    private(set) var length = 0

    init(text: String) {
        let nsText = text as NSString
        length = nsText.length
        lines = Self.lines(of: text, base: 0)
        frontmatterZoneEnd = Self.frontmatterZoneEnd(lines: lines, text: nsText) { text }

        let regions = CodeFence.regions(in: text)
        fences = regions.map { region in
            Fence(
                range: NSRange(region.range, in: text),
                language: region.language,
                // A fence `CodeFence` synthesised for a missing closing line ends its body where it
                // ends itself, which a closed one never does (`MarkdownStyler.viewBlockRuns`).
                isClosed: region.body.upperBound != region.range.upperBound
            )
        }

        let runs = MarkdownStyler.structuralRuns(in: text, regions: regions)
        tableRuns = runs.tables.map { NSRange($0, in: text) }
        viewBlockRuns = runs.viewBlocks.map { NSRange($0, in: text) }

        let fenceRanges = Set(fences.map(\.range))
        let others = (runs.tokenFences + WikilinkParser.fencedCodeRanges(in: text[runs.bodyStart...]))
            .map { NSRange($0, in: text) }
            .filter { !fenceRanges.contains($0) }
        codeBlocks = Array(Set(others)).sorted { ($0.location, $0.length) < ($1.location, $1.length) }
    }

    // MARK: Edits

    /// What an edit did to the lines, for `RestyleScope`'s decision.
    struct Touched {
        /// The index of the first line the edit touched, the same before and after it.
        var first: Int
        /// The signatures of the lines it touched, as they were.
        var oldSignatures: [MarkdownLineSignature]
        /// How many lines now stand where those were.
        var newCount: Int
        var oldFrontmatterZoneEnd: Int?
    }

    /// Shifts the map by `edit` and recomputes the signatures of the lines it touched, from `text`
    /// (the text after the edit).
    mutating func apply(_ edit: StorageEdit, in text: NSString) {
        _ = applying(edit, in: text)
    }

    /// `apply`, answering which lines the edit touched.
    mutating func applying(_ edit: StorageEdit, in text: NSString) -> Touched {
        let oldZone = frontmatterZoneEnd
        let oldLength = length
        guard !lines.isEmpty else {
            self = StructureMap(text: text as String)
            return Touched(first: 0, oldSignatures: [], newCount: lines.count, oldFrontmatterZoneEnd: oldZone)
        }

        let old = edit.oldRange
        let first = lineIndex(containing: old.location)
        let last = lineIndex(containing: NSMaxRange(old))
        let oldSignatures = lines[first...last].map(\.signature)
        let start = lines[first].start

        // The new lines run from the first touched line's start to the end of the line holding the
        // edit's new end, the "\n" that ends it included so a "\r\n" is read as one terminator.
        let newLength = text.length
        var end = min(NSMaxRange(edit.range), newLength)
        while end < newLength, text.character(at: end) != 10 { end += 1 }
        let endsWithBreak = end < newLength
        let region = text.substring(with: NSRange(location: start, length: (endsWithBreak ? end + 1 : end) - start))
        var fresh = Self.lines(of: region, base: start)
        if endsWithBreak { fresh.removeLast() }

        for index in (last + 1)..<lines.count { lines[index].start += edit.delta }
        lines.replaceSubrange(first...last, with: fresh)
        length = newLength

        fences = fences.compactMap { fence in
            Self.shifted(fence.range, by: edit, oldLength: oldLength, newLength: newLength).map {
                Fence(range: $0, language: fence.language, isClosed: fence.isClosed)
            }
        }
        codeBlocks = codeBlocks.compactMap { Self.shifted($0, by: edit, oldLength: oldLength, newLength: newLength) }
        tableRuns = tableRuns.compactMap { edit.shifted($0) }
        viewBlockRuns = viewBlockRuns.compactMap { edit.shifted($0) }

        // Only the first line opens a frontmatter and only a line up to its closing one ends it, so
        // an edit below the zone leaves it where it is.
        if start <= (oldZone ?? 0) {
            frontmatterZoneEnd = Self.frontmatterZoneEnd(lines: lines, text: text) { text as String }
        }

        return Touched(
            first: first, oldSignatures: oldSignatures, newCount: fresh.count, oldFrontmatterZoneEnd: oldZone
        )
    }

    /// Replaces the runs inside `dirty` (in the note's coordinates) with the runs of `fragment`, a
    /// map of the dirty range's own text, whose offsets start `offset` units into the note.
    mutating func splice(_ fragment: StructureMap, at offset: Int, replacing dirty: NSRange) {
        let end = NSMaxRange(dirty)
        let low = lines.firstIndex { $0.start >= dirty.location } ?? lines.count
        let high = lines[low...].firstIndex { $0.start >= end } ?? lines.count
        let fresh = fragment.lines
            .filter { $0.start < dirty.length }
            .map { Line(start: $0.start + offset, signature: $0.signature) }
        lines.replaceSubrange(low..<high, with: fresh)

        func moved(_ range: NSRange) -> NSRange { NSRange(location: range.location + offset, length: range.length) }
        fences = Self.spliced(fences, \.range, dirty: dirty, with: fragment.fences.map {
            Fence(range: moved($0.range), language: $0.language, isClosed: $0.isClosed)
        })
        tableRuns = Self.spliced(tableRuns, \.self, dirty: dirty, with: fragment.tableRuns.map(moved))
        viewBlockRuns = Self.spliced(viewBlockRuns, \.self, dirty: dirty, with: fragment.viewBlockRuns.map(moved))
        codeBlocks = Self.spliced(codeBlocks, \.self, dirty: dirty, with: fragment.codeBlocks.map(moved))
    }

    // MARK: Reading

    /// The index of the line holding `offset`: the last one starting at or before it.
    func lineIndex(containing offset: Int) -> Int {
        var low = 0
        var high = lines.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lines[middle].start <= offset { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// Where line `index` ends, its terminator included.
    func lineEnd(_ index: Int) -> Int {
        index + 1 < lines.count ? lines[index + 1].start : length
    }

    // MARK: Building

    /// The styler lines of `text`, `base` added to every start: a line ends at "\n" or "\r\n", found
    /// by a scan of the UTF-16 for U+000A (ADR-0091 C3), and its signature reads it without them.
    private static func lines(of text: String, base: Int) -> [Line] {
        var result: [Line] = []
        let units = text.utf16
        var lineStart = units.startIndex
        var lineStartOffset = base
        var offset = base
        var previous: UInt16 = 0
        var index = units.startIndex
        while index != units.endIndex {
            let unit = units[index]
            let next = units.index(after: index)
            offset += 1
            if unit == 10 {
                let contentEnd = previous == 13 && index > lineStart ? units.index(before: index) : index
                result.append(Line(start: lineStartOffset, signature: .of(text[lineStart..<contentEnd])))
                lineStart = next
                lineStartOffset = offset
            }
            previous = unit
            index = next
        }
        result.append(Line(start: lineStartOffset, signature: .of(text[lineStart..<units.endIndex])))
        return result
    }

    /// From 0 to the later of the two frontmatter parsers' closing lines (ADR-0091 §D3, C3 item 1):
    /// `NoteFrontmatter.range`, which the styler reads, and `FrontmatterSource`'s delimiter test,
    /// which `NoteDocument.parse` and so `Transclusion` read. The whole text when either opens and
    /// finds no closing line; nil when neither opens.
    private static func frontmatterZoneEnd(lines: [Line], text: NSString, string: () -> String) -> Int? {
        guard !lines.isEmpty else { return nil }
        let length = text.length
        /// Line `index` as `NoteDocument` splits it: up to its "\n", a "\r" before it kept.
        func raw(_ index: Int) -> String {
            let end = index + 1 < lines.count ? lines[index + 1].start - 1 : length
            return text.substring(with: NSRange(location: lines[index].start, length: end - lines[index].start))
        }
        func contentEnd(_ index: Int) -> Int {
            guard index + 1 < lines.count else { return length }
            let end = lines[index + 1].start - 1
            return end > lines[index].start && text.character(at: end - 1) == 13 ? end - 1 : end
        }

        let first = raw(0)
        var zoneEnd: Int?
        // `NoteFrontmatter.range`'s own opening test, asked of the line that holds the text's start.
        if first.hasPrefix("---") {
            let whole = string()
            guard let range = NoteFrontmatter.range(in: whole) else { return length }
            let closingStart = whole.utf16.distance(from: whole.startIndex, to: range.upperBound) - 3
            zoneEnd = contentEnd(lineIndex(of: closingStart, in: lines))
        }
        if FrontmatterSource.isDelimiter(FrontmatterSource.interpreted(first, isFirst: true)) {
            guard let closing = lines.indices.dropFirst().first(where: {
                FrontmatterSource.isDelimiter(FrontmatterSource.interpreted(raw($0)))
            }) else { return length }
            zoneEnd = max(zoneEnd ?? 0, contentEnd(closing))
        }
        return zoneEnd
    }

    private static func lineIndex(of offset: Int, in lines: [Line]) -> Int {
        var low = 0
        var high = lines.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lines[middle].start <= offset { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// `StorageEdit.shifted`, except that a fence that reached the end of the old text still does:
    /// an unclosed fence runs to the end of the note, whatever is typed after its last character.
    private static func shifted(_ range: NSRange, by edit: StorageEdit, oldLength: Int, newLength: Int) -> NSRange? {
        if NSMaxRange(range) == oldLength, edit.oldRange.location >= range.location {
            return NSRange(location: range.location, length: newLength - range.location)
        }
        return edit.shifted(range)
    }

    /// `runs` without the ones that intersect `dirty`, and `fragment`'s in their place.
    private static func spliced<Run>(
        _ runs: [Run], _ key: KeyPath<Run, NSRange>, dirty: NSRange, with fragment: [Run]
    ) -> [Run] {
        let end = NSMaxRange(dirty)
        let before = runs.filter { NSMaxRange($0[keyPath: key]) <= dirty.location }
        let after = runs.filter { $0[keyPath: key].location >= end && NSMaxRange($0[keyPath: key]) > dirty.location }
        return before + fragment + after
    }
}
