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
/// - Note: stub. Both functions return `[]` unconditionally so
///   `Tests/InlineSpanRevealTests.swift` compiles and fails red before the coder's task fills
///   in the real bodies (ADR-0037's plan conventions: the tester owns the interface, the coder
///   owns the body).
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
        []
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
        []
    }
}
