import Foundation

/// Decides, per edit, between restyling the lines it touched and restyling the note
/// (ADR-0091 §D2, §D3).
///
/// `record` takes each character edit as the text storage reports it: it reads the touched lines'
/// signatures from the map, applies the edit to the map, decides by §D3's table, and folds the
/// decision into the one still pending. `take` hands the pending decision over and clears it. The
/// owner rebuilds the scope after every full restyle, and hands the fragment's own map back with
/// `absorb` after a ranged one.
///
/// Foundation only (ADR-0091 §D1).
struct RestyleScope: Sendable {
    private(set) var map: StructureMap
    private var pending: Decision?
    /// True once a wholesale replace left the map describing a text that is gone: nothing is read
    /// from it until the full restyle that decision asks for rebuilds the scope.
    private var isStale = false

    init(text: String) {
        map = StructureMap(text: text)
    }

    enum Decision: Equatable, Sendable {
        case full(Reason)
        /// A range in the text as it now is, aligned outward to styler lines and widened. It ends
        /// after the last line's terminator, or at the end of the text.
        case lines(NSRange)
    }

    enum Reason: Equatable, Sendable {
        case noBaseline, wholesale, frontmatter, fenceLine, wikilinkTokens, wikilinkPending
        /// A run of table-capable lines the range has to cover holds a fence mark: the block
        /// tokenizer reads such a line as a row or as a fence depending on the table above it.
        case tableFence
    }

    /// Takes one edit, `text` being the text after it.
    mutating func record(_ edit: StorageEdit, in text: NSString) {
        let old = edit.oldRange
        if isStale || (old.location == 0 && old.length == map.length) {
            pending = .full(.wholesale)
            isStale = true
            return
        }

        let touched = map.applying(edit, in: text)
        if case .full? = pending { return }

        let decision = decide(touched, in: text)
        if case .lines(let range) = decision, case .lines(let previous)? = pending {
            pending = .lines(aligned(Self.hull(Self.mapped(previous, through: edit), range)))
        } else {
            pending = decision
        }
    }

    /// The decision for every edit recorded since the last call, which it clears; nil when none was
    /// recorded.
    mutating func take() -> Decision? {
        defer { pending = nil }
        return pending
    }

    /// Whether the map's fences are the text's own right now. A recorded edit only shifts them, so
    /// they stop being exact once an edit is waiting on a full restyle, and a wholesale replace
    /// leaves nothing exact at all; a `.lines` edit never moves a fence line, so they stay exact.
    var fencesAreCurrent: Bool {
        guard !isStale else { return false }
        if case .full? = pending { return false }
        return true
    }

    /// The list stack in force at `offset`, folded from the map's roles.
    func listSeed(at offset: Int) -> [Int] {
        stack(before: map.lineIndex(containing: offset))
    }

    /// Where a windowed list renumbering may start reading for an edit at `offset`, or nil while the map
    /// describes a text that is gone (ADR-0093 §D8). From the line before the one holding `offset`
    /// (the scoped form widens by that line), back to the nearest line whose previous line ends every
    /// run, or the first line; no ordered run crosses that start. The fence parity there is the sum of
    /// the delimiters above it, an array walk over integers that reads no text.
    func renumberWindow(before offset: Int) -> ListContinuation.Window? {
        guard !isStale, !map.lines.isEmpty else { return nil }
        let lines = map.lines
        var start = max(0, map.lineIndex(containing: offset) - 1)
        while start > 0, !lines[start - 1].listFacts.endsEveryRun { start -= 1 }
        let delimiters = lines[..<start].reduce(0) { $0 + $1.listFacts.fenceDelimiters }
        return ListContinuation.Window(start: lines[start].start, fenceOpen: delimiters % 2 == 1)
    }

    /// Hands the fragment's own map back after a restyle (`StructureMap.splice`).
    mutating func absorb(_ fragment: StructureMap, at offset: Int, replacing dirty: NSRange) {
        map.splice(fragment, at: offset, replacing: dirty)
    }

    // MARK: The decision (ADR-0091 §D3)

    private func decide(_ touched: StructureMap.Touched, in text: NSString) -> Decision {
        let lines = map.lines
        let first = touched.first
        let last = first + touched.newCount - 1
        let oldSignatures = touched.oldSignatures
        let newSignatures = lines[first...last].map(\.signature)

        if touchesFrontmatter(touched, in: text) { return .full(.frontmatter) }

        // Fence lines, in the old text or the new.
        if oldSignatures.contains(where: \.fenceMark) || newSignatures.contains(where: \.fenceMark) {
            return .full(.fenceLine)
        }

        var low = first
        var high = last

        // Tables: every run of table-capable lines the edit touches or adjoins.
        let touchesTable = oldSignatures.contains(where: \.tableCapable)
            || newSignatures.contains(where: \.tableCapable)
            || (low > 0 && lines[low - 1].signature.tableCapable)
            || (high + 1 < lines.count && lines[high + 1].signature.tableCapable)
        if touchesTable, !extendOverTableRuns(&low, &high, onlyWhereCut: false) { return .full(.tableFence) }

        high = max(high, listWalkEnd(first: first, last: last, old: oldSignatures, new: newSignatures))
        if !widenOverRegions(&low, &high) { return .full(.tableFence) }
        if readsFrontmatter(from: low, in: text) { return .full(.frontmatter) }

        // Wikilinks: a change in the tokens, or a link crossing either end of the range.
        if oldSignatures.flatMap(\.brackets) != newSignatures.flatMap(\.brackets) { return .full(.wikilinkTokens) }
        if pendingOpener(before: low) || pendingOpener(before: high + 1) { return .full(.wikilinkPending) }

        let rangeStart = lines[low].start
        return .lines(NSRange(location: rangeStart, length: map.lineEnd(high) - rangeStart))
    }

    /// Frontmatter at the edit: the zone before or after it, or a first line that spells an opening.
    private func touchesFrontmatter(_ touched: StructureMap.Touched, in text: NSString) -> Bool {
        let start = map.lines[touched.first].start
        if let zone = touched.oldFrontmatterZoneEnd, start <= zone { return true }
        if let zone = map.frontmatterZoneEnd, start <= zone { return true }
        return touched.first == 0 && Self.spellsFrontmatterOpening(line(0, in: text))
    }

    /// Lists: the last line the stacks are folded over, past the edit, until the old and the new agree.
    private func listWalkEnd(
        first: Int, last: Int, old: [MarkdownLineSignature], new: [MarkdownLineSignature]
    ) -> Int {
        let lines = map.lines
        let seed = stack(before: first)
        var oldStack = old.reduce(seed) { ListNesting.folding($0, $1.listRole) }
        var newStack = new.reduce(seed) { ListNesting.folding($0, $1.listRole) }
        var walk = last
        while oldStack != newStack, walk + 1 < lines.count {
            walk += 1
            oldStack = ListNesting.folding(oldStack, lines[walk].signature.listRole)
            newStack = ListNesting.folding(newStack, lines[walk].signature.listRole)
        }
        return walk
    }

    /// Fence bodies, the other readers' fences, and table runs a widening cut, until nothing moves.
    /// False when a cut run holds a fence mark, as `extendOverTableRuns` answers.
    private func widenOverRegions(_ low: inout Int, _ high: inout Int) -> Bool {
        let lines = map.lines
        // The map does not change inside the loop, so the regions are gathered once.
        let regions = map.fences.map(\.range) + map.codeBlocks
        var moved = true
        while moved {
            moved = false
            let rangeStart = lines[low].start
            let rangeEnd = map.lineEnd(high)
            for region in regions where region.location < rangeEnd && NSMaxRange(region) > rangeStart {
                let regionLow = map.lineIndex(containing: region.location)
                let regionHigh = map.lineIndex(containing: max(region.location, NSMaxRange(region) - 1))
                if regionLow < low { low = regionLow; moved = true }
                if regionHigh > high { high = regionHigh; moved = true }
            }
            let before = (low, high)
            if !extendOverTableRuns(&low, &high, onlyWhereCut: true) { return false }
            if before != (low, high) { moved = true }
        }
        return true
    }

    /// A range from line `low` that reaches the frontmatter, or whose first line a fragment would
    /// read as one.
    private func readsFrontmatter(from low: Int, in text: NSString) -> Bool {
        if let zone = map.frontmatterZoneEnd, map.lines[low].start <= zone { return true }
        return low > 0 && Self.spellsFrontmatterOpening(line(low, in: text))
    }

    /// Grows `low` and `high` over the runs of table-capable lines they touch, or only over the ones
    /// they cut when `onlyWhereCut`. False when a run holds a fence mark: the block tokenizer reads
    /// such a line as a row or as a fence depending on the table above it.
    private func extendOverTableRuns(_ low: inout Int, _ high: inout Int, onlyWhereCut: Bool) -> Bool {
        let lines = map.lines
        func capable(_ index: Int) -> Bool { lines[index].signature.tableCapable }
        if !onlyWhereCut || (low > 0 && capable(low)) {
            while low > 0, capable(low - 1) {
                low -= 1
                if lines[low].signature.fenceMark { return false }
            }
        }
        if !onlyWhereCut || capable(high) {
            while high + 1 < lines.count, capable(high + 1) {
                high += 1
                if lines[high].signature.fenceMark { return false }
            }
        }
        return true
    }

    /// The list stack open just before line `index`, folded from the last reset line above it.
    private func stack(before index: Int) -> [Int] {
        let lines = map.lines
        var start = index
        while start > 0, lines[start - 1].signature.listRole != .reset { start -= 1 }
        return lines[start..<index].reduce([]) { ListNesting.folding($0, $1.signature.listRole) }
    }

    /// Whether the last bracket token above line `index` is an opener outside code with a `]]`
    /// somewhere after it: the link parser would pair it across the line boundary.
    private func pendingOpener(before index: Int) -> Bool {
        let lines = map.lines
        var line = index - 1
        while line >= 0, lines[line].signature.brackets.isEmpty { line -= 1 }
        guard line >= 0, case .open(_, inCode: false)? = lines[line].signature.brackets.last else { return false }
        return lines[(line + 1)...].contains { $0.signature.brackets.contains(.close) }
    }

    /// Line `index` of `text` without its terminator.
    private func line(_ index: Int, in text: NSString) -> String {
        let start = map.lines[index].start
        var end = map.lineEnd(index)
        if end > start, end <= text.length, text.character(at: end - 1) == 10 { end -= 1 }
        return text.substring(with: NSRange(location: start, length: end - start))
    }

    /// A line either frontmatter parser could take for an opening `---`: a leading U+FEFF and
    /// blanks allowed, so the check is wider than both.
    private static func spellsFrontmatterOpening(_ line: String) -> Bool {
        var body = line
        if body.unicodeScalars.first == "\u{FEFF}" {
            body = String(String.UnicodeScalarView(body.unicodeScalars.dropFirst()))
        }
        return body.drop { $0.unicodeScalars.allSatisfy(CharacterSet.whitespaces.contains) }.hasPrefix("---")
    }

    // MARK: Folding two ranges

    /// Aligns `range` outward to whole styler lines, the last one's terminator included.
    private func aligned(_ range: NSRange) -> NSRange {
        let low = map.lineIndex(containing: range.location)
        let high = map.lineIndex(containing: max(range.location, NSMaxRange(range) - 1))
        let start = map.lines[low].start
        return NSRange(location: start, length: map.lineEnd(high) - start)
    }

    /// Where a pending range goes through a later edit: its ends move as offsets do, and an end the
    /// edit replaced lands on the edit's own bounds.
    private static func mapped(_ range: NSRange, through edit: StorageEdit) -> NSRange {
        let old = edit.oldRange
        let start: Int
        if range.location <= old.location {
            start = range.location
        } else if range.location >= NSMaxRange(old) {
            start = range.location + edit.delta
        } else {
            start = edit.range.location
        }
        let end: Int
        let rangeEnd = NSMaxRange(range)
        if rangeEnd <= old.location {
            end = rangeEnd
        } else if rangeEnd >= NSMaxRange(old) {
            end = rangeEnd + edit.delta
        } else {
            end = NSMaxRange(edit.range)
        }
        return NSRange(location: start, length: max(0, end - start))
    }

    private static func hull(_ lhs: NSRange, _ rhs: NSRange) -> NSRange {
        let start = min(lhs.location, rhs.location)
        return NSRange(location: start, length: max(NSMaxRange(lhs), NSMaxRange(rhs)) - start)
    }
}
