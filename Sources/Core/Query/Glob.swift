import Foundation

/// The wildcard matching `tag()` and `path()` use in a view (ADR-0009 §D3).
///
/// Two metacharacters and no others: `*` stands for any run of characters including
/// none, `?` for exactly one. No character classes, no `**`, no escaping, and above all
/// no regular expressions - §D3 refuses those here because a regex over a hundred notes
/// is the global search's job and M10 already gave it one.
///
/// Matching is folded the way search is (`SearchQuery.fold`), so an accent or a capital
/// in a folder name does not decide whether a view has any rows.
enum Glob {
    /// Whether a pattern matches a whole candidate string.
    ///
    /// Iterative with a single backtracking point rather than recursive: a pattern is
    /// short but a path is not, and `a*a*a*` against a long path is the case that turns
    /// the recursive version into a pause.
    static func matches(_ pattern: String, _ candidate: String) -> Bool {
        let pattern = Array(SearchQuery.fold(pattern))
        let text = Array(SearchQuery.fold(candidate))

        var patternIndex = 0, textIndex = 0
        // Where to resume if the `*` we last passed turns out to have swallowed too little.
        var starIndex: Int?
        var resumeIndex = 0

        while textIndex < text.count {
            if patternIndex < pattern.count,
               pattern[patternIndex] == "?" || pattern[patternIndex] == text[textIndex] {
                patternIndex += 1
                textIndex += 1
            } else if patternIndex < pattern.count, pattern[patternIndex] == "*" {
                starIndex = patternIndex
                resumeIndex = textIndex
                patternIndex += 1
            } else if let star = starIndex {
                patternIndex = star + 1
                resumeIndex += 1
                textIndex = resumeIndex
            } else {
                return false
            }
        }

        while patternIndex < pattern.count, pattern[patternIndex] == "*" { patternIndex += 1 }
        return patternIndex == pattern.count
    }

    /// True when a pattern carries a wildcard at all.
    ///
    /// The two callers read it in opposite directions, which is why it is a question and
    /// not a rule: `tag("status-aperto")` without one means *that* tag exactly, while
    /// `path("Clienti")` without one means that folder and everything under it. A prefix
    /// rule for tags would make `tag("status-a")` quietly take `status-aperto`, and an
    /// exact rule for paths would make the roadmap's own example match nothing.
    static func isPattern(_ pattern: String) -> Bool {
        pattern.contains("*") || pattern.contains("?")
    }

    /// `tag()`: exact when the pattern has no wildcard, glob when it has one.
    static func matchesTag(_ pattern: String, _ tag: String) -> Bool {
        isPattern(pattern) ? matches(pattern, tag) : SearchQuery.fold(pattern) == SearchQuery.fold(tag)
    }

    /// `path()`: a prefix of the vault-relative path when the pattern has no wildcard,
    /// a glob over the whole path when it has one.
    static func matchesPath(_ pattern: String, _ path: String) -> Bool {
        isPattern(pattern) ? matches(pattern, path) : SearchQuery.fold(path).hasPrefix(SearchQuery.fold(pattern))
    }
}
