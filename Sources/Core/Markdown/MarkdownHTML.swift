import Foundation

/// The markdown-to-HTML conversion behind `NoteExport.html` (ADR-0077).
///
/// It recognises nothing itself. The blocks come from `MarkdownBlockParser` and the runs inside
/// them from `MarkdownInlineParser`, the two parsers every reading surface reads (ADR-0018 §D1,
/// ADR-0029 §D10), so a dialect change reaches the export with no edit here. A defect the export
/// inherits from them is fixed in them, never worked around here (§D5).
///
/// Two rules carry the export's security properties (PG-124), and neither is visible from a
/// single line of this file:
///
/// - every string taken from the note goes through `NoteExport.escape` exactly once, as it is
///   written out; the only unescaped output is this file's own markup (§D2);
/// - the element set is closed and names no resource (§D4). The PDF path hands this HTML to
///   `NSAttributedString(html:)`, and a resource named there is a load it may attempt: a network
///   call out of note content. Embeds therefore export as their name, never as an `<img>`.
enum MarkdownHTML {
    static func render(_ markdown: String) -> String {
        MarkdownBlockParser.blocks(in: markdown).map(html(for:)).joined(separator: "\n")
    }

    /// One paragraph's inline markup, escaped.
    static func inline(_ text: String) -> String {
        var html = ""
        var spans = MarkdownInlineParser.spans(in: text)[...]
        while let first = spans.first {
            guard case .url(let target)? = first.link else {
                html += Self.html(for: first)
                spans = spans.dropFirst()
                continue
            }
            // Consecutive spans of one link share one anchor: `[a **b**](url)` is one link.
            let run = spans.prefix { $0.link == first.link }
            spans = spans.dropFirst(run.count)
            let content = run.map(Self.html(for:)).joined()
            // The raw target is asked, then escaped into the attribute: escaping touches only
            // `&<>"'`, none of which can be part of an openable scheme (§D3).
            html += LinkPolicy.isOpenable(target)
                ? "<a href=\"\(NoteExport.escape(target))\">\(content)</a>"
                : content
        }
        return html
    }

    // MARK: Blocks

    private static func html(for block: MarkdownBlock) -> String {
        switch block {
        case .heading(let level, let text):
            "<h\(level)>\(inline(text))</h\(level)>"
        case .paragraph(let text):
            "<p>\(inline(joined(text.components(separatedBy: "\n"))))</p>"
        case .bulletList(let items), .numberedList(let items):
            // `<ol>` starts at 1: the parser keeps no first number, and neither did the export.
            list(block == .bulletList(items) ? "ul" : "ol", items.map(inline))
        case .tasks(let tasks):
            list("ul", tasks.map { "\(glyph(for: $0.marker)) \(inline($0.text))" })
        case .quote(let lines):
            "<blockquote><p>\(inline(joined(lines)))</p></blockquote>"
        case .code(_, let lines):
            // No language class, `pergamenum-view` included: a fence exports as its text (§D6).
            "<pre><code>\(NoteExport.escape(lines.joined(separator: "\n")))</code></pre>"
        case .rule:
            "<hr>"
        case .table(let table):
            html(for: table)
        case .embed(let target, let alt):
            "<p>\(NoteExport.escape(alt ?? target))</p>"
        case .transclusion(let reference, _):
            "<p>\(NoteExport.escape(reference))</p>"
        }
    }

    /// A paragraph's or a quote's lines, trimmed and joined by one space (§D6).
    private static func joined(_ lines: [String]) -> String {
        lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

    private static func list(_ tag: String, _ items: [String]) -> String {
        (["<\(tag)>"] + items.map { "<li>\($0)</li>" } + ["</\(tag)>"]).joined(separator: "\n")
    }

    /// A task keeps its box, drawn as a character: an exported checklist that lost its state
    /// would be a different document. Done text is not struck (§D6).
    private static func glyph(for marker: Character) -> String {
        switch marker {
        case "x", "X": "☑"
        case "-": "⊟"
        case ">": "▷"
        default: "☐"
        }
    }

    private static func html(for table: MarkdownBlock.Table) -> String {
        func row(_ cells: [String], _ tag: String) -> String {
            let html = zip(cells, table.alignments).map { cell, alignment in
                "<\(tag)\(attribute(for: alignment))>\(inline(cell))</\(tag)>"
            }
            return "<tr>\(html.joined())</tr>"
        }
        return "<table>\n<thead>\(row(table.header, "th"))</thead>\n"
            + "<tbody>\(table.rows.map { row($0, "td") }.joined())</tbody>\n</table>"
    }

    /// One of two fixed values, or nothing for a leading column, so a default table's bytes do
    /// not change (§D4).
    private static func attribute(for alignment: MarkdownBlock.Table.Column) -> String {
        switch alignment {
        case .leading: ""
        case .center: " style=\"text-align: center\""
        case .trailing: " style=\"text-align: right\""
        }
    }

    // MARK: Spans

    /// Styles wrap inside to outside as `code`, `del`, `em`, `strong`, so a run is always
    /// well-formed however its styles combine.
    private static func html(for span: MarkdownSpan) -> String {
        var html = NoteExport.escape(displayed(span))
        for (style, tag) in [(MarkdownSpan.Style.code, "code"), (.strikethrough, "del"), (.emphasis, "em"),
                             (.strong, "strong")] where span.styles.contains(style) {
            html = "<\(tag)>\(html)</\(tag)>"
        }
        return html
    }

    /// What a span shows. A note link is text, since the reader has no vault to resolve it in:
    /// its alias when it has one, otherwise its title up to the first `#` (§D3). The parser puts
    /// the alias in the span's text, the title itself when there is none, and `""` for
    /// `[[Nota|]]`, so "has one" means a text that is not empty and not the title.
    private static func displayed(_ span: MarkdownSpan) -> String {
        guard case .note(let title)? = span.link else { return span.text }
        if !span.text.isEmpty, span.text != title { return span.text }
        return String(title.prefix { $0 != "#" })
    }
}
