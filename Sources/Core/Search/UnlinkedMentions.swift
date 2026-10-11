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
/// - **Not inside code** (ADR-0084 §D3). A name in a fenced block or an inline code span is not
///   a mention: «Collega» would write `[[…]]` into code.
/// - **Not inside a web link** (ADR-0084 §D3). A name in a markdown link, label or URL, images
///   included, or in a bare `http(s)://` or `www.` address is not a mention: a `[[…]]` written
///   there would break the link.
/// - **Not inside a tag or an annotation** (ADR-0084 §D3). A name in an inline `#tag` or an
///   `@annotation(…)` is not a mention: `#client-[[Rossi|rossi]]` is no longer a tag.
///
/// A pure function over a string, in `Core`, so it can be checked without a vault and so both
/// connectors could offer it later without a second implementation to drift.
enum UnlinkedMentions {
    /// The first mention of a name: where it sits in the original text (UTF-16, the unit the
    /// editor and `MentionLink.rewrite` use), the text it matched, and its trimmed line
    /// (ADR-0084 §D3).
    struct Mention: Equatable, Sendable {
        let range: NSRange
        let matched: String
        let line: String
    }

    /// The earliest mention of any of `names` in the body, matched on the original text.
    ///
    /// The scan's rule - case and diacritic insensitive, whole words, outside wikilinks, body
    /// only - with ADR-0084 §D3's narrowings: **a name inside fenced or inline code, a web link, a
    /// `#tag` or an `@annotation(…)` is not a mention**, since writing `[[…]]` there would change
    /// code or break the markup. Two names starting at one place give the longer match.
    static func firstMention(of names: [String], in text: String) -> Mention? {
        let body = NoteDocument.parse(text).body
        let needles = names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // No name in the body at all, under `firstWholeWord`'s own matching: nothing to exclude.
        guard needles.contains(where: {
            body.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }) else { return nil }

        // Both code rules, because they disagree: `codeRanges` is the link parser's (``` or ~~~,
        // closed only by a bare delimiter), `CodeFence` is what the editor and the reading view
        // draw as code (``` only, closed by any ``` line). A name either one calls code is skipped.
        let excluded = WikilinkParser.links(in: body).map(\.range)
            + WikilinkParser.codeRanges(in: body)
            + CodeFence.regions(in: body).map(\.range)
            + inlineRanges(in: body)

        var best: Range<String.Index>?
        for needle in needles {
            guard let found = firstWholeWord(needle, in: body, outside: excluded) else { continue }
            if let current = best,
               current.lowerBound < found.lowerBound
                || (current.lowerBound == found.lowerBound && current.upperBound >= found.upperBound) {
                continue
            }
            best = found
        }
        guard let best else { return nil }

        // The body is the text's verbatim suffix, so the range moves by the frontmatter's length.
        let offset = text.utf16.count - body.utf16.count
        let local = NSRange(best, in: body)
        let lineStart = body[..<best.lowerBound].lastIndex(where: LineBreak.isTerminator)
            .map { body.index(after: $0) } ?? body.startIndex
        let lineEnd = body[best.lowerBound...].firstIndex(where: LineBreak.isTerminator) ?? body.endIndex
        return Mention(
            range: NSRange(location: local.location + offset, length: local.length),
            matched: String(body[best]),
            line: body[lineStart..<lineEnd].trimmingCharacters(in: .whitespaces)
        )
    }

    /// A bare `http(s)://` or `www.` address, up to the next whitespace.
    private static let bareURL = try? NSRegularExpression(
        pattern: #"(?:https?://|www\.)\S+"#, options: [.caseInsensitive]
    )

    /// Where `body` is inline markup a `[[…]]` would break: every `[label](url)` the inline parser
    /// finds (a name in the label or in the URL is not prose), every `#tag` and `@annotation(…)` it
    /// finds (`#client-[[Rossi|rossi]]` is no longer a tag), and every bare address. The parser
    /// reads a line at a time, as the editor's styler feeds it.
    private static func inlineRanges(in body: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var lineStart = body.startIndex
        while lineStart < body.endIndex {
            let lineEnd = body[lineStart...].firstIndex(where: LineBreak.isTerminator) ?? body.endIndex
            let line = body[lineStart..<lineEnd]
            if line.contains("](") || line.contains("#") || line.contains("@") {
                for token in MarkdownInlineParser.tokens(in: line) {
                    switch token.kind {
                    case .link, .tag, .annotation: ranges.append(token.range)
                    default: break
                    }
                }
            }
            lineStart = lineEnd < body.endIndex ? body.index(after: lineEnd) : body.endIndex
        }
        if let bareURL {
            let whole = NSRange(body.startIndex..., in: body)
            for match in bareURL.matches(in: body, range: whole) {
                if let range = Range(match.range, in: body) { ranges.append(range) }
            }
        }
        return ranges
    }

    /// The first hit of `needle` in `text` with no letter or digit on either side and touching
    /// none of `excluded`, widened to whole characters (a decomposed accent belongs to its letter).
    private static func firstWholeWord(
        _ needle: String, in text: String, outside excluded: [Range<String.Index>]
    ) -> Range<String.Index>? {
        var searchFrom = text.startIndex
        while searchFrom < text.endIndex,
              let hit = text.range(
                  of: needle, options: [.caseInsensitive, .diacriticInsensitive],
                  range: searchFrom..<text.endIndex
              ) {
            let lower = text.rangeOfComposedCharacterSequence(at: hit.lowerBound).lowerBound
            var upper = hit.upperBound
            if upper < text.endIndex {
                let composed = text.rangeOfComposedCharacterSequence(at: upper)
                if composed.lowerBound < upper { upper = composed.upperBound }
            }
            let match = lower..<upper
            let openedCleanly = lower == text.startIndex || !isWord(text[text.index(before: lower)])
            let closedCleanly = upper == text.endIndex || !isWord(text[upper])
            if openedCleanly, closedCleanly, !excluded.contains(where: { $0.overlaps(match) }) {
                return match
            }
            // One character on, not one match on: overlapping names exist.
            searchFrom = text.index(after: lower)
        }
        return nil
    }

    /// The line of the first mention of `names`, trimmed, or nil: `firstMention`'s line, so for a
    /// title one note carries the inspector lists exactly the mentions «Collega» can link (ADR-0084
    /// §D3). For a title several notes share it does not: the inspector passes the subject's own
    /// aliases while «Collega» drops them, so an alias-only row answers `.noMention`.
    static func firstMentionLine(of names: [String], in text: String) -> String? {
        firstMention(of: names, in: text)?.line
    }

    /// Whether one line names any of them.
    ///
    /// No production caller since `firstMentionLine` reads through `firstMention` (ADR-0084 §D3):
    /// kept, with `containsWholeWord`, as the scan's independent oracle for the tests
    /// (`SearchTests`, `MentionLinkTests`). Not a live path; do not route a feature through it.
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
