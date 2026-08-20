import Foundation

/// Where a note's name turns up in another note's prose without being a link (ADR-0012 D9).
///
/// The rule is narrower than "contains the title", and each narrowing is there because the
/// wider version produces a list nobody reads:
///
/// - **Whole words only.** "Curva" must not match "Curvatura". A mention is the name being
///   used, not its letters appearing in order.
/// - **Not inside a wikilink.** `[[Curva di trasmissibilità]]` is the opposite of an unlinked
///   mention, and the note holding it is already in the backlinks.
/// - **Body only.** A name in the frontmatter is metadata - an alias, a `related` entry - and
///   listing it would mean reporting the note's own bookkeeping as prose about it.
/// - **Folded**, so "trasmissibilita" finds "trasmissibilità", the same rule the search reads
///   text by.
///
/// A pure function over a string, in `Core`, so it can be checked without a vault and so both
/// connectors could offer it later without a second implementation to drift.
enum UnlinkedMentions {
    /// The first body line naming one of `names` outside a wikilink, trimmed, or nil.
    static func firstMentionLine(of names: [String], in text: String) -> String? {
        let body = NoteDocument.parse(text).body
        for line in body.components(separatedBy: "\n") where mentions(names, in: line) {
            return line.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Whether one line names any of them.
    static func mentions(_ names: [String], in line: String) -> Bool {
        // Wikilinks go first and on the original line: folding can change what a character
        // is, and the brackets have to be found before anything rewrites the text around them.
        let prose = line.replacingOccurrences(
            of: "\\[\\[[^\\]]*\\]\\]", with: " ", options: .regularExpression
        )
        let haystack = SearchQuery.fold(prose)
        return names.contains { name in
            let needle = SearchQuery.fold(name.trimmingCharacters(in: .whitespaces))
            return !needle.isEmpty && containsWholeWord(needle, in: haystack)
        }
    }

    /// `needle` in `haystack` with a non-word character on each side of it.
    private static func containsWholeWord(_ needle: String, in haystack: String) -> Bool {
        var searchFrom = haystack.startIndex
        while let found = haystack.range(of: needle, range: searchFrom..<haystack.endIndex) {
            let openedCleanly = found.lowerBound == haystack.startIndex
                || !isWord(haystack[haystack.index(before: found.lowerBound)])
            let closedCleanly = found.upperBound == haystack.endIndex
                || !isWord(haystack[found.upperBound])
            if openedCleanly, closedCleanly { return true }

            // One character on, not one match on: overlapping names exist, and skipping the
            // whole failed match would step over a good occurrence starting inside it.
            searchFrom = haystack.index(after: found.lowerBound)
            if searchFrom >= haystack.endIndex { break }
        }
        return false
    }

    private static func isWord(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
