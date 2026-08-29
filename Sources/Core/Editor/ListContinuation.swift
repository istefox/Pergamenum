import Foundation

/// Enter-to-continue and ordered-run renumbering for list lines, pure (ADR-0028 §D6, plan
/// `2026-08-29-wysiwyg-markdown-in-workspace`, Task 2, R-07, R-08).
///
/// Sits beside `LineFormat` in `Sources/Core/Editor/` but answers a different question:
/// `LineFormat` rewrites the lines a *selection* touches, with no knowledge of what is above or
/// below them. `newline` and `renumbered` are both questions about the *run* a line belongs to -
/// where it starts, where it ends, what its own first ordinal was - which is why this is a new
/// type rather than an addition to that one (ADR-0028 §A9). The marker-recognition duplication
/// between the two files is accepted and recorded in the ADR's Consequences.
///
/// Foundation only. This is under `Sources/Core`, which both connectors compile
/// (`Project.swift`'s `sharedSources` glob, `:73`), so an `import AppKit` or `import SwiftUI`
/// here breaks `perg` and `pergamenum-mcp` rather than this file (`InlineFormat.swift`'s own
/// header warning, repeated here on purpose).
enum ListContinuation {
    /// The text and caret after pressing Return inside a list item at `selection`, or `nil` when
    /// the caret is not inside a list item at all - which is how a caller falls through to
    /// AppKit's ordinary Return.
    ///
    /// - A non-empty selection returns `nil`: Return over a selection is a replace, not a
    ///   continuation.
    /// - A caret still inside the line's indentation or its marker returns `nil` too. Return at
    ///   the start of `- primo` means «push this item down», which the ordinary Return already
    ///   does; continuing the list there would write a marker nobody typed.
    /// - An item whose text is empty *exits* the list rather than extending it: the whole prefix
    ///   goes and no line is inserted (R-07).
    /// - A bullet's own character is copied, never normalised - `* ` continues as `* `, `+ ` as
    ///   `+ ` - and a checkbox always continues as an empty box whatever this item's state.
    /// - An ordered item's continuation renumbers the run it belongs to *in the same returned
    ///   string*, so the insertion and the renumbering are one replacement and therefore one undo
    ///   step (R-12's precondition).
    static func newline(in text: String, at selection: NSRange) -> (text: String, selection: NSRange)? {
        guard selection.length == 0 else { return nil }
        let haystack = text as NSString
        let caret = min(max(selection.location, 0), haystack.length)
        let all = lines(in: haystack)
        let fenced = codeFenceFlags(in: all, haystack: haystack)

        // The line a bare caret sits on is the last one starting at or before it, so a caret on a
        // line's first character belongs to that line and not to the one that ended there.
        guard let index = all.lastIndex(where: { $0.start <= caret }), !fenced[index] else { return nil }
        let line = all[index]
        guard let marker = marker(on: line, in: haystack), caret >= marker.end else { return nil }

        let indent = haystack.substring(with: NSRange(location: line.start, length: marker.start - line.start))

        // Nothing written after the marker: the prefix is removed and the line becomes an ordinary
        // empty paragraph. No line is inserted, so the caret lands where the indentation used to
        // start (R-07's exit rule).
        guard marker.end < line.contentEnd else {
            let rewritten = NSMutableString(string: text)
            rewritten.replaceCharacters(
                in: NSRange(location: line.start, length: marker.end - line.start), with: ""
            )
            return (rewritten as String, NSRange(location: line.start, length: 0))
        }

        var edits: [Edit] = []
        let continued: String
        switch marker.kind {
        case .bullet:
            // Copied verbatim from the source rather than rebuilt, which is what preserves the
            // "-"/"*"/"+" the author chose.
            continued = haystack.substring(
                with: NSRange(location: marker.start, length: marker.end - marker.start)
            )
        case .checkbox:
            // Always an *empty* box: continuing "- [x] fatto" with another done item would tick
            // something nobody did.
            continued = haystack.substring(with: NSRange(location: marker.start, length: 1)) + " [ ] "
        case .ordered(let delimiter):
            let level = marker.start - line.start
            let members = orderedRun(containing: index, level: level, in: all, haystack: haystack, fenced: fenced)
            let position = members.firstIndex(of: index) ?? 0
            let first = ordered(on: all[members[0]], in: haystack)?.number ?? 1
            // Every member is renumbered here, not only the ones after the caret: the run is made
            // contiguous from its own first ordinal in the very string the insertion lands in, so
            // a gap left by an earlier edit closes on the same Return (R-08, ADR-0028 §A6).
            for (offset, member) in members.enumerated() {
                let ordinal = first + offset + (offset > position ? 1 : 0)
                if let edit = renumberEdit(on: all[member], to: ordinal, in: haystack) { edits.append(edit) }
            }
            continued = String(first + position + 1) + delimiter + " "
        }

        // Renumbering above the caret moves it; renumbering below it does not.
        let shift = edits
            .filter { NSMaxRange($0.range) <= caret }
            .reduce(0) { $0 + ($1.replacement as NSString).length - $1.range.length }
        let insertion = "\n" + indent + continued
        edits.append(Edit(range: NSRange(location: caret, length: 0), replacement: insertion))

        let rewritten = apply(edits, to: text)
        let location = caret + shift + (insertion as NSString).length
        return (rewritten, NSRange(location: location, length: 0))
    }

    /// `text` with every ordered run renumbered contiguously from its own first item's ordinal,
    /// or `nil` when no run needs a change.
    ///
    /// A run is renumbered from the number its first item already carries, never from 1: a list
    /// deliberately written `3. / 4. / 5.` is an author's choice, and snapping it to 1 on the next
    /// keystroke would make it impossible to write at all (ADR-0028 §A6). `nil` on an untouched
    /// text is the whole point of the return type - it is what keeps a no-op keystroke from
    /// pushing an undo step nobody asked for.
    static func renumbered(_ text: String) -> String? {
        let haystack = text as NSString
        let all = lines(in: haystack)
        let fenced = codeFenceFlags(in: all, haystack: haystack)

        var settled: Set<Int> = []
        var edits: [Edit] = []
        for index in all.indices where !settled.contains(index) && !fenced[index] {
            guard let marker = marker(on: all[index], in: haystack), case .ordered = marker.kind else { continue }
            let level = marker.start - all[index].start
            let members = orderedRun(containing: index, level: level, in: all, haystack: haystack, fenced: fenced)
            // Marked settled so a later member is not read a second time as the start of a run of
            // its own - which would renumber the tail of a run from the tail's own ordinal. A
            // nested line is never a member, so it is still reached on its own iteration and gets
            // its own run at its own level.
            settled.formUnion(members)
            guard let first = ordered(on: all[members[0]], in: haystack)?.number else { continue }
            for (offset, member) in members.enumerated() {
                if let edit = renumberEdit(on: all[member], to: first + offset, in: haystack) { edits.append(edit) }
            }
        }
        guard !edits.isEmpty else { return nil }
        return apply(edits, to: text)
    }

    // MARK: Edits

    private struct Edit {
        var range: NSRange
        var replacement: String
    }

    /// Applied back to front, so an earlier edit's length change cannot move a later edit's range
    /// out from under it. Sorted rather than assumed ordered: a nested run is discovered after the
    /// outer run it sits inside, whose remaining members are further down the text.
    private static func apply(_ edits: [Edit], to text: String) -> String {
        let rewritten = NSMutableString(string: text)
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            rewritten.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return rewritten as String
    }

    /// The edit that makes `line`'s ordinal `ordinal`, or nil when it already is - only the digits
    /// are rewritten, so the delimiter the line was written with (`.` or `)`) is preserved.
    private static func renumberEdit(on line: Line, to ordinal: Int, in haystack: NSString) -> Edit? {
        guard let ordered = ordered(on: line, in: haystack) else { return nil }
        let replacement = String(ordinal)
        guard haystack.substring(with: ordered.digits) != replacement else { return nil }
        return Edit(range: ordered.digits, replacement: replacement)
    }

    // MARK: Runs

    private enum RunRole {
        /// An ordered item at the run's own level.
        case member
        /// Nested content, carried over without belonging to the run's numbering.
        case inside
        /// Where the run ends.
        case boundary
    }

    /// The ordered items of the run `index` belongs to, in document order, `index` included.
    ///
    /// Scanned in both directions, because a caret continuing the *last* item of a run needs the
    /// run's first ordinal, which is above it.
    private static func orderedRun(
        containing index: Int, level: Int, in all: [Line], haystack: NSString, fenced: [Bool]
    ) -> [Int] {
        var above: [Int] = []
        var cursor = index - 1
        backwards: while cursor >= 0 {
            switch role(of: cursor, level: level, in: all, haystack: haystack, fenced: fenced) {
            case .member: above.append(cursor)
            case .inside: break
            case .boundary: break backwards
            }
            cursor -= 1
        }
        var members = above.reversed() + [index]
        cursor = index + 1
        forwards: while cursor < all.count {
            switch role(of: cursor, level: level, in: all, haystack: haystack, fenced: fenced) {
            case .member: members.append(cursor)
            case .inside: break
            case .boundary: break forwards
            }
            cursor += 1
        }
        return members
    }

    /// What `index` is to a run at `level`.
    ///
    /// A blank line ends a run: two ordered lists separated by one are two lists, each numbering
    /// from its own first ordinal. So does anything at the run's own level that is not an ordered
    /// item - a bullet, a checkbox (`- [ ]` is not an ordered item, and reading it as one would
    /// make the line under it the run's next number), or plain prose. A *deeper* line is nested
    /// content: it is carried over without breaking the run and gets its own run, at its own
    /// level, on its own iteration.
    private static func role(
        of index: Int, level: Int, in all: [Line], haystack: NSString, fenced: [Bool]
    ) -> RunRole {
        guard !fenced[index] else { return .boundary }
        let line = all[index]
        let indent = indentLength(on: line, in: haystack)
        guard line.start + indent < line.contentEnd else { return .boundary }
        guard indent <= level else { return .inside }
        guard indent == level,
              let marker = marker(on: line, in: haystack),
              case .ordered = marker.kind
        else { return .boundary }
        return .member
    }

    // MARK: Lines

    /// One line of the text: `start ..< contentEnd` is what is written on it, `start ..< end`
    /// includes its terminator.
    private struct Line {
        var start: Int
        var contentEnd: Int
        var end: Int
    }

    /// Every line of `haystack`, including the empty one after a trailing newline.
    ///
    /// Line boundaries come from `NSString` itself rather than from splitting on `"\n"`, so a
    /// `\r\n` pasted in from somewhere else is one terminator and not two.
    private static func lines(in haystack: NSString) -> [Line] {
        var found: [Line] = []
        var index = 0
        while index < haystack.length {
            var start = 0, end = 0, contentEnd = 0
            haystack.getLineStart(
                &start, end: &end, contentsEnd: &contentEnd,
                for: NSRange(location: index, length: 0)
            )
            found.append(Line(start: start, contentEnd: contentEnd, end: end))
            index = end
        }
        // Text ending in a terminator has one more line - empty, and the one a caret parked at
        // the very end sits on. Empty text is that same line and nothing else.
        if let last = found.last {
            if last.contentEnd < last.end {
                found.append(
                    Line(start: haystack.length, contentEnd: haystack.length, end: haystack.length)
                )
            }
        } else {
            found.append(Line(start: 0, contentEnd: 0, end: 0))
        }
        return found
    }

    /// Which lines are code, fence delimiters included.
    ///
    /// A `- item` inside a fenced block is a character of somebody's shell script, not a list:
    /// continuing it would write a marker into their code, and renumbering would rewrite their
    /// digits.
    private static func codeFenceFlags(in all: [Line], haystack: NSString) -> [Bool] {
        var flags = [Bool](repeating: false, count: all.count)
        var open = false
        for (index, line) in all.enumerated() {
            if isFenceDelimiter(line, in: haystack) {
                flags[index] = true
                open.toggle()
            } else {
                flags[index] = open
            }
        }
        return flags
    }

    private static func isFenceDelimiter(_ line: Line, in haystack: NSString) -> Bool {
        let start = line.start + indentLength(on: line, in: haystack)
        return matches("```", in: haystack, at: start, limit: line.contentEnd)
            || matches("~~~", in: haystack, at: start, limit: line.contentEnd)
    }

    private static func indentLength(on line: Line, in haystack: NSString) -> Int {
        var cursor = line.start
        while cursor < line.contentEnd {
            let character = haystack.character(at: cursor)
            guard character == 0x20 || character == 0x09 else { break }  // space or tab
            cursor += 1
        }
        return cursor - line.start
    }

    // MARK: Markers

    private enum Kind {
        /// `- `, `* `, `+ `.
        case bullet
        /// `- [ ] `, `* [x] ` and the other states `TaskParser.state(for:)` recognizes.
        case checkbox
        /// `1. `, `12) ` - the one kind whose continuation is arithmetic rather than a copy.
        case ordered(delimiter: String)
    }

    /// A line's list prefix: `start` is where the marker begins (past the indentation), `end`
    /// where the item's own text begins.
    private struct Marker {
        var start: Int
        var end: Int
        var kind: Kind
    }

    private static func marker(on line: Line, in haystack: NSString) -> Marker? {
        let start = line.start + indentLength(on: line, in: haystack)
        if let ordered = ordered(on: line, in: haystack) {
            return Marker(start: start, end: ordered.end, kind: .ordered(delimiter: ordered.delimiter))
        }
        guard start + 1 < line.contentEnd else { return nil }
        let bullet = haystack.character(at: start)
        guard bullet == 0x2D || bullet == 0x2A || bullet == 0x2B,  // "-", "*" or "+"
              haystack.character(at: start + 1) == 0x20            // " "
        else { return nil }
        guard isChecklistMarker(in: haystack, at: start + 2, limit: line.contentEnd) else {
            return Marker(start: start, end: start + 2, kind: .bullet)
        }
        // A box written without a trailing space is still a checkbox line; its text simply begins
        // where the box ends.
        var end = start + 5
        if end < line.contentEnd, haystack.character(at: end) == 0x20 { end += 1 }
        return Marker(start: start, end: end, kind: .checkbox)
    }

    /// The ordered marker on `line`: its number, the range of its digits - the only part a
    /// renumbering rewrites - the delimiter it was written with, and where the item's text begins.
    private static func ordered(
        on line: Line, in haystack: NSString
    ) -> (number: Int, digits: NSRange, delimiter: String, end: Int)? {
        let start = line.start + indentLength(on: line, in: haystack)
        var cursor = start
        while cursor < line.contentEnd, isDigit(haystack.character(at: cursor)) { cursor += 1 }
        guard cursor > start, cursor + 1 < line.contentEnd else { return nil }
        guard haystack.character(at: cursor) == 0x2E || haystack.character(at: cursor) == 0x29,  // "." or ")"
              haystack.character(at: cursor + 1) == 0x20  // " "
        else { return nil }
        let digits = NSRange(location: start, length: cursor - start)
        guard let number = Int(haystack.substring(with: digits)) else { return nil }
        return (
            number, digits,
            haystack.substring(with: NSRange(location: cursor, length: 1)),
            cursor + 2
        )
    }

    /// Whether `"[X]"` sits at `index`, `X` being one of `TaskParser.state(for:)`'s markers: a
    /// space (open), `x`/`X` (done), `>` (rescheduled) or `-` (cancelled).
    private static func isChecklistMarker(in haystack: NSString, at index: Int, limit: Int) -> Bool {
        guard index + 3 <= limit, haystack.character(at: index) == 0x5B else { return false }  // "["
        guard haystack.character(at: index + 2) == 0x5D else { return false }  // "]"
        let state = haystack.character(at: index + 1)
        return state == 0x20 || state == 0x78 || state == 0x58 || state == 0x3E || state == 0x2D
    }

    private static func matches(
        _ needle: String, in haystack: NSString, at index: Int, limit: Int
    ) -> Bool {
        let length = (needle as NSString).length
        guard index + length <= limit else { return false }
        return haystack.substring(with: NSRange(location: index, length: length)) == needle
    }

    private static func isDigit(_ character: unichar) -> Bool {
        character >= 0x30 && character <= 0x39
    }
}
