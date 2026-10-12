import Foundation
import Testing
@testable import Pergamenum

// ADR-0093 §D8, plan docs/plans/scoped-layout-followup.md, Task 5 (R-10).
//
// The windowed renumbering equals the scoped one. Over notes made of list lines, fences, blank lines
// and prose, in every terminator the editor can hold (`\n`, `\r\n`, a lone `\r`, NEL, U+2028, U+2029),
// edited at a random offset, the window a `RestyleScope` hands out and the windowed read give, for the
// same edit, the same renumbering as `renumbered(_:touching:)` read over the whole note: the range, the
// replacement and the mapping at every offset of the rewritten range.
//
// "Equals the whole-text renumbering" is read as ADR-0093 §D8 reads it: where the text after the
// windowed rewrite has nothing left to renumber, `renumbered(_:)` of the edited text gives that same
// text. Literal equality with `renumbered(_:)` would force the windowed form to touch misnumbered runs
// the edit never reached, which ADR-0082 §D6 forbids.
//
// The counters at the end of each seed are the non-vacuity guard: equal results are also what a form
// that renumbers nothing gives, so each seed must also have produced renumberings to compare.

private let seeds: [UInt64] = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]
private let casesPerSeed = 300

// MARK: - The generator

private let terminators: [(String, Int)] = [
    ("\n", 70), ("\r\n", 8), ("\r", 7), ("\u{85}", 5), ("\u{2028}", 5), ("\u{2029}", 5),
]

private struct NoteGenerator {
    var random: SplitMix64

    init(seed: UInt64) { random = SplitMix64(seed: seed) }

    mutating func chance(_ percent: Int) -> Bool { Int.random(in: 0..<100, using: &random) < percent }

    mutating func pick<T>(_ items: [T]) -> T { items[Int.random(in: 0..<items.count, using: &random)] }

    mutating func weighted(_ items: [(String, Int)]) -> String {
        var roll = Int.random(in: 0..<items.reduce(0) { $0 + $1.1 }, using: &random)
        for (item, weight) in items {
            if roll < weight { return item }
            roll -= weight
        }
        return items[0].0
    }

    private mutating func indent() -> String {
        weighted([("", 55), ("  ", 10), ("   ", 10), ("    ", 15), ("\t", 10)])
    }

    private mutating func word() -> String { pick(["voce", "x", "é", "item lungo", "dato"]) }

    /// A run of ordered items at `indent`, counting on from `start` with the odd gap, sometimes with a
    /// nested run under an item.
    private mutating func list(indent: String, depth: Int = 0) -> [String] {
        var number = pick([1, 1, 1, 3, 5, 9, 10, 99])
        let delimiter = pick([".", ".", ".", ")"])
        var lines: [String] = []
        for _ in 0..<Int.random(in: 2...7, using: &random) {
            lines.append(indent + "\(number)" + delimiter + " " + word())
            if depth < 1, chance(25) {
                lines += list(indent: indent + pick(["  ", "   ", "    ", "\t"]), depth: depth + 1)
            }
            number += chance(70) ? 1 : (chance(60) ? Int.random(in: 2...4, using: &random) : 0)
        }
        return lines
    }

    private mutating func block() -> [String] {
        switch Int.random(in: 0..<100, using: &random) {
        case 0..<45: return list(indent: indent())
        case 45..<60:
            let mark = pick(["```", "```", "~~~", "```swift"])
            let lead = pick(["", "", "  ", "\t"])
            var lines = [lead + mark]
            for _ in 0..<Int.random(in: 0...3, using: &random) { lines.append(chance(50) ? "1. nel codice" : "codice") }
            if chance(80) { lines.append(lead + mark) }
            return lines
        case 60..<75: return pick([[""], ["   "], ["\t"], ["", ""]])
        case 75..<85: return [pick(["prosa", "un'altra riga di prosa", "  prosa rientrata", "# Titolo"])]
        case 85..<93: return [indent() + pick(["-", "*", "+"]) + " " + word(), indent() + pick(["- [ ] ", "- [x] "]) + "attivita"]
        default: return [indent() + "\(Int.random(in: 1...12, using: &random))" + pick([".", ")"]) + " " + word()]
        }
    }

    mutating func note() -> String {
        var text = ""
        for _ in 0..<Int.random(in: 2...6, using: &random) {
            for line in block() { text += line + weighted(terminators) }
        }
        return text
    }

    private static let tokens = [
        "1. ", "2. ", "\n", "\n\n", "```", "~~~", "  ", "\t", "x", "- ", "\r", "\u{2028}", "\u{85}", "7", "10. ", ")", ".",
        "\r\n", "\u{2029}", " ", "3. voce\n", "# ", "1. ", "5. ", "\n", "\n", "    ", "\n\n",
    ]

    /// A random edit of `text`: its range, and what replaces it.
    mutating func edit(of text: NSString) -> (range: NSRange, replacement: String) {
        var location = Int.random(in: 0...text.length, using: &random)
        // Half of the edits land at the start of a line, where a marker is typed or a line is joined.
        if chance(50) { location = text.lineRange(for: NSRange(location: min(location, max(0, text.length - 1)), length: 0)).location }
        let tail = text.length - location
        switch Int.random(in: 0..<3, using: &random) {
        case 0: return (NSRange(location: location, length: 0), pick(Self.tokens))
        case 1:
            guard tail > 0 else { return (NSRange(location: location, length: 0), pick(Self.tokens)) }
            return (NSRange(location: location, length: Int.random(in: 1...min(8, tail), using: &random)), "")
        default:
            guard tail > 0 else { return (NSRange(location: location, length: 0), pick(Self.tokens)) }
            return (NSRange(location: location, length: Int.random(in: 1...min(4, tail), using: &random)), pick(Self.tokens))
        }
    }
}

// MARK: - What a case checks

private func applied(_ renumbering: ListContinuation.Renumbering?, to text: String) -> String {
    guard let renumbering else { return text }
    return (text as NSString).replacingCharacters(in: renumbering.range, with: renumbering.replacement)
}

private let separators: Set<unichar> = [0x0D, 0x85, 0x2028, 0x2029]

/// Whether `range` of `text` holds a terminator other than a "\n" or the "\n" of a "\r\n": a line the
/// styler does not split and the list renumbering does.
private func holdsAnExtraSeparator(_ range: NSRange, in text: NSString) -> Bool {
    guard range.length > 0 else { return false }
    for offset in range.location..<NSMaxRange(range) {
        let unit = text.character(at: offset)
        guard separators.contains(unit) else { continue }
        if unit == 0x0D, offset + 1 < text.length, text.character(at: offset + 1) == 0x0A { continue }
        return true
    }
    return false
}

private struct Counters {
    var renumbered = 0
    var windowAboveStart = 0
    var fenceOpen = 0
    var nestedRunFixed = 0
    var extraSeparator = 0
    var gappedRunFixed = 0
    var keptScopeChecked = 0
}

/// The ordinals of the lines of `text` that are ordered items at column 0, in order, with their line index.
private func hasGappedColumnZeroRun(_ text: String) -> Bool {
    let haystack = text as NSString
    var previous: (index: Int, number: Int)?
    for (index, line) in LineScan.lines(in: haystack).enumerated() {
        var cursor = line.start
        while cursor < line.contentEnd, LineScan.isDigit(haystack.character(at: cursor)) { cursor += 1 }
        guard cursor > line.start, cursor + 1 < line.contentEnd,
              let number = Int(haystack.substring(with: NSRange(location: line.start, length: cursor - line.start)))
        else { previous = nil; continue }
        if let before = previous, before.index + 1 == index, number >= before.number + 2 { return true }
        previous = (index, number)
    }
    return false
}

/// Whether a line of `before` that begins with white space differs, by position, from `after`'s line.
private func fixedANestedItem(_ before: String, _ after: String) -> Bool {
    let old = LineScan.lines(in: before as NSString)
    let new = LineScan.lines(in: after as NSString)
    guard old.count == new.count else { return false }
    let left = before as NSString
    let right = after as NSString
    for (a, b) in zip(old, new) {
        let first = a.contentEnd > a.start ? left.character(at: a.start) : 0
        guard first == 0x20 || first == 0x09 else { continue }
        if left.substring(with: NSRange(location: a.start, length: a.contentEnd - a.start))
            != right.substring(with: NSRange(location: b.start, length: b.contentEnd - b.start)) { return true }
    }
    return false
}

// MARK: - The property

// (R-10) Over 300 random notes and edits per seed, the windowed renumbering equals the scoped one.
@Test(arguments: seeds)
func theWindowedRenumberingEqualsTheScopedOne(_ seed: UInt64) {
    var generator = NoteGenerator(seed: seed)
    var counters = Counters()
    var failures: [String] = []
    func fail(_ message: @autoclosure () -> String) { failures.append(message()) }

    for _ in 0..<casesPerSeed {
        let before = generator.note() as NSString
        let change = generator.edit(of: before)
        let text = before.replacingCharacters(in: change.range, with: change.replacement)
        let nsText = text as NSString
        let replacementLength = (change.replacement as NSString).length
        let edited = NSRange(location: change.range.location, length: replacementLength)
        let label = "text \(text.debugDescription) edited \(edited)"

        let scope = RestyleScope(text: text)
        guard let window = scope.renumberWindow(before: edited.location) else {
            fail("no window: \(label)")
            continue
        }
        let windowed = ListContinuation.renumbered(nsText, touching: edited, window: window)
        let scoped = ListContinuation.renumbered(text, touching: edited)

        // The same range, replacement and mapping.
        switch (windowed.renumbering, scoped) {
        case (nil, nil): break
        case let (one?, other?):
            if one.range != other.range { fail("range \(one.range) against \(other.range): \(label)") }
            if one.replacement != other.replacement { fail("replacement \(one.replacement.debugDescription) against \(other.replacement.debugDescription): \(label)") }
            for offset in one.range.location...NSMaxRange(one.range) where one.mapping(offset) != other.mapping(offset) {
                fail("mapping of \(offset): \(one.mapping(offset)) against \(other.mapping(offset)): \(label)")
                break
            }
        default:
            fail("windowed \(String(describing: windowed.renumbering?.range)) against scoped \(String(describing: scoped?.range)): \(label)")
        }
        if windowed.readRange.location < window.start || NSMaxRange(windowed.readRange) > nsText.length {
            fail("read range \(windowed.readRange) outside \(window.start)..<\(nsText.length): \(label)")
        }

        // Where nothing is left to renumber after the windowed rewrite, the whole-text answer is that text.
        let rewritten = applied(windowed.renumbering, to: text)
        if ListContinuation.renumbered(rewritten) == nil {
            let whole = ListContinuation.renumbered(text) ?? text
            if whole != rewritten { fail("whole-text \(whole.debugDescription) against windowed \(rewritten.debugDescription): \(label)") }
        }

        // A scope kept through the edit gives the window a fresh one does.
        var kept = RestyleScope(text: before as String)
        let wholesale = change.range.location == 0 && change.range.length == before.length
        kept.record(StorageEdit(range: edited, delta: replacementLength - change.range.length), in: nsText)
        if !wholesale {
            counters.keptScopeChecked += 1
            if kept.renumberWindow(before: edited.location) != window {
                fail("kept scope \(String(describing: kept.renumberWindow(before: edited.location))) against \(window): \(label)")
            }
        }

        if windowed.renumbering != nil {
            counters.renumbered += 1
            if window.start > 0 { counters.windowAboveStart += 1 }
            if window.fenceOpen { counters.fenceOpen += 1 }
            if fixedANestedItem(text, rewritten) { counters.nestedRunFixed += 1 }
            if holdsAnExtraSeparator(windowed.readRange, in: nsText) { counters.extraSeparator += 1 }
            if hasGappedColumnZeroRun(text) { counters.gappedRunFixed += 1 }
        }
    }

    #expect(failures.isEmpty, "\(failures.count) of \(casesPerSeed) cases differ; the first: \(failures.prefix(3))")
    // Non-vacuity: a form that renumbers nothing, or that is only ever asked from the top, agrees with
    // itself.
    #expect(counters.renumbered >= 80, "\(counters)")
    #expect(counters.windowAboveStart >= 30, "\(counters)")
    #expect(counters.fenceOpen >= 3, "\(counters)")
    #expect(counters.nestedRunFixed >= 40, "\(counters)")
    #expect(counters.extraSeparator >= 50, "\(counters)")
    #expect(counters.gappedRunFixed >= 30, "\(counters)")
    #expect(counters.keptScopeChecked >= casesPerSeed - 5, "\(counters)")
}
