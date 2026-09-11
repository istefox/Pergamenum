import Foundation

/// What a construct is, and which one the caret is in, for word-grained reveal-on-caret
/// (ADR-0037 §D4/§D5). A pure namespace over a single paragraph's text - no delegate, no
/// `NSTextView`, no state - so `MarkupReveal.inlineSpans(in:selection:markedRange:currentMatch:)`
/// (ADR-0037 §D6) can call it once per paragraph with nothing but a `String` and a range.
///
/// `constructs` never invents its own parser (ADR-0018 §D1's rule, restated at ADR-0037 A4):
/// every extent it returns comes out of `MarkdownStyler.spans(in:)` as already merged, and
/// `MarkdownStyler.swift` itself is not edited by this chain.
///
/// Plan: `2026-09-08-word-grained-markdown-reveal-on-caret-in`, Task 1.
///
/// Pinned by `Tests/InlineSpanRevealTests.swift`, which owns the interface these two bodies
/// answer to (ADR-0037's plan conventions: the tester owns the interface, the coder the body).
enum InlineSpanReveal {
    /// Every emphasis/strikethrough/link construct in `paragraph`, as UTF-16 `NSRange`s
    /// sorted by location with duplicates removed (ADR-0037 §D4).
    ///
    /// - `.bold`/`.italic`/`.strikethrough` spans from `MarkdownStyler.spans(in:)` are kept
    ///   as-is - the whole run, delimiters included, nested runs included (PG-084).
    /// - A `.linkSyntax` span whose text starts with `[[` is a wikilink's whole run, kept
    ///   as-is.
    /// - A `.linkSyntax` span that is exactly `[` is paired with the *next* `.linkSyntax`
    ///   span starting with `](`, reconstructing the whole CommonMark `[text](url)` run that
    ///   `MarkdownStyler` never emits as a single span (ADR-0037 F2).
    static func constructs(inParagraph paragraph: String) -> [NSRange] {
        let styled = MarkdownStyler.spans(in: paragraph)
        // The `.linkSyntax` halves in source order, so a lone `[` can look forward for the
        // `](url)` that closes it without re-scanning the whole span list unsorted.
        let linkHalves = styled
            .filter { $0.span == .linkSyntax }
            .sorted { $0.range.lowerBound < $1.range.lowerBound }

        var found: [NSRange] = []
        for styledRange in styled {
            switch styledRange.span {
            case .bold, .italic, .strikethrough:
                found.append(NSRange(styledRange.range, in: paragraph))
            case .linkSyntax:
                let text = paragraph[styledRange.range]
                if text.hasPrefix("[[") {
                    // A wikilink's whole bracketed run, `![[embed]]` excluded by the prefix
                    // test: an embed is paragraph-grained (ADR-0037 §D3).
                    found.append(NSRange(styledRange.range, in: paragraph))
                } else if text == "[" {
                    // A CommonMark link, which `MarkdownStyler` only ever emits as two halves
                    // (ADR-0037 F2): join this `[` to the next `](url)` half after it.
                    guard let closing = linkHalves.first(where: {
                        $0.range.lowerBound >= styledRange.range.upperBound
                            && paragraph[$0.range].hasPrefix("](")
                    }) else { break }
                    found.append(NSRange(
                        styledRange.range.lowerBound..<closing.range.upperBound, in: paragraph
                    ))
                }
            default:
                break
            }
        }

        // Sorted by location, the outer of two runs starting together first, then deduplicated
        // - equal ranges are adjacent once sorted, so one pass over neighbours is enough.
        let sorted = found.sorted {
            $0.location == $1.location ? $0.length > $1.length : $0.location < $1.location
        }
        var unique: [NSRange] = []
        for range in sorted where unique.last != range {
            unique.append(range)
        }
        return unique
    }

    /// Which of `paragraph`'s constructs `range` reveals (ADR-0037 §D5).
    ///
    /// - `range.length == 0` (a caret at `p`): the containing spans are those with
    ///   `s ≤ p ≤ NSMaxRange(span)` - a **closed** interval, so a caret exactly at either
    ///   delimiter boundary counts as inside. Of those, only the spans of **minimum length**
    ///   are returned, ties included (R-05's innermost-wins rule).
    /// - `range.length > 0` (a selection, an IME marked range, the find bar's current
    ///   match): every span with `NSIntersectionRange(span, range).length > 0` is returned,
    ///   with **no** innermost filtering (R-04).
    ///
    /// An out-of-bounds range, or one containing `NSNotFound`, returns `[]` rather than
    /// crashing.
    static func revealed(inParagraph paragraph: String, touchedBy range: NSRange) -> [NSRange] {
        // `NSNotFound` is what a text view reports for "no selection"/"no composition"; it is
        // a sentinel, never a location to look up. The bounds test is written as a subtraction
        // so a caller's absurd length can never overflow `NSMaxRange`.
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0 else { return [] }
        let paragraphLength = (paragraph as NSString).length
        guard range.location <= paragraphLength,
              range.length <= paragraphLength - range.location else { return [] }

        let spans = constructs(inParagraph: paragraph)
        guard !spans.isEmpty else { return [] }

        // A selection (or an IME marked range, or the find bar's current match) reveals every
        // construct it touches, with no innermost filtering (R-04).
        guard range.length == 0 else {
            return spans.filter { NSIntersectionRange($0, range).length > 0 }
        }

        // A caret: closed interval on both delimiters, then innermost wins, ties included (R-05).
        let caret = range.location
        let containing = spans.filter { $0.location <= caret && caret <= NSMaxRange($0) }
        guard let innermost = containing.map(\.length).min() else { return [] }
        return containing.filter { $0.length == innermost }
    }
}
