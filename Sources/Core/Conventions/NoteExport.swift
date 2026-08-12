import Foundation

/// Exporting a note for someone outside the vault (SPEC §10, File › Esporta nota).
///
/// Two things are removed on the way out, because they mean nothing to the reader and
/// something to us: the frontmatter block, which is this system's bookkeeping
/// (frontmatter.md 6.3), and the `## Note correlate` section, which points at notes
/// the reader does not have (wikilink.md 6.3).
enum NoteExport {
    /// The note as markdown, ready to hand over.
    static func markdown(from text: String) -> String {
        let document = NoteDocument.parse(text)
        return strippingRelatedSection(from: document.body)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// Removes `## Note correlate` and its bullets, up to the next heading.
    private static func strippingRelatedSection(from body: String) -> String {
        guard let range = body.range(of: RelatedSection.heading) else { return body }
        let after = body[range.upperBound...]

        // The section ends at the next heading of any level, or at the end.
        var end = body.endIndex
        var cursor = after.startIndex
        while cursor < after.endIndex {
            let lineEnd = after[cursor...].firstIndex(of: "\n") ?? after.endIndex
            if after[cursor..<lineEnd].hasPrefix("#") {
                end = cursor
                break
            }
            guard lineEnd < after.endIndex else { break }
            cursor = after.index(after: lineEnd)
        }

        var result = body
        result.removeSubrange(range.lowerBound..<end)
        return result
    }

    /// The note as a standalone HTML document.
    ///
    /// A deliberately small CommonMark subset - headings, emphasis, code, lists,
    /// quotes, links, GFM tables - which is what §5 says a note may contain. Anything
    /// outside it comes through as its own text rather than as markup: an exported
    /// note that silently dropped a line would be worse than one that shows a stray
    /// asterisk.
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

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// The markdown-to-HTML conversion behind `NoteExport.html`.
enum MarkdownHTML {
    /// The blocks being accumulated while the lines are read.
    ///
    /// A type rather than a handful of local variables and nested closures: the reader
    /// of `render` should see the line-by-line decisions, not the bookkeeping each one
    /// implies.
    private struct Blocks {
        var html: [String] = []
        var listKind: String?
        var paragraph: [String] = []
        var quote: [String] = []
        var table: [[String]] = []

        mutating func closeParagraph() {
            guard !paragraph.isEmpty else { return }
            html.append("<p>\(inline(paragraph.joined(separator: " ")))</p>")
            paragraph = []
        }
        mutating func closeList() {
            guard let kind = listKind else { return }
            html.append("</\(kind)>")
            listKind = nil
        }
        mutating func closeQuote() {
            guard !quote.isEmpty else { return }
            html.append("<blockquote><p>\(inline(quote.joined(separator: " ")))</p></blockquote>")
            quote = []
        }
        mutating func closeTable() {
            guard !table.isEmpty else { return }
            var rows = table
            let head = rows.removeFirst()
            // The alignment row of a GFM table is separator, not content.
            if let second = rows.first, second.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) {
                rows.removeFirst()
            }
            var out = "<table>\n<thead><tr>"
            out += head.map { "<th>\(inline($0))</th>" }.joined()
            out += "</tr></thead>\n<tbody>"
            for row in rows {
                out += "<tr>" + row.map { "<td>\(inline($0))</td>" }.joined() + "</tr>"
            }
            out += "</tbody>\n</table>"
            html.append(out)
            table = []
        }
        mutating func closeAll() {
            closeParagraph()
            closeList()
            closeQuote()
            closeTable()
        }
    }

    static func render(_ markdown: String) -> String {
        var blocks = Blocks()
        var inCode = false
        var codeLines: [String] = []

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if inCode {
                    blocks.html.append("<pre><code>\(NoteExport.escape(codeLines.joined(separator: "\n")))</code></pre>")
                    codeLines = []
                    inCode = false
                } else {
                    blocks.closeAll()
                    inCode = true
                }
                continue
            }
            if inCode {
                codeLines.append(rawLine)
                continue
            }

            if line.isEmpty {
                blocks.closeAll()
                continue
            }

            if line.hasPrefix("#") {
                let level = min(6, line.prefix { $0 == "#" }.count)
                let content = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
                blocks.closeAll()
                blocks.html.append("<h\(level)>\(inline(content))</h\(level)>")
                continue
            }

            if line.hasPrefix("|"), line.hasSuffix("|") {
                blocks.closeParagraph()
                blocks.closeList()
                blocks.closeQuote()
                blocks.table.append(
                    line.dropFirst().dropLast()
                        .components(separatedBy: "|")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                )
                continue
            }
            blocks.closeTable()

            if line.hasPrefix("> ") || line == ">" {
                blocks.closeParagraph()
                blocks.closeList()
                blocks.quote.append(String(line.dropFirst(line == ">" ? 1 : 2)))
                continue
            }
            blocks.closeQuote()

            if let item = listItem(line) {
                blocks.closeParagraph()
                if blocks.listKind != item.kind {
                    blocks.closeList()
                    blocks.html.append("<\(item.kind)>")
                    blocks.listKind = item.kind
                }
                blocks.html.append("<li>\(inline(item.content))</li>")
                continue
            }
            blocks.closeList()

            blocks.paragraph.append(line)
        }

        if inCode, !codeLines.isEmpty {
            blocks.html.append("<pre><code>\(NoteExport.escape(codeLines.joined(separator: "\n")))</code></pre>")
        }
        blocks.closeAll()
        return blocks.html.joined(separator: "\n")
    }

    private static func listItem(_ line: String) -> (kind: String, content: String)? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            var content = String(line.dropFirst(marker.count))
            // A task list keeps its box, drawn as a character: an exported checklist
            // that lost its state would be a different document.
            if content.hasPrefix("[ ] ") {
                content = "☐ " + content.dropFirst(4)
            } else if content.lowercased().hasPrefix("[x] ") {
                content = "☑ " + content.dropFirst(4)
            }
            return ("ul", content)
        }
        // `1. `, `2. ` and so on.
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return ("ol", String(line.dropFirst(digits.count + 2)))
        }
        return nil
    }

    /// Inline markup, applied to already-escaped text.
    static func inline(_ text: String) -> String {
        var result = NoteExport.escape(text)

        // Wikilinks become their display text: the reader has no vault to resolve them
        // in, and `[[Titolo]]` on a page sent to a customer is noise.
        result = replacePairs(in: result, open: "[[", close: "]]") { inner in
            let withoutEmbed = inner
            let displayed = withoutEmbed.split(separator: "|").last.map(String.init) ?? withoutEmbed
            return displayed.split(separator: "#").first.map(String.init) ?? displayed
        }
        result = replaceCode(in: result)
        result = replaceMarkdownLinks(in: result)
        result = replacePairs(in: result, open: "**", close: "**") { "<strong>\($0)</strong>" }
        result = replacePairs(in: result, open: "*", close: "*") { "<em>\($0)</em>" }
        return result
    }

    private static func replaceCode(in text: String) -> String {
        replacePairs(in: text, open: "`", close: "`") { "<code>\($0)</code>" }
    }

    /// `[testo](url)` becomes an anchor.
    private static func replaceMarkdownLinks(in text: String) -> String {
        var result = ""
        var rest = Substring(text)

        while let open = rest.firstIndex(of: "["),
              let close = rest[open...].firstIndex(of: "]"),
              rest.index(after: close) < rest.endIndex,
              rest[rest.index(after: close)] == "(",
              let end = rest[close...].firstIndex(of: ")") {
            let label = String(rest[rest.index(after: open)..<close])
            let url = String(rest[rest.index(close, offsetBy: 2)..<end])
            result += rest[rest.startIndex..<open]
            result += "<a href=\"\(url)\">\(label)</a>"
            rest = rest[rest.index(after: end)...]
        }
        return result + rest
    }

    /// Replaces every `open … close` pair, leaving an unmatched delimiter as text.
    private static func replacePairs(
        in text: String,
        open: String,
        close: String,
        transform: (String) -> String
    ) -> String {
        var result = ""
        var rest = Substring(text)

        while let start = rest.range(of: open),
              let end = rest.range(of: close, range: start.upperBound..<rest.endIndex) {
            result += rest[rest.startIndex..<start.lowerBound]
            result += transform(String(rest[start.upperBound..<end.lowerBound]))
            rest = rest[end.upperBound...]
        }
        return result + rest
    }
}
