import Foundation

/// Line-scan primitives shared by `LineFormat` and `ListContinuation` (ADR-0071 §D9).
///
/// The two enums answer different questions and stay separate (ADR-0028 A9); only the scanning
/// underneath them lives here, so a change to how a line or a checklist marker is recognised is
/// made once. Foundation-only and `internal`: `sharedSources` compiles it into `perg` and
/// `pergamenum-mcp`, where nothing is `public`.
enum LineScan {
    /// One line of the text: `start ..< contentEnd` is what is written on it, `start ..< end`
    /// includes its terminator.
    struct Line {
        var start: Int
        var contentEnd: Int
        var end: Int
    }

    /// Every line of `haystack`, including the empty one after a trailing newline.
    ///
    /// Line boundaries come from `NSString` itself rather than from splitting on `"\n"`, so a
    /// `\r\n` pasted in from somewhere else is one terminator and not two.
    static func lines(in haystack: NSString) -> [Line] {
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

    static func indentLength(on line: Line, in haystack: NSString) -> Int {
        var cursor = line.start
        while cursor < line.contentEnd {
            let character = haystack.character(at: cursor)
            guard character == 0x20 || character == 0x09 else { break }  // space or tab
            cursor += 1
        }
        return cursor - line.start
    }

    /// Whether `"[X]"` sits at `index`, `X` being one of `TaskParser.state(for:)`'s markers: a
    /// space (open), `x`/`X` (done), `>` (rescheduled) or `-` (cancelled).
    static func isChecklistMarker(in haystack: NSString, at index: Int, limit: Int) -> Bool {
        guard index + 3 <= limit, haystack.character(at: index) == 0x5B else { return false }  // "["
        guard haystack.character(at: index + 2) == 0x5D else { return false }  // "]"
        let state = haystack.character(at: index + 1)
        return state == 0x20 || state == 0x78 || state == 0x58 || state == 0x3E || state == 0x2D
    }

    static func matches(
        _ needle: String, in haystack: NSString, at index: Int, limit: Int
    ) -> Bool {
        let length = (needle as NSString).length
        guard index + length <= limit else { return false }
        return haystack.substring(with: NSRange(location: index, length: length)) == needle
    }

    static func isDigit(_ character: unichar) -> Bool {
        character >= 0x30 && character <= 0x39
    }
}
