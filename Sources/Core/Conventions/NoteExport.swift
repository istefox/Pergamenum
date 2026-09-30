import Foundation

/// Exporting a note for someone outside the vault (SPEC §10, File › Esporta nota).
///
/// Two things are removed on the way out, because they mean nothing to the reader and
/// something to us: the frontmatter block, which is this system's bookkeeping
/// (frontmatter.md 6.3), and the `## Note correlate` section, which points at notes
/// the reader does not have (wikilink.md 6.3).
enum NoteExport {
    /// The note as markdown, ready to hand over. The final line break is the note's own, so a
    /// CRLF note is not handed over mixed (ADR-0065 §D3, PG-274).
    static func markdown(from text: String) -> String {
        let document = NoteDocument.parse(text)
        return strippingRelatedSection(from: document.body)
            .trimmingCharacters(in: .whitespacesAndNewlines) + LineBreak.detected(in: text).characters
    }

    /// Removes `## Note correlate` and its bullets, up to the next heading of any level - the
    /// one locator the linter and «Collega» use too (ADR-0065 §D9.3, R-18), so a sub-heading
    /// that only contains the words stays, and a CRLF note stops at its next heading.
    private static func strippingRelatedSection(from body: String) -> String {
        guard let section = RelatedSection.sectionRange(in: body) else { return body }
        var result = body
        result.removeSubrange(section)
        return result
    }

    /// The note as a standalone HTML document.
    ///
    /// The body is the dialect the reading surfaces read, through the same parsers
    /// (`MarkdownHTML`, ADR-0077). Anything outside it comes through as its own text
    /// rather than as markup: an exported note that silently dropped a line would be
    /// worse than one that shows a stray asterisk.
    static func html(from text: String, title: String) -> String {
        let body = MarkdownHTML.render(markdown(from: text))
        return """
        <!DOCTYPE html>
        <html lang="it">
        <head>
        <meta charset="utf-8">
        <title>\(escape(title))</title>
        <style>
        body { font: 16px/1.6 -apple-system, system-ui, sans-serif; max-width: 42em;
               margin: 3em auto; padding: 0 1.5em; color: #1c1c1e; }
        h1, h2, h3 { line-height: 1.25; }
        code { font: 0.9em ui-monospace, SFMono-Regular, monospace;
               background: #f2f2f7; padding: 0.1em 0.3em; border-radius: 3px; }
        pre { background: #f2f2f7; padding: 1em; border-radius: 6px; overflow-x: auto; }
        pre code { background: none; padding: 0; }
        blockquote { margin: 0; padding-left: 1em; border-left: 3px solid #d1d1d6; color: #48484a; }
        table { border-collapse: collapse; }
        th, td { border: 1px solid #d1d1d6; padding: 0.4em 0.7em; text-align: left; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    /// Applied exactly once to every string `MarkdownHTML` takes from the note, as it is
    /// written out, and never before parsing (ADR-0077 §D2). Quotes are escaped as well as
    /// angle brackets because a link's URL goes into a quoted `href` attribute: a literal
    /// `"` there would end the attribute and let the rest of the href become markup
    /// (PG-124). `&` goes first, or it would re-escape the entities the later lines
    /// introduce.
    ///
    /// `'` becomes `&apos;`, which HTML5 defines. Nothing splits the escaped text any more,
    /// so `&#39;` would do as well; `&apos;` stays so that every exported page keeps its
    /// bytes.
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
