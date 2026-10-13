import Foundation

// The scoped renumbering (ADR-0082 §D6) and its windowed sibling (ADR-0093 §D8), in a file of their
// own so `ListContinuation.swift` stays within SwiftLint's file length. Both hand the lines they read to
// one run walk, `renumbering(of:fenced:first:last:in:)`, so the windowed answer is the scoped one by
// construction rather than by two implementations agreeing. `LineScan.Line` carries absolute offsets, so
// the walk needs no base shift for a window that starts inside the note.
//
// Foundation only: `Sources/Core` compiles into both connectors (ADR-0001 §D1).
extension ListContinuation {
    /// What a scoped renumbering rewrites (ADR-0082 §D6): the smallest range covering every marker
    /// that changes, what replaces it, and where a location of the old text lands in the new one.
    struct Renumbering: Equatable, Sendable {
        let range: NSRange
        let replacement: String
        /// Every rewritten digit run, in old-text coordinates and document order.
        fileprivate let edits: [DigitEdit]

        /// Where `location` of the text before the rewrite lands in the text after it: moved by
        /// every rewritten digit run that ends at or before it, and kept inside a run it falls in,
        /// so the caret never crosses a marker it sat in.
        func mapping(_ location: Int) -> Int {
            var shift = 0
            for edit in edits {
                if location >= edit.location + edit.oldLength {
                    shift += edit.newLength - edit.oldLength
                } else if location > edit.location {
                    return min(location, edit.location + edit.newLength) + shift
                } else {
                    break
                }
            }
            return location + shift
        }
    }

    /// One digit run a scoped renumbering rewrites, with the lengths `mapping` needs.
    fileprivate struct DigitEdit: Equatable, Sendable { let location, oldLength, newLength: Int }

    /// Where a windowed read starts: a line whose previous line ends every run (or the first), and
    /// whether a code fence is open there in the renumberer's sense.
    struct Window: Equatable, Sendable {
        var start: Int
        var fenceOpen: Bool
    }

    /// What the windowed form answers: the scoped form's renumbering, how many lines it read and the
    /// range they cover, so a test can see the read does not follow the note.
    struct Windowed: Equatable, Sendable {
        var renumbering: Renumbering?
        var linesRead: Int
        var readRange: NSRange
    }

    /// What the renumbering needs to know about a styler line without reading its neighbours: how many
    /// fence delimiters it holds and whether its last line ends every ordered run.
    struct LineFacts: Equatable, Sendable {
        var fenceDelimiters: Int
        var endsEveryRun: Bool
    }

    // MARK: The scoped form

    /// The renumbering of only the ordered runs that touch `edited`, widened by one line on each
    /// side, or `nil` when none of them needs a change.
    ///
    /// `edited` is a range of `text` after the edit; the widening sees a deleted blank line that
    /// merged two runs. A misnumbered run the edit does not reach is left alone. `renumbered(_:)`
    /// stays the whole-text answer for the card and for a `textDidChange` with no recorded range.
    static func renumbered(_ text: String, touching edited: NSRange) -> Renumbering? {
        let haystack = text as NSString
        let all = LineScan.lines(in: haystack)
        let fenced = codeFenceFlags(in: all, haystack: haystack)
        let lower = max(0, min(edited.location, haystack.length))
        let upper = max(lower, min(NSMaxRange(edited), haystack.length))
        guard let first = all.lastIndex(where: { $0.start <= lower }),
              let last = all.lastIndex(where: { $0.start <= upper })
        else { return nil }
        return renumbering(of: all, fenced: fenced, first: first, last: last, in: haystack)
    }

    // MARK: The windowed form (ADR-0093 §D8)

    /// The facts of the styler line `line` of `text`, its terminator included: the fence delimiters
    /// among its `LineScan` lines (one after a lone CR, NEL, U+2028 or U+2029 counts), and whether its
    /// last `LineScan` line ends every ordered run whatever the fence state.
    static func facts(ofLine line: NSRange, in text: NSString) -> LineFacts {
        let end = min(NSMaxRange(line), text.length)
        var index = max(0, min(line.location, text.length))
        // An empty range is one empty line, as the empty text is.
        var last = LineScan.Line(start: index, contentEnd: index, end: index)
        var delimiters = 0
        while index < end {
            let piece = LineScan.line(at: index, in: text)
            if isFenceDelimiter(piece, in: text) { delimiters += 1 }
            last = piece
            index = piece.end
        }
        return LineFacts(fenceDelimiters: delimiters, endsEveryRun: endsEveryRun(last, in: text))
    }

    /// `renumbered(_:touching:)` over the lines from `window.start` onward: read forward, the fence
    /// flag seeded with `window.fenceOpen`, up to and including the first line after the edit's last
    /// line that ends every run, or to the end of the text. Every run the scoped form would renumber
    /// has ended by then, and none starts above the window, whose previous line ends every run.
    static func renumbered(_ text: NSString, touching edited: NSRange, window: Window) -> Windowed {
        let length = text.length
        let lower = max(0, min(edited.location, length))
        let upper = max(lower, min(NSMaxRange(edited), length))
        var lines: [LineScan.Line] = []
        var fenced: [Bool] = []
        var open = window.fenceOpen
        var index = max(0, min(window.start, length))
        var stopped = false
        while index < length {
            let line = LineScan.line(at: index, in: text)
            if isFenceDelimiter(line, in: text) {
                fenced.append(true)
                open.toggle()
            } else {
                fenced.append(open)
            }
            lines.append(line)
            index = line.end
            if line.start > upper, endsEveryRun(line, in: text) {
                stopped = true
                break
            }
        }
        // `LineScan.lines(in:)`'s empty last line, after a terminator at the end of the text.
        if !stopped, lines.last.map({ $0.contentEnd < $0.end }) ?? true {
            lines.append(LineScan.Line(start: length, contentEnd: length, end: length))
            fenced.append(open)
        }

        let readStart = lines.first?.start ?? 0
        let readRange = NSRange(location: readStart, length: (lines.last?.end ?? readStart) - readStart)
        guard let first = lines.lastIndex(where: { $0.start <= lower }),
              let last = lines.lastIndex(where: { $0.start <= upper })
        else { return Windowed(renumbering: nil, linesRead: lines.count, readRange: readRange) }
        return Windowed(
            renumbering: renumbering(of: lines, fenced: fenced, first: first, last: last, in: text),
            linesRead: lines.count, readRange: readRange
        )
    }

    // MARK: The walk both forms share

    /// Whether `line` ends every ordered run whatever the fence state, by `role(of:level:…)`'s own
    /// tests: it is blank, it is a fence delimiter, or it sits at column 0 and is not an ordered item.
    private static func endsEveryRun(_ line: LineScan.Line, in haystack: NSString) -> Bool {
        let indent = LineScan.indentLength(on: line, in: haystack)
        if line.start + indent >= line.contentEnd { return true }
        if isFenceDelimiter(line, in: haystack) { return true }
        return indent == 0 && ordered(on: line, in: haystack) == nil
    }

    /// The runs that touch lines `first ... last` of `all`, widened by one line on each side, made
    /// contiguous from each run's own first ordinal, as one covering rewrite.
    private static func renumbering(
        of all: [LineScan.Line], fenced: [Bool], first: Int, last: Int, in haystack: NSString
    ) -> Renumbering? {
        var settled: Set<Int> = []
        var edits: [Edit] = []
        for index in max(0, first - 1)...min(all.count - 1, last + 1)
        where !settled.contains(index) && !fenced[index] {
            guard let marker = marker(on: all[index], in: haystack), case .ordered = marker.kind else { continue }
            let members = orderedRun(
                containing: index, level: marker.start - all[index].start, in: all, haystack: haystack, fenced: fenced
            )
            settled.formUnion(members)
            guard let start = ordered(on: all[members[0]], in: haystack)?.number else { continue }
            for (offset, member) in members.enumerated() {
                if let edit = renumberEdit(on: all[member], to: start + offset, in: haystack) { edits.append(edit) }
            }
        }
        guard !edits.isEmpty else { return nil }

        // Digit runs never overlap, so the last one in document order ends the covering range.
        let sorted = edits.sorted { $0.range.location < $1.range.location }
        let start = sorted[0].range.location
        let covering = NSRange(location: start, length: NSMaxRange(sorted[sorted.count - 1].range) - start)
        let local = sorted.map { edit in
            Edit(range: NSRange(location: edit.range.location - start, length: edit.range.length),
                 replacement: edit.replacement)
        }
        let digits = sorted.map { edit in
            DigitEdit(location: edit.range.location, oldLength: edit.range.length,
                      newLength: (edit.replacement as NSString).length)
        }
        let replacement = apply(local, to: haystack.substring(with: covering))
        return Renumbering(range: covering, replacement: replacement, edits: digits)
    }
}
