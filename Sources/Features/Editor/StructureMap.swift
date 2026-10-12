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
/// Every store that grows with the note sits on a step (ADR-0094 §D6): an edit replaces the lines it
/// touched and moves the rest by its delta in one `replace`, and the readers answer by search. The three
/// mark sets keep, at line starts, what the parity and `pendingOpener` used to walk the lines for.
///
/// Foundation only (ADR-0091 §D1).
struct StructureMap: Equatable, Sendable {
    struct Line: Equatable, Sendable {
        /// The UTF-16 offset of the line's first character.
        var start: Int
        var signature: MarkdownLineSignature
        /// What the windowed list renumbering needs of the line, read off its own range, terminator
        /// included (ADR-0093 §D8). Computed wherever the signature is; the default is for a line
        /// nothing has read yet.
        var listFacts: ListContinuation.LineFacts = .init(fenceDelimiters: 0, endsEveryRun: false)
    }

    struct Fence: Equatable, Sendable {
        /// The whole block, opening and closing lines included.
        var range: NSRange
        var language: String?
        var isClosed: Bool
    }

    /// A line start, the element of the three mark sets.
    struct Mark: OffsetEntry, Sendable {
        var position: Int

        func moved(by delta: Int) -> Mark { Mark(position: position + delta) }
    }

    private(set) var lines = StepBuffer<Line>()
    private(set) var fences = OffsetRanges<Fence>()
    private(set) var tableRuns = OffsetRanges<NSRange>()
    private(set) var viewBlockRuns = OffsetRanges<NSRange>()
    /// The starts of the lines whose `listFacts.fenceDelimiters` is odd: the fence parity before a line
    /// is the rank of its start here, modulo 2 (ADR-0094 §D6).
    private(set) var oddFenceLines = StepBuffer<Mark>()
    /// The starts of the lines whose signature holds a bracket token.
    private(set) var bracketLines = StepBuffer<Mark>()
    /// The starts of the lines whose bracket tokens include a `]]`.
    private(set) var closingLines = StepBuffer<Mark>()
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
        let built = Self.lines(of: text, base: 0)
        lines = StepBuffer(sorted: built)
        oddFenceLines = StepBuffer(sorted: Self.marks(of: built, \.isOddFenceLine))
        bracketLines = StepBuffer(sorted: Self.marks(of: built, \.holdsBracket))
        closingLines = StepBuffer(sorted: Self.marks(of: built, \.holdsClosingBracket))
        frontmatterZoneEnd = Self.frontmatterZoneEnd(lines: lines, text: nsText) { text }

        let regions = CodeFence.regions(in: text)
        let fenceList = regions.map { region in
            Fence(
                range: NSRange(region.range, in: text),
                language: region.language,
                // A fence `CodeFence` synthesised for a missing closing line ends its body where it
                // ends itself, which a closed one never does (`MarkdownStyler.viewBlockRuns`).
                isClosed: region.body.upperBound != region.range.upperBound
            )
        }
        fences = OffsetRanges(sorted: fenceList)

        let runs = MarkdownStyler.structuralRuns(in: text, regions: regions)
        tableRuns = OffsetRanges(sorted: runs.tables.map { NSRange($0, in: text) })
        viewBlockRuns = OffsetRanges(sorted: runs.viewBlocks.map { NSRange($0, in: text) })

        let fenceRanges = Set(fenceList.map(\.range))
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
        // The fence rule below computes the new end as `oldLength + delta` (ADR-0094 §D3).
        assert(oldLength + edit.delta == newLength, "the map's length is not that of the text the edit was made to")
        var end = min(NSMaxRange(edit.range), newLength)
        while end < newLength, text.character(at: end) != 10 { end += 1 }
        let endsWithBreak = end < newLength
        let region = text.substring(with: NSRange(location: start, length: (endsWithBreak ? end + 1 : end) - start))
        var fresh = Self.lines(of: region, base: start)
        if endsWithBreak { fresh.removeLast() }

        // The touched lines' span in the text as it was, read before anything moves: the mark sets
        // replace the marks inside it.
        let windowEnd = last + 1 < lines.count ? lines[last + 1].start : Int.max
        lines.replace(first..<last + 1, with: fresh, movingTheRestBy: edit.delta, as: .shift)
        replaceMarks(from: start, to: windowEnd, with: fresh, movingTheRestBy: edit.delta, as: .shift)
        length = newLength

        fences.apply(edit, anchoringTheEndOf: oldLength)
        codeBlocks = codeBlocks.compactMap { edit.shifted($0, anchoringTheEndOf: oldLength) }
        tableRuns.apply(edit, partial: .drop)
        viewBlockRuns.apply(edit, partial: .drop)

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
        let low = lines.lowerBound(dirty.location)
        let high = max(low, lines.lowerBound(end))
        let fresh = fragment.lines
            .filter { $0.start < dirty.length }
            .map { Line(start: $0.start + offset, signature: $0.signature, listFacts: $0.listFacts) }
        lines.replace(low..<high, with: fresh, movingTheRestBy: 0, as: .splice)
        replaceMarks(from: dirty.location, to: end, with: fresh, movingTheRestBy: 0, as: .splice)

        fences.splice(fragment.fences.map { $0.moved(by: offset) }, replacing: dirty)
        tableRuns.splice(fragment.tableRuns.map { $0.moved(by: offset) }, replacing: dirty)
        viewBlockRuns.splice(fragment.viewBlockRuns.map { $0.moved(by: offset) }, replacing: dirty)
        codeBlocks = Self.spliced(codeBlocks, dirty: dirty, with: fragment.codeBlocks.map { $0.moved(by: offset) })
    }

    /// Replaces, in each mark set, the marks at positions `from ..< to` (in the coordinates the sets are
    /// in now) with the marks of `fresh`, and moves every mark after them by `delta`.
    private mutating func replaceMarks(
        from start: Int, to end: Int, with fresh: [Line], movingTheRestBy delta: Int, as operation: StepTally.Operation
    ) {
        func replace(_ marks: inout StepBuffer<Mark>, _ holds: KeyPath<Line, Bool>) {
            let low = marks.lowerBound(start)
            let high = max(low, marks.lowerBound(end))
            marks.replace(low..<high, with: Self.marks(of: fresh, holds), movingTheRestBy: delta, as: operation)
        }
        replace(&oddFenceLines, \.isOddFenceLine)
        replace(&bracketLines, \.holdsBracket)
        replace(&closingLines, \.holdsClosingBracket)
    }

    // MARK: Reading

    /// The index of the line holding `offset`: the last one starting at or before it.
    func lineIndex(containing offset: Int) -> Int {
        max(0, lines.partition { $0.start > offset }.index - 1)
    }

    /// Whether an odd number of fence delimiters lies above line `index` (ADR-0093 §D8): the rank of the
    /// line's start among the odd-delimiter lines, modulo 2 (ADR-0094 §D6). A sum modulo 2 is the count
    /// of its odd terms modulo 2.
    func fenceParity(before index: Int) -> Bool {
        let bound = index < lines.count ? lines[index].start : Int.max
        return oddFenceLines.lowerBound(bound) % 2 == 1
    }

    /// The index of the nearest line before line `index` whose signature holds a bracket token, or nil.
    /// `index` may be `lines.count`, which reads as a position past every line.
    func nearestBracketLine(before index: Int) -> Int? {
        let bound = index < lines.count ? lines[index].start : Int.max
        let mark = bracketLines.lowerBound(bound) - 1
        guard mark >= 0 else { return nil }
        return lines.lowerBound(bracketLines[mark].position)
    }

    /// Whether a line after line `index` holds a `]]`. `index` must be a valid line index, unlike
    /// `nearestBracketLine(before:)`: its one caller passes a line that reader returned.
    func hasClosingBracket(after index: Int) -> Bool {
        let start = lines[index].start
        return closingLines.partition { $0.position > start }.index < closingLines.count
    }

    /// Where line `index` ends, its terminator included.
    func lineEnd(_ index: Int) -> Int {
        index + 1 < lines.count ? lines[index + 1].start : length
    }

    // MARK: Building

    /// The styler lines of `text`, `base` added to every start: a line ends at "\n" or "\r\n", found
    /// by a scan of the UTF-16 for U+000A (ADR-0091 C3), and its signature reads it without them. Its
    /// list facts read it with them (ADR-0093 §D8).
    private static func lines(of text: String, base: Int) -> [Line] {
        var result: [Line] = []
        let nsText = text as NSString
        func facts(from start: Int, to end: Int) -> ListContinuation.LineFacts {
            ListContinuation.facts(ofLine: NSRange(location: start - base, length: end - start), in: nsText)
        }
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
                result.append(Line(
                    start: lineStartOffset, signature: .of(text[lineStart..<contentEnd]),
                    listFacts: facts(from: lineStartOffset, to: offset)
                ))
                lineStart = next
                lineStartOffset = offset
            }
            previous = unit
            index = next
        }
        result.append(Line(
            start: lineStartOffset, signature: .of(text[lineStart..<units.endIndex]),
            listFacts: facts(from: lineStartOffset, to: offset)
        ))
        return result
    }

    /// From 0 to the later of the two frontmatter parsers' closing lines (ADR-0091 §D3, C3 item 1):
    /// `NoteFrontmatter.range`, which the styler reads, and `FrontmatterSource`'s delimiter test,
    /// which `NoteDocument.parse` and so `Transclusion` read. The whole text when either opens and
    /// finds no closing line; nil when neither opens.
    private static func frontmatterZoneEnd(lines: StepBuffer<Line>, text: NSString, string: () -> String) -> Int? {
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
            zoneEnd = contentEnd(max(0, lines.partition { $0.start > closingStart }.index - 1))
        }
        if FrontmatterSource.isDelimiter(FrontmatterSource.interpreted(first, isFirst: true)) {
            guard let closing = lines.indices.dropFirst().first(where: {
                FrontmatterSource.isDelimiter(FrontmatterSource.interpreted(raw($0)))
            }) else { return length }
            zoneEnd = max(zoneEnd ?? 0, contentEnd(closing))
        }
        return zoneEnd
    }

    /// The marks of `lines` for which `holds` is true, at their starts.
    private static func marks(of lines: [Line], _ holds: KeyPath<Line, Bool>) -> [Mark] {
        lines.filter { $0[keyPath: holds] }.map { Mark(position: $0.start) }
    }

    /// `codeBlocks` without the ones that intersect `dirty`, and `fragment`'s in their place. The run
    /// lists on a step take `OffsetRanges.splice`, the same partition; `codeBlocks` can overlap, so it
    /// stays an array (ADR-0094 §D6).
    private static func spliced(_ runs: [NSRange], dirty: NSRange, with fragment: [NSRange]) -> [NSRange] {
        let end = NSMaxRange(dirty)
        let before = runs.filter { NSMaxRange($0) <= dirty.location }
        let after = runs.filter { $0.location >= end && NSMaxRange($0) > dirty.location }
        return before + fragment + after
    }
}

// MARK: - The step's entries (ADR-0094 §D2)

extension StructureMap.Line: OffsetEntry {
    var position: Int { start }

    func moved(by delta: Int) -> StructureMap.Line {
        var line = self
        line.start += delta
        return line
    }

    /// What the three mark sets record of a line.
    fileprivate var isOddFenceLine: Bool { listFacts.fenceDelimiters % 2 == 1 }
    fileprivate var holdsBracket: Bool { !signature.brackets.isEmpty }
    fileprivate var holdsClosingBracket: Bool { signature.brackets.contains(.close) }
}

extension StructureMap.Fence: RangedEntry {
    var position: Int { range.location }

    func moved(by delta: Int) -> StructureMap.Fence {
        with(range: NSRange(location: range.location + delta, length: range.length))
    }

    func with(range: NSRange) -> StructureMap.Fence {
        StructureMap.Fence(range: range, language: language, isClosed: isClosed)
    }
}

// MARK: - Tallies (ADR-0094 §D5)

extension StructureMap {
    /// The step tallies of the map's stores, by name: `map.lines`, `map.fences`, `map.tableRuns`,
    /// `map.viewBlockRuns`, `map.oddFenceLines`, `map.bracketLines` and `map.closingLines`.
    var tallies: [String: StepTally] {
        [
            "map.lines": lines.tally, "map.fences": fences.tally, "map.tableRuns": tableRuns.tally,
            "map.viewBlockRuns": viewBlockRuns.tally, "map.oddFenceLines": oddFenceLines.tally,
            "map.bracketLines": bracketLines.tally, "map.closingLines": closingLines.tally,
        ]
    }

    mutating func resetTallies() {
        lines.resetTally()
        fences.resetTally()
        tableRuns.resetTally()
        viewBlockRuns.resetTally()
        oddFenceLines.resetTally()
        bracketLines.resetTally()
        closingLines.resetTally()
    }
}
