import Foundation

/// A parsed global-search query (SPEC §12, ADR-0012 D8).
///
/// Supports `tag:`, `path:`, `task:open`, `regex:`, `modified:`, `is:starred`, `linked:`,
/// `orphan:`, `"frase esatta"` and bare words, any of which can be negated with a leading
/// `-`. Everything is ANDed: a search that widened as you added terms would be useless for
/// narrowing down, which is what search is for.
///
/// Parsing only. Three of the operators cannot be answered by a note on its own - `is:starred`
/// reads the store of ADR-0012 D6, `linked:` and `orphan:` read the link graph - so they are
/// recorded here and applied by `VaultSession.search`, which has both. Everything else is
/// decided by `SearchQuery.Matcher` against the note's own record and text.
struct SearchQuery: Equatable, Sendable {
    /// Bare words, matched case- and accent-insensitively anywhere in the note.
    var words: [String] = []
    /// Quoted phrases, matched as a contiguous run.
    var phrases: [String] = []
    /// `tag:type-note`, matched against the note's frontmatter and inline tags.
    var tags: [String] = []
    /// `path:01 Progetti`, matched as a substring of the note's path.
    var paths: [String] = []
    /// `task:open` or `task:done`.
    var taskState: TaskItem.State?

    /// `-parola`, `-"frase"`, `-tag:x`, `-path:x`: a note carrying any of these is out.
    var negatedWords: [String] = []
    var negatedPhrases: [String] = []
    var negatedTags: [String] = []
    var negatedPaths: [String] = []

    /// `regex:` patterns, kept in the spelling they were typed. Lowercasing them would
    /// rewrite the pattern itself - `\S` and `\s` are opposites - even though the match
    /// is case-insensitive.
    var patterns: [String] = []
    var negatedPatterns: [String] = []
    /// Patterns that do not compile, reported to the user. A query holding one matches
    /// **nothing**: quietly matching everything is the failure that makes a search
    /// untrustworthy, because the results look like an answer.
    var invalidPatterns: [String] = []

    /// `modified:` bounds, intersected when the operator appears more than once.
    var modified: DateFilter?
    /// `is:starred` (ADR-0012 D6).
    var starredOnly = false
    /// `linked:Titolo`, resolved against the link graph in both directions.
    var linkedTo: [String] = []
    /// `orphan:`, meaning no link in and no link out.
    var orphansOnly = false

    /// True when the query asks for nothing, which should list everything rather than
    /// nothing.
    var isEmpty: Bool {
        words.isEmpty && phrases.isEmpty && tags.isEmpty && paths.isEmpty && taskState == nil
            && negatedWords.isEmpty && negatedPhrases.isEmpty && negatedTags.isEmpty
            && negatedPaths.isEmpty
            && patterns.isEmpty && negatedPatterns.isEmpty && invalidPatterns.isEmpty
            && modified == nil && !starredOnly && linkedTo.isEmpty && !orphansOnly
    }

    /// The operators that need the vault rather than the note: `VaultSession.search`
    /// narrows on these before reading a single file.
    var needsVaultContext: Bool {
        starredOnly || orphansOnly || !linkedTo.isEmpty
    }

    // MARK: Dates

    /// A `modified:` constraint, as inclusive day bounds.
    ///
    /// `>` and `<` are read as "on or after" and "on or before" on purpose. The strict
    /// reading would need the day before or after a date, which is calendar arithmetic
    /// inside a value type, and nobody typing `modified:>2026-08-01` means to exclude
    /// what was touched that morning.
    struct DateFilter: Equatable, Sendable {
        var from: CalendarDate?
        var to: CalendarDate?

        /// Parses `>2026-08-01`, `>=…`, `<…`, `<=…`, `2026-08-01..2026-08-19` and a bare
        /// `2026-08-01`. Returns nil for anything else, which drops the operator rather
        /// than filtering on a date nobody wrote.
        init?(_ raw: String) {
            let value = raw.trimmingCharacters(in: .whitespaces)
            if let range = value.range(of: "..") {
                guard let start = CalendarDate(iso: String(value[value.startIndex..<range.lowerBound])),
                      let end = CalendarDate(iso: String(value[range.upperBound...]))
                else { return nil }
                from = min(start, end)
                to = max(start, end)
            } else if value.hasPrefix(">") {
                guard let day = CalendarDate(iso: Self.afterComparator(in: value)) else { return nil }
                from = day
            } else if value.hasPrefix("<") {
                guard let day = CalendarDate(iso: Self.afterComparator(in: value)) else { return nil }
                to = day
            } else {
                guard let day = CalendarDate(iso: value) else { return nil }
                from = day
                to = day
            }
        }

        private init(from: CalendarDate?, to: CalendarDate?) {
            self.from = from
            self.to = to
        }

        /// What follows `>`, `<`, `>=` or `<=`.
        private static func afterComparator(in value: String) -> String {
            let rest = value.dropFirst()
            return String(rest.hasPrefix("=") ? rest.dropFirst() : rest)
        }

        func admits(_ day: CalendarDate) -> Bool {
            if let from, day < from { return false }
            if let to, to < day { return false }
            return true
        }

        /// The tighter of two constraints, because two `modified:` in one query read as
        /// an AND like everything else here.
        func intersected(with other: DateFilter) -> DateFilter {
            DateFilter(
                from: [from, other.from].compactMap { $0 }.max(),
                to: [to, other.to].compactMap { $0 }.min()
            )
        }
    }

    // MARK: Parsing

    init(_ raw: String) {
        for token in SearchQuery.tokenise(raw) {
            switch token.kind {
            case .phrase:
                let value = token.value.lowercased()
                if token.isNegated { negatedPhrases.append(value) } else { phrases.append(value) }
            case .word:
                parse(token)
            }
        }
    }

    /// The three operators that read the same negated as they do plain, then everything
    /// else - which only has a plain reading.
    private mutating func parse(_ token: Token) {
        let lower = token.value.lowercased()

        if let rest = lower.dropPrefixIfPresent("tag:") {
            // Accepts `tag:#type-note` too: the hash is how a tag is written in the body,
            // and typing it should not make the filter miss.
            let tag = String(rest.drop(while: { $0 == "#" }))
            return append(tag, to: &tags, or: &negatedTags, negated: token.isNegated)
        }
        if let rest = lower.dropPrefixIfPresent("path:") {
            return append(String(rest), to: &paths, or: &negatedPaths, negated: token.isNegated)
        }
        if lower.hasPrefix("regex:") {
            return parseRegex(String(token.value.dropFirst("regex:".count)), negated: token.isNegated)
        }
        // What is left has no negated reading worth guessing: deciding what `-orphan:` or
        // `-modified:2026-08-01` means is a decision, not a default. A `-` in front of one
        // of them makes it the literal text it looks like, which is what an unknown
        // `foo:bar` already becomes.
        guard !token.isNegated else { return negatedWords.append(lower) }
        parseUnnegated(lower)
    }

    private mutating func parseRegex(_ pattern: String, negated: Bool) {
        guard !pattern.isEmpty else { return }
        guard (try? NSRegularExpression(pattern: pattern)) != nil else {
            return invalidPatterns.append(pattern)
        }
        append(pattern, to: &patterns, or: &negatedPatterns, negated: negated)
    }

    private mutating func parseUnnegated(_ lower: String) {
        if let rest = lower.dropPrefixIfPresent("modified:") {
            guard let filter = DateFilter(String(rest)) else { return }
            modified = modified?.intersected(with: filter) ?? filter
        } else if let rest = lower.dropPrefixIfPresent("linked:"), !rest.isEmpty {
            linkedTo.append(String(rest))
        } else if lower == "orphan:" || lower == "is:orphan" {
            orphansOnly = true
        } else if lower == "is:starred" {
            starredOnly = true
        } else if let rest = lower.dropPrefixIfPresent("task:") {
            switch rest {
            case "open": taskState = .open
            case "done": taskState = .done
            default: break
            }
        } else if !lower.isEmpty {
            words.append(lower)
        }
    }

    private func append(
        _ value: String, to wanted: inout [String], or unwanted: inout [String], negated: Bool
    ) {
        guard !value.isEmpty else { return }
        if negated { unwanted.append(value) } else { wanted.append(value) }
    }

    private struct Token {
        enum Kind { case word, phrase }
        var kind: Kind
        var value: String
        var isNegated: Bool
    }

    /// Splits on whitespace, keeping quoted runs together and taking off a leading `-`.
    private static func tokenise(_ raw: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var inQuotes = false
        /// True while inside a quote that belongs to an operator (`path:"01 Progetti"`).
        /// Its closing quote must not turn the token into a phrase.
        var quotedOperator = false
        /// Set when a `-` was consumed just before an opening quote, so `-"frase"` reaches
        /// the closing quote still knowing it was a negation.
        var pendingNegation = false

        func flush(asPhrase: Bool) {
            var value = current.trimmingCharacters(in: .whitespaces)
            current = ""
            var isNegated = pendingNegation
            pendingNegation = false
            if !asPhrase, value.hasPrefix("-"), value.count > 1 {
                isNegated = true
                value.removeFirst()
            }
            guard !value.isEmpty else { return }
            tokens.append(Token(kind: asPhrase ? .phrase : .word, value: value, isNegated: isNegated))
        }

        for character in raw {
            if character == "\"" {
                // A quote right after an operator belongs to it: the folders in this
                // vault are called "01 Progetti", so `path:` without quoting would
                // split on the space and search for the wrong thing.
                if current.hasSuffix(":") {
                    inQuotes = true
                    quotedOperator = true
                    continue
                }
                if quotedOperator {
                    inQuotes = false
                    quotedOperator = false
                    continue
                }
                let negatesPhrase = !inQuotes && current == "-"
                if negatesPhrase { current = "" }
                flush(asPhrase: inQuotes)
                if negatesPhrase { pendingNegation = true }
                inQuotes.toggle()
                continue
            }
            if character == " ", !inQuotes {
                flush(asPhrase: false)
                continue
            }
            current.append(character)
        }
        // An unclosed quote is still a phrase: the user typed a run they want kept
        // together, and dropping it or splitting it would search for something else.
        flush(asPhrase: inQuotes)
        return tokens
    }

    /// Lowercased and accent-folded, so "trasmissibilita" finds "trasmissibilità".
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "it_IT"))
    }
}

private extension String {
    /// The remainder after a prefix, or nil when the prefix is absent.
    func dropPrefixIfPresent(_ prefix: String) -> Substring? {
        hasPrefix(prefix) ? dropFirst(prefix.count) : nil
    }
}
