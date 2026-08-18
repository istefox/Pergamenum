import Foundation

/// Finding text inside one note, by literal or by regular expression (SPEC §10).
///
/// AppKit's find bar does everything else this needs and cannot do the pattern: checked
/// against MacOSX26.5.sdk rather than assumed, `NSTextFinderMatchingType` has exactly four
/// values - `Contains`, `StartsWith`, `FullWord`, `EndsWith` - and no option elsewhere on
/// the class adds a fifth. So the searching is ours, and this is it: no view, no text view,
/// nothing that cannot be answered by a test.
///
/// Foundation only, deliberately. This file is under `Sources/Core`, which both connectors
/// compile (`Project.swift`), so an `import AppKit` here breaks `perg` and `pergamenum-mcp`
/// rather than this file - ADR-0001 §D1 enforcing itself.
enum NoteFind {
    struct Query: Equatable, Sendable {
        var text: String
        /// Whether `text` is a pattern. Off, it is the characters themselves, `(` included.
        var isRegex = false
        /// Off by default, which is what a person means by typing a word in a find field.
        var isCaseSensitive = false

        init(text: String, isRegex: Bool = false, isCaseSensitive: Bool = false) {
            self.text = text
            self.isRegex = isRegex
            self.isCaseSensitive = isCaseSensitive
        }
    }

    /// What a search came back with.
    ///
    /// Three cases and not an optional array, because the bar has to tell «nessuna
    /// corrispondenza» from «pattern incompleto» in the same corner of the same line. They
    /// mean opposite things: the first is an answer, the second is a question still being
    /// typed. Collapsing them is the mistake this enum exists to make impossible.
    enum Result: Equatable, Sendable {
        /// Nothing was asked. An empty field is not a search that found nothing.
        case idle
        /// Every match, in document order, absolute to the whole text even when the search
        /// was scoped. Empty is «nessuna corrispondenza».
        case matches([NSRange])
        /// A pattern the regex engine will not accept - `\b(\d{4` on the way to `\b(\d{4})`.
        case invalidPattern

        var ranges: [NSRange] {
            if case let .matches(ranges) = self { return ranges }
            return []
        }
    }

    /// Every match of `query` in `text`, optionally confined to `scope`.
    static func run(_ query: Query, in text: String, within scope: NSRange? = nil) -> Result {
        guard !query.text.isEmpty else { return .idle }
        let haystack = text as NSString
        let whole = NSRange(location: 0, length: haystack.length)
        // Clamped rather than trusted: the scope is a selection captured when the bar
        // opened, and the note may have been edited since.
        let searched = scope.map { NSIntersectionRange($0, whole) } ?? whole
        guard searched.length > 0 else { return .matches([]) }

        return query.isRegex
            ? regexMatches(query, in: haystack, within: searched)
            : literalMatches(query, in: haystack, within: searched)
    }

    private static func literalMatches(
        _ query: Query, in haystack: NSString, within searched: NSRange
    ) -> Result {
        var options: NSString.CompareOptions = [.literal]
        if !query.isCaseSensitive { options.insert(.caseInsensitive) }

        var found: [NSRange] = []
        var cursor = searched
        while cursor.length > 0 {
            let match = haystack.range(of: query.text, options: options, range: cursor)
            guard match.location != NSNotFound else { break }
            found.append(match)
            // Past the whole match, so `aa` in `aaaa` is two matches and not three: an
            // overlapping second one cannot be replaced without eating the first.
            let next = NSMaxRange(match)
            cursor = NSRange(location: next, length: NSMaxRange(searched) - next)
        }
        return .matches(found)
    }

    private static func regexMatches(
        _ query: Query, in haystack: NSString, within searched: NSRange
    ) -> Result {
        guard let expression = expression(for: query) else { return .invalidPattern }
        let found = expression
            .matches(in: haystack as String, range: searched)
            .map(\.range)
            // Zero-length matches dropped, and this is not tidiness. `a*` and `\b` match
            // the empty string at every position, so kept they make the count meaningless,
            // leave the stepper with nowhere to step, and turn replace-all into a loop that
            // inserts the template between every pair of characters for ever.
            .filter { $0.length > 0 }
        return .matches(found)
    }

    /// What one match is replaced by.
    ///
    /// `$1` expands only under the regex option. A literal search that hits `$1` in the
    /// replacement field means the two characters, because a person who did not turn on
    /// patterns is not writing one - and `NSRegularExpression`'s template syntax would
    /// silently eat them.
    static func replacement(
        for query: Query, matching range: NSRange, in text: String, template: String
    ) -> String {
        guard query.isRegex, let expression = expression(for: query) else { return template }
        let haystack = text as NSString
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: haystack.length))
        guard clamped.length > 0 else { return template }
        // Over the match alone, so the offset the template's groups resolve against is this
        // match's and not the document's.
        return expression.stringByReplacingMatches(
            in: haystack.substring(with: clamped), range: NSRange(location: 0, length: clamped.length),
            withTemplate: template
        )
    }

    private static func expression(for query: Query) -> NSRegularExpression? {
        var options: NSRegularExpression.Options = []
        if !query.isCaseSensitive { options.insert(.caseInsensitive) }
        return try? NSRegularExpression(pattern: query.text, options: options)
    }
}
