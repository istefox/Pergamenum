import Foundation

/// The emphasis delimiter rules: which marker a run opens with, whether it opens at all, and where
/// it closes. Apart from `MarkdownInline.swift` only for SwiftLint's file and type-body limits; the
/// scanner there is their one caller. `emphasisMarker(at:)`, `opensEmphasis(_:marker:after:)` and
/// `closingRange(of:in:)` widen from `private` to internal for that reason, and nothing else calls
/// them.
extension MarkdownInlineParser {
    static func emphasisMarker(at rest: Substring) -> (String, MarkdownSpan.Style)? {
        if rest.hasPrefix("**") { return ("**", .strong) }
        if rest.hasPrefix("__") { return ("__", .strong) }
        if rest.hasPrefix("~~") { return ("~~", .strikethrough) }
        // `==` opens like `~~`: never followed by a space, closed by a pair not preceded by one
        // (ADR-0087 §D2). Code spans are matched before any of these, so `` `a==b==` `` is code.
        if rest.hasPrefix("==") { return ("==", .highlight) }
        if rest.hasPrefix("*") { return ("*", .emphasis) }
        if rest.hasPrefix("_") { return ("_", .emphasis) }
        return nil
    }

    // MARK: Delimiter rules

    /// Whether a marker opens a span at all.
    ///
    /// `2 * 3 * 4` is arithmetic, not emphasis: a marker followed by a space opens
    /// nothing. Without this the parser ate both asterisks and rendered "2  3  4",
    /// which is the one thing a reading view must never do - lose the text.
    ///
    /// `_` and `__` also open nothing inside a word, CommonMark's intraword rule: `file_name_here`
    /// is a file name, not `file` *`name`* `here` (ADR-0077 §D5). `*` keeps today's rule.
    static func opensEmphasis(_ rest: Substring, marker: String, after previous: Character?) -> Bool {
        guard let next = rest.dropFirst(marker.count).first else { return false }
        if marker.hasPrefix("_"), let previous, isWordCharacter(previous) { return false }
        // `==` opens nothing before another `=`: a line of `=` (a setext underline) is no highlight, and
        // `====` would otherwise be an empty one and `======` a pill of `==` (ADR-0087 §D2).
        if marker == "==", next == "=" { return false }
        return !next.isWhitespace
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// Finds the marker that closes a span.
    ///
    /// A run longer than the marker closes at the END of the run: in
    /// `**forte con *corsivo***` the first `**` found sits inside the final `***`,
    /// and stopping there would leave a stray asterisk and lose the inner emphasis.
    ///
    /// A single marker steps over a strong run nested inside it: in
    /// `*corsivo con **forte** dentro*` the `**` pair is the inner span, and neither of its
    /// asterisks closes the outer one.
    static func closingRange(of marker: String, in haystack: Substring) -> Range<String.Index>? {
        var search = haystack
        while let found = search.range(of: marker) {
            if marker.count == 1, let nested = nestedStrongEnd(at: found.lowerBound, in: haystack) {
                search = haystack[nested...]
                continue
            }
            // A marker preceded by a space closes nothing, symmetrically with the
            // opening rule.
            if haystack[..<found.lowerBound].last?.isWhitespace == true {
                search = haystack[found.upperBound...]
                continue
            }
            guard let markerCharacter = marker.first else { return found }
            var end = found.upperBound
            while end < haystack.endIndex, haystack[end] == markerCharacter {
                end = haystack.index(after: end)
            }
            // The closing half of the intraword rule: `_lieve_mente` does not close at `_m`.
            if markerCharacter == "_", end < haystack.endIndex, isWordCharacter(haystack[end]) {
                search = haystack[end...]
                continue
            }
            guard haystack.distance(from: found.lowerBound, to: end) > marker.count else { return found }
            return haystack.index(end, offsetBy: -marker.count)..<end
        }
        return nil
    }

    /// Where a strong run opening at `start` ends, when exactly two marker characters sit there,
    /// open by `opensEmphasis`'s rule and are closed by a pair further on; nil otherwise, which
    /// leaves `closingRange` reading the characters as it always has. The pair closes at the first
    /// `**` (or `__`) not preceded by a space, so `*a **b***` keeps its last asterisk for the outer
    /// span.
    private static func nestedStrongEnd(at start: String.Index, in haystack: Substring) -> String.Index? {
        let character = haystack[start]
        let run = haystack[start...].prefix(while: { $0 == character })
        guard run.count == 2 else { return nil }
        let previous = start > haystack.startIndex ? haystack[haystack.index(before: start)] : nil
        guard opensEmphasis(haystack[start...], marker: String(run), after: previous) else { return nil }
        var search = haystack[run.endIndex...]
        while let close = search.range(of: String(run)) {
            if haystack[..<close.lowerBound].last?.isWhitespace != true { return close.upperBound }
            search = haystack[close.upperBound...]
        }
        return nil
    }
}
