import Foundation

/// Bullet, numbered and heading prefixes on the lines a selection touches (ADR-0027 §D6, plan
/// `2026-08-28-unificare-nota-e-testo-in-un-solo-strume`, Task 2, R-05).
///
/// `InlineFormat` wraps a *selection* in a pair of markers; a list or a heading is a *line*
/// operation instead - it does not surround characters, it rewrites the start of every line the
/// selection touches, and it must do that whether the selection is a whole paragraph, a single
/// word inside one line, or a bare caret. The two pure engines sit side by side on purpose
/// (`FormattingTextView` in a later task wires both through the same one-edit-per-press path),
/// but they do not share an implementation: markers-around-a-range and prefix-on-every-line are
/// different arithmetic.
///
/// Foundation only. This is under `Sources/Core`, which both connectors compile
/// (`Project.swift`'s `sharedSources` glob, `:73`), so an `import AppKit` or `import SwiftUI`
/// here breaks `perg` and `pergamenum-mcp` rather than this file.
enum LineFormat: Equatable, Sendable {
    case bullet
    case numbered
    /// 1...3, per SPEC scope (`MarkdownStyler`'s existing heading spans go no deeper).
    case heading(level: Int)

    /// Whether every line `range` touches already carries this format, which is what lights the
    /// card's format-bar button and what `toggled` inverts. A *mixed* selection - one line
    /// already prefixed, one not - reads as not-applied, so the next press adds the format to
    /// every touched line rather than stripping the one that already has it (plan Task 2, "one
    /// press makes the whole selection consistent").
    static func isApplied(_ format: Self, in text: String, over range: NSRange) -> Bool {
        let haystack = text as NSString
        let touched = touchedLines(in: haystack, over: clamped(range, to: haystack.length))
        guard !touched.isEmpty else { return false }
        return touched.allSatisfy { markerLength(of: format, on: $0, in: haystack) != nil }
    }

    /// The text after toggling `format` over every line `range` touches, and where the
    /// selection ends up afterwards.
    ///
    /// - A bare caret (`range.length == 0`) still touches exactly one line, its own, and is not
    ///   a no-op - unlike `InlineFormat.toggled`'s empty-selection rule, which exists to avoid
    ///   leaving a stray marker pair around nothing. There is no equivalent trap here: the
    ///   caret's line is real text (or a real empty line) either way.
    /// - `.numbered` renumbers the touched run from 1 regardless of the lines' position in the
    ///   rest of the document.
    /// - `.heading(level:)` over a line already at a *different* level replaces that line's
    ///   marker rather than stacking a third `#` onto it.
    /// - The returned selection covers the same words it did before, the same contract
    ///   `InlineFormat.toggled` keeps, so pressing the same button twice acts on what the first
    ///   press acted on.
    static func toggled(
        _ format: Self, in text: String, over range: NSRange
    ) -> (text: String, selection: NSRange) {
        let haystack = text as NSString
        let selection = clamped(range, to: haystack.length)
        let touched = touchedLines(in: haystack, over: selection)
        guard !touched.isEmpty else { return (text, selection) }

        // A *mixed* selection removes nothing: only when every touched line already carries the
        // format does the press take it away, which is the same rule `isApplied` answers with.
        let removing = touched.allSatisfy { markerLength(of: format, on: $0, in: haystack) != nil }

        var edits: [Edit] = []
        for (offset, line) in touched.enumerated() {
            let start = line.start + indentLength(on: line, in: haystack)
            if removing {
                guard let length = markerLength(of: format, on: line, in: haystack) else { continue }
                edits.append(Edit(start: start, oldLength: length, replacement: ""))
            } else {
                // Whatever line marker the line already carries is *replaced*, never stacked: a
                // level-1 heading asked for level 2 becomes `## `, not `### `, and a line means
                // one of bullet / numbered / heading at a time rather than `1. - item`.
                edits.append(
                    Edit(
                        start: start,
                        oldLength: anyMarkerLength(on: line, in: haystack),
                        replacement: marker(for: format, ordinal: offset + 1)
                    )
                )
            }
        }
        guard !edits.isEmpty else { return (text, selection) }

        // Applied back to front, so an earlier edit's length change cannot move a later edit's
        // start out from under it.
        let rewritten = NSMutableString(string: text)
        for edit in edits.reversed() {
            rewritten.replaceCharacters(
                in: NSRange(location: edit.start, length: edit.oldLength), with: edit.replacement
            )
        }
        let start = mapped(selection.location, through: edits)
        let end = mapped(NSMaxRange(selection), through: edits)
        return (rewritten as String, NSRange(location: start, length: max(0, end - start)))
    }

    // MARK: The lines a selection touches

    /// One line of the text: `start ..< contentEnd` is what is written on it, `start ..< end`
    /// includes its terminator.
    private struct Line {
        var start: Int
        var contentEnd: Int
        var end: Int
    }

    private struct Edit {
        var start: Int
        var oldLength: Int
        var replacement: String
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

    private static func touchedLines(in haystack: NSString, over range: NSRange) -> [Line] {
        let all = lines(in: haystack)
        guard range.length > 0 else {
            // A bare caret is one line, the last one starting at or before it - so a caret on a
            // line's first character belongs to that line, not to the one that ended there.
            return all.last(where: { $0.start <= range.location }).map { [$0] } ?? []
        }
        let end = NSMaxRange(range)
        // A selection stopping exactly where the next line begins has not reached it.
        return all.filter { $0.start < end && $0.end > range.location }
    }

    // MARK: Markers

    private static func marker(for format: Self, ordinal: Int) -> String {
        switch format {
        case .bullet: "- "
        case .numbered: "\(ordinal). "
        case .heading(let level): String(repeating: "#", count: headingLevel(level)) + " "
        }
    }

    /// The length of `format`'s own marker on `line`, or nil when the line does not carry it.
    ///
    /// Measured from the end of the line's indentation, so a nested `  - item` reads as a bullet
    /// and gets its prefix rewritten in place rather than a second one bolted on in front of the
    /// spaces.
    private static func markerLength(of format: Self, on line: Line, in haystack: NSString) -> Int? {
        let start = line.start + indentLength(on: line, in: haystack)
        switch format {
        case .bullet:
            return matches("- ", in: haystack, at: start, limit: line.contentEnd) ? 2 : nil
        case .numbered:
            return numberedMarkerLength(in: haystack, at: start, limit: line.contentEnd)
        case .heading(let level):
            // The trailing space is what tells the levels apart: `## Titolo` does not start with
            // `# `, so a level-1 button does not light on a level-2 heading.
            let hashes = String(repeating: "#", count: headingLevel(level)) + " "
            return matches(hashes, in: haystack, at: start, limit: line.contentEnd)
                ? (hashes as NSString).length : nil
        }
    }

    /// The length of whichever line marker the line carries, 0 when it carries none. This is what
    /// an applied format replaces.
    private static func anyMarkerLength(on line: Line, in haystack: NSString) -> Int {
        if let bullet = markerLength(of: .bullet, on: line, in: haystack) { return bullet }
        if let numbered = markerLength(of: .numbered, on: line, in: haystack) { return numbered }
        // Read every CommonMark level, not only the 1...3 this feature writes, so a `#####`
        // pasted in from a note is replaced rather than stacked on.
        for level in 1...6 {
            if let heading = markerLength(of: .heading(level: level), on: line, in: haystack) {
                return heading
            }
        }
        return 0
    }

    /// `12. ` and `12) ` both, since CommonMark writes either; this file only ever emits the dot.
    private static func numberedMarkerLength(
        in haystack: NSString, at index: Int, limit: Int
    ) -> Int? {
        var cursor = index
        while cursor < limit, isDigit(haystack.character(at: cursor)) { cursor += 1 }
        guard cursor > index, cursor + 1 < limit else { return nil }
        let delimiter = haystack.character(at: cursor)
        guard delimiter == 0x2E || delimiter == 0x29,  // "." or ")"
              haystack.character(at: cursor + 1) == 0x20  // " "
        else { return nil }
        return cursor + 2 - index
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

    /// SPEC scope is 1...3; clamping to CommonMark's 1...6 keeps a caller's stray value from
    /// writing `#`-less or unbounded markers.
    private static func headingLevel(_ level: Int) -> Int { min(max(level, 1), 6) }

    // MARK: Where the selection lands

    private static func clamped(_ range: NSRange, to length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        return NSRange(
            location: location, length: min(max(range.length, 0), length - location)
        )
    }

    /// Where `position` ends up once every edit has been applied, so the selection keeps covering
    /// the words it covered before rather than growing over the markers.
    private static func mapped(_ position: Int, through edits: [Edit]) -> Int {
        var delta = 0
        for edit in edits {
            let replacement = (edit.replacement as NSString).length
            if position >= edit.start + edit.oldLength {
                delta += replacement - edit.oldLength
            } else if position >= edit.start {
                // Inside the marker being rewritten: no character of the new text answers to it,
                // so it lands where the line's own words now start.
                return edit.start + delta + replacement
            } else {
                break  // Edits run in ascending order; this one and the rest are past `position`.
            }
        }
        return position + delta
    }
}
