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
        var walk = HTMLWalk()
        for token in HTMLTokenizer.tokens(of: html) { walk.consume(token) }
        return walk.finished()
    }
}

// MARK: - Tokenizer

private enum HTMLToken {
    case text(String)
    case open(name: String, attributes: [String: String])
    case close(name: String)
}

/// Deliberately forgiving: an unclosed tag, an unknown element and a stray `<` are all
/// ordinary in email HTML, and a strict parser would return nothing for a message a
/// person can plainly read. Never a `WebView`: SPEC §14 keeps *rendering* excluded, and
/// this stays a text transform (ADR §D16).
private enum HTMLTokenizer {
    static func tokens(of html: String) -> [HTMLToken] {
        let characters = Array(html)
        var tokens: [HTMLToken] = []
        var text = ""
        var index = 0

        func flush() {
            if !text.isEmpty {
                tokens.append(.text(text))
                text = ""
            }
        }

        while index < characters.count {
            guard characters[index] == "<" else {
                text.append(characters[index])
                index += 1
                continue
            }
            // `<!-- … -->`, `<!DOCTYPE …>`: dropped whole, comments first because their
            // body may contain a `>` of its own.
            if index + 1 < characters.count, characters[index + 1] == "!" {
                if matches("<!--", at: index, in: characters) {
                    index = end(of: "-->", from: index, in: characters)
                } else {
                    index = end(of: ">", from: index, in: characters)
                }
                continue
            }
            guard let closing = firstIndex(of: ">", from: index, in: characters) else {
                text.append(characters[index])
                index += 1
                continue
            }
            let raw = String(characters[(index + 1)..<closing])
            index = closing + 1
            flush()

            if raw.hasPrefix("/") {
                tokens.append(.close(name: elementName(of: String(raw.dropFirst()))))
                continue
            }
            let name = elementName(of: raw)
            // A stylesheet and a script are not text: their content is skipped at the
            // tokenizer, so no later stage has to remember to ignore it.
            if name == "style" || name == "script" {
                index = end(of: "</\(name)", from: index, in: characters)
                index = end(of: ">", from: index - 1, in: characters)
                continue
            }
            tokens.append(.open(name: name, attributes: attributes(of: raw)))
        }
        flush()
        return tokens
    }

    private static func elementName(of raw: String) -> String {
        String(raw.prefix { !$0.isWhitespace && $0 != "/" }).lowercased()
    }

    private static func attributes(of raw: String) -> [String: String] {
        var attributes: [String: String] = [:]
        let characters = Array(raw)
        var index = 0
        // Past the element name.
        while index < characters.count, !characters[index].isWhitespace { index += 1 }

        while index < characters.count {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
            var name = ""
            while index < characters.count, !characters[index].isWhitespace,
                  characters[index] != "=", characters[index] != "/" {
                name.append(characters[index])
                index += 1
            }
            guard !name.isEmpty else {
                index += 1
                continue
            }
            while index < characters.count, characters[index].isWhitespace { index += 1 }
            guard index < characters.count, characters[index] == "=" else {
                attributes[name.lowercased()] = ""
                continue
            }
            index += 1
            while index < characters.count, characters[index].isWhitespace { index += 1 }
            var value = ""
            if index < characters.count, characters[index] == "\"" || characters[index] == "'" {
                let quote = characters[index]
                index += 1
                while index < characters.count, characters[index] != quote {
                    value.append(characters[index])
                    index += 1
                }
                index += 1
            } else {
                while index < characters.count, !characters[index].isWhitespace {
                    value.append(characters[index])
                    index += 1
                }
            }
            attributes[name.lowercased()] = HTMLEntities.decode(value)
        }
        return attributes
    }

    /// Case-insensitive on purpose: this backs `end(of:)`'s search for a `</style`/
    /// `</script` closing tag (§the walk, `name == "style" || name == "script"`), and
    /// HTML element and comment/bracket tokens are case-insensitive by spec - a
    /// `</STYLE>` sent by a real mail client discarded the rest of the body when this
    /// compared case-sensitively, since the search then ran to end-of-text.
    private static func matches(_ needle: String, at index: Int, in characters: [Character]) -> Bool {
        let needleCharacters = Array(needle)
        guard index + needleCharacters.count <= characters.count else { return false }
        return zip(characters[index..<(index + needleCharacters.count)], needleCharacters)
            .allSatisfy { $0.lowercased() == $1.lowercased() }
    }

    private static func firstIndex(of character: Character, from index: Int, in characters: [Character]) -> Int? {
        var cursor = index
        while cursor < characters.count {
            if characters[cursor] == character { return cursor }
            cursor += 1
        }
        return nil
    }

    /// The index just past `needle`, or the end of the input when it never appears -
    /// an unterminated comment eats the rest, which is what a browser does too.
    private static func end(of needle: String, from index: Int, in characters: [Character]) -> Int {
        var cursor = max(index, 0)
        while cursor < characters.count {
            if matches(needle, at: cursor, in: characters) { return cursor + needle.count }
            cursor += 1
        }
        return characters.count
    }
}

// MARK: - The walk

/// Accumulates markdown into a stack of buffers: the bottom one is the document, and a
/// link's text or a table cell's content pushes its own, so nesting (a link inside a
/// cell, bold inside a link) needs no special case.
private struct HTMLWalk {
    private var buffers: [String] = [""]
    /// The element that pushed each buffer above the document's (`a`, `td`, `th`), so a buffer
    /// still open at the end of input can be closed the way its own close tag would.
    private var owners: [String] = []
    private var hrefs: [String] = []
    private var lists: [(ordered: Bool, index: Int)] = []
    private var tables: [[[String]]] = []

    mutating func consume(_ token: HTMLToken) {
        switch token {
        case .text(let raw):
            append(HTMLEntities.decode(raw).collapsedWhitespace)
        case .open(let name, let attributes):
            open(name, attributes)
        case .close(let name):
            close(name)
        }
    }

    func finished() -> String {
        // One pass over the body instead of a rescan of the whole string per collapsed
        // triple: the loop this replaces shortened every run of three or more newlines to
        // exactly two, one newline at a time, which is what keeping the first two of each
        // run does in a single sweep.
        //
        // The run is counted in **Characters**, not in code units, because that is what the
        // old loop compared: `"\r\n"` is one Character and never equals `"\n"`, so a CRLF
        // breaks a run here exactly as it did before. A `\n{3,}` regex would instead count
        // the CRLF's own line feed and eat one newline too many.
        let document = drained().buffers[0]
        var text = ""
        text.reserveCapacity(document.count)
        var consecutiveNewlines = 0
        for character in document {
            if character == "\n" {
                consecutiveNewlines += 1
                if consecutiveNewlines <= 2 { text.append(character) }
            } else {
                consecutiveNewlines = 0
                text.append(character)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Elements

    private mutating func open(_ name: String, _ attributes: [String: String]) {
        switch name {
        case "br":
            breakLine()
        case "p", "div", "blockquote", "section", "hr":
            breakParagraph()
        case "b", "strong":
            append("**")
        case "i", "em":
            append("*")
        case "a":
            hrefs.append(attributes["href"] ?? "")
            pushBuffer(for: name)
        case "ul", "ol":
            breakParagraph()
            lists.append((ordered: name == "ol", index: 0))
        case "li":
            breakLine()
            if !lists.isEmpty {
                lists[lists.count - 1].index += 1
                let list = lists[lists.count - 1]
                append(String(repeating: "  ", count: max(lists.count - 1, 0)))
                append(list.ordered ? "\(list.index). " : "- ")
            } else {
                append("- ")
            }
        case "h1", "h2", "h3", "h4", "h5", "h6":
            breakParagraph()
            append(String(repeating: "#", count: Int(name.dropFirst()) ?? 1) + " ")
        case "table":
            breakParagraph()
            tables.append([])
        case "tr":
            if !tables.isEmpty { tables[tables.count - 1].append([]) }
        case "td", "th":
            pushBuffer(for: name)
        case "img":
            appendImage(attributes)
        default:
            break
        }
    }

    private mutating func close(_ name: String) {
        switch name {
        case "p", "div", "blockquote", "section":
            breakParagraph()
        case "b", "strong":
            append("**")
        case "i", "em":
            append("*")
        case "a":
            let text = popBuffer()
            let href = hrefs.popLast() ?? ""
            // A link with no text of its own, or pointing nowhere, is written as plain
            // text: `[](url)` renders as nothing at all. A scheme `LinkPolicy` refuses
            // (`javascript:`, `file:`, a custom app's) keeps its text and loses the link,
            // so the note never carries something a click would hand to the system.
            if text.isEmpty {
                append(href)
            } else if href.isEmpty || !LinkPolicy.isOpenable(href) {
                append(text)
            } else {
                append("[\(text)](\(href))")
            }
        case "ul", "ol":
            _ = lists.popLast()
            breakParagraph()
        case "h1", "h2", "h3", "h4", "h5", "h6":
            breakParagraph()
        case "td", "th":
            placeCell(popBuffer())
        case "table":
            if let rows = tables.popLast() { appendTable(rows) }
        default:
            break
        }
    }

    /// A remote image is dropped whole - its URL is the tracking (R-06), and this app
    /// never fetches one (principle 2). A `cid:` image is left as a markdown embed for
    /// the caller to repoint at the decoded inline part; a 1×1 of any origin is a pixel,
    /// not a picture.
    private mutating func appendImage(_ attributes: [String: String]) {
        let source = attributes["src"] ?? ""
        let width = Int(attributes["width"] ?? "")
        let height = Int(attributes["height"] ?? "")
        if let width, let height, width <= 1, height <= 1 { return }
        guard source.lowercased().hasPrefix("cid:") else { return }
        append("![\(attributes["alt"] ?? "")](\(source))")
    }

    private mutating func appendTable(_ rows: [[String]]) {
        let filled = rows.filter { !$0.isEmpty }
        guard let header = filled.first else { return }
        // One cell in one row is a layout table, which email is built out of: its
        // content is the paragraph, not a one-column grid.
        guard filled.count > 1 || header.count > 1 else {
            append(header.joined())
            breakParagraph()
            return
        }
        breakParagraph()
        append("| " + header.map(escapedCell).joined(separator: " | ") + " |")
        breakLine()
        append("| " + header.map { _ in "---" }.joined(separator: " | ") + " |")
        for row in filled.dropFirst() {
            breakLine()
            let padded = row + Array(repeating: "", count: max(header.count - row.count, 0))
            append("| " + padded.map(escapedCell).joined(separator: " | ") + " |")
        }
        breakParagraph()
    }

    private func escapedCell(_ cell: String) -> String {
        cell.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: Buffers

    private mutating func append(_ text: String) {
        guard !text.isEmpty else { return }
        var addition = text
        // HTML collapses whitespace across a tag boundary, so a space that would land
        // at the start of a line is not one the reader ever saw.
        if addition.hasPrefix(" "),
           buffers[buffers.count - 1].isEmpty || buffers[buffers.count - 1].hasSuffix("\n") {
            addition.removeFirst()
        }
        buffers[buffers.count - 1] += addition
    }

    private mutating func breakLine() {
        let current = buffers[buffers.count - 1]
        guard !current.isEmpty, !current.hasSuffix("\n") else { return }
        buffers[buffers.count - 1] += "\n"
    }

    private mutating func breakParagraph() {
        let current = buffers[buffers.count - 1]
        guard !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if current.hasSuffix("\n\n") { return }
        buffers[buffers.count - 1] += current.hasSuffix("\n") ? "\n" : "\n\n"
    }

    private mutating func pushBuffer(for element: String) {
        buffers.append("")
        owners.append(element)
    }

    private mutating func popBuffer() -> String {
        guard buffers.count > 1 else { return "" }
        _ = owners.popLast()
        return buffers.removeLast().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A finished cell joins the open table's last row, or - outside a table - the text.
    private mutating func placeCell(_ cell: String) {
        if !tables.isEmpty, !tables[tables.count - 1].isEmpty {
            let table = tables.count - 1
            tables[table][tables[table].count - 1].append(cell)
        } else {
            append(cell)
        }
    }

    /// The walk with every element still open at the end of input closed, innermost first, the
    /// way its matching close tag would have (ADR-0064 §D7.1, R-10): text after an unclosed `<a>`
    /// or `<td>` is kept, in order, instead of staying in a buffer nothing reads.
    private func drained() -> HTMLWalk {
        var walk = self
        while walk.buffers.count > 1, let owner = walk.owners.last {
            guard owner == "td" || owner == "th" else {
                walk.close(owner)
                continue
            }
            // `<td>A<td>B` is two sibling cells in HTML. Folded innermost first they would land
            // reversed, so a run of unclosed cells is placed outer first.
            var cells: [String] = []
            while walk.buffers.count > 1, let last = walk.owners.last, last == "td" || last == "th" {
                cells.append(walk.popBuffer())
            }
            for cell in cells.reversed() { walk.placeCell(cell) }
        }
        while let rows = walk.tables.popLast() { walk.appendTable(rows) }
        return walk
    }
}

// MARK: - Entities

private enum HTMLEntities {
    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var remainder = Substring(text)

        while let start = remainder.firstIndex(of: "&") {
            result += remainder[remainder.startIndex..<start]
            let afterStart = remainder[remainder.index(after: start)...]
            guard let semicolon = afterStart.firstIndex(of: ";"),
                  afterStart.distance(from: afterStart.startIndex, to: semicolon) <= 8 else {
                result.append("&")
                remainder = afterStart
                continue
            }
            let name = String(afterStart[afterStart.startIndex..<semicolon])
            result += replacement(for: name) ?? "&\(name);"
            remainder = afterStart[afterStart.index(after: semicolon)...]
        }
        result += remainder
        return result
    }

    /// The named entities, and the two numeric references that show up often enough to
    /// be worth a lookup instead of the parse below. Keys are lowercase: the lookup
    /// lowercases the name first.
    static let named: [String: String] = [
        "amp": "&",
        "lt": "<",
        "gt": ">",
        "quot": "\"",
        "apos": "'", "#39": "'",
        // A non-breaking space is a space once the HTML is gone: keeping U+00A0 puts an
        // invisible, unsearchable character in every imported message.
        "nbsp": " ",
        "euro": "€",
        "hellip": "…",
        "rsquo": "\u{2019}", "#8217": "\u{2019}",
        "lsquo": "\u{2018}",
        "ldquo": "\u{201C}",
        "rdquo": "\u{201D}",
        "ndash": "\u{2013}",
        "mdash": "\u{2014}",
    ]

    private static func replacement(for name: String) -> String? {
        if let known = named[name.lowercased()] { return known }
        guard name.hasPrefix("#") else { return nil }
        let digits = name.dropFirst()
        let value: UInt32?
        if digits.lowercased().hasPrefix("x") {
            value = UInt32(digits.dropFirst(), radix: 16)
        } else {
            value = UInt32(digits)
        }
        guard let value, let scalar = Unicode.Scalar(value) else { return nil }
        return String(Character(scalar))
    }
}

private extension String {
    /// HTML's own whitespace rule: any run of spaces, tabs and newlines is one space.
    var collapsedWhitespace: String {
        var result = ""
        var pendingSpace = false
        for character in self {
            if character.isWhitespace {
                pendingSpace = true
                continue
            }
            if pendingSpace {
                result.append(" ")
                pendingSpace = false
            }
            result.append(character)
        }
        // A leading or trailing run survives as one space: it is the word gap across a
        // tag boundary, and `append(_:)` is what decides whether it lands on a line.
        if pendingSpace { result.append(" ") }
        return result
    }
}
