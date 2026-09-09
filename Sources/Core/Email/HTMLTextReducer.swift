import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 2 - R-06.
//
// SPEC §14 amendment (ADR §D16): HTML *rendering* stays excluded, but reducing an
// HTML body to light markdown text is included from this chain on - the cost that
// was excluded was maintaining a rendered, styled HTML view, which a text reducer
// never has.

/// Turns an HTML email body into light markdown: paragraphs, `<br>`, ordered/
/// unordered lists, links as `[text](url)`, bold, and a regular table as a GFM table.
/// Styles, scripts, remote images and tracking pixels are dropped; a `cid:` image is
/// left as-is for the caller to resolve against a decoded inline part.
enum HTMLTextReducer {
    static func reduce(_ html: String) -> String {
        // Coder-owned: a small forgiving HTML walk (no `WebView`, no rendering - SPEC
        // §14 keeps that excluded). Stubbed to the input unchanged so a caller cannot
        // mistake "not implemented yet" for "already plain text".
        html
    }
}
