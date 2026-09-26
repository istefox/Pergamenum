import Foundation

/// The line break a note's text uses (ADR-0065 §D3).
///
/// Detected once, from the text's first line break, and used only for the lines the app writes:
/// an existing line keeps its own ending, so a mixed file stays mixed.
enum LineBreak: Equatable, Sendable {
    case lf
    case crlf

    var characters: String {
        switch self {
        case .lf: "\n"
        case .crlf: "\r\n"
        }
    }

    /// What a line split on `"\n"` carries at its end: the `\r` of a CRLF pair, or nothing.
    var lineSuffix: String {
        switch self {
        case .lf: ""
        case .crlf: "\r"
        }
    }

    /// CRLF when the text's first line break is `\r\n`, LF otherwise, and LF for a text with none.
    ///
    /// Walks unicode scalars, not `Character`s: `"\r\n"` is one `Character`, so
    /// `firstIndex(of: "\n")` on the string itself never finds the LF of a CRLF pair.
    static func detected(in text: String) -> LineBreak {
        let scalars = text.unicodeScalars
        guard let newline = scalars.firstIndex(of: "\n"), newline > scalars.startIndex else { return .lf }
        return scalars[scalars.index(before: newline)] == "\r" ? .crlf : .lf
    }
}

/// The frontmatter block exactly as it was read (ADR-0065 §D1.1).
///
/// `NoteDocument.frontmatter` is what the block *means*; this is what it *was*, line by line, so a
/// write can change the keys the app meant to change and emit every other byte verbatim - a
/// comment, a colon-less line, an unparsable tag, a duplicated key, a CRLF ending. `parsed` is the
/// value the parse produced, which is how the serializer tells a key the caller changed from one
/// it left alone.
struct FrontmatterSource: Equatable, Sendable {
    enum Entry: Equatable, Sendable {
        /// A key line and its continuation lines, raw (a CRLF line keeps its `\r`).
        case key(name: String, lines: [String])
        /// A line the parser does not read as a key: blank, a YAML comment, a colon-less line,
        /// or an indented or dash line with no key above it.
        case opaque(String)
    }

    /// The raw opening delimiter line, a leading U+FEFF and a trailing `\r` included. Empty when
    /// the text has no block.
    var opening: String
    var entries: [Entry]
    /// The raw closing delimiter line, or nil when the text has no block.
    var closing: String?
    /// False when the file ends right at the closing delimiter.
    var closingHasLineBreak: Bool
    var lineBreak: LineBreak
    var parsed: Frontmatter

    /// A raw line as the parser reads it: one trailing `\r` removed and, on the text's first line,
    /// one leading U+FEFF (§D4.4). The line is still emitted as it was read.
    static func interpreted(_ raw: String, isFirst: Bool = false) -> String {
        var line = raw
        if line.hasSuffix("\r") { line.removeLast() }
        if isFirst, line.unicodeScalars.first == "\u{FEFF}" {
            line = String(String.UnicodeScalarView(line.unicodeScalars.dropFirst()))
        }
        return line
    }

    static func isDelimiter(_ interpretedLine: String) -> Bool {
        interpretedLine.trimmingCharacters(in: .whitespaces) == "---"
    }

    /// Splits a note's text (§D1.2). `components(separatedBy:)` is Foundation's split, below the
    /// grapheme level, so a CRLF line arrives with its `\r` attached rather than merged with the
    /// next one (§D3).
    static func document(from text: String) -> NoteDocument {
        let lines = text.components(separatedBy: "\n")
        let lineBreak = LineBreak.detected(in: text)
        let interpretedLines = lines.enumerated().map { interpreted($1, isFirst: $0 == 0) }
        let withoutBlock = NoteDocument(
            frontmatter: .empty, body: text, hasFrontmatterBlock: false,
            source: FrontmatterSource(
                opening: "", entries: [], closing: nil, closingHasLineBreak: false,
                lineBreak: lineBreak, parsed: .empty
            )
        )
        guard let first = interpretedLines.first, isDelimiter(first),
              let closing = interpretedLines.indices.dropFirst().first(where: { isDelimiter(interpretedLines[$0]) })
        else {
            // No block, or an opening delimiter with no closing one: the whole file is body
            // rather than a frontmatter that was never closed.
            return withoutBlock
        }

        let block = Array(interpretedLines[1..<closing])
        let frontmatter = FrontmatterParser.parse(block)
        let source = FrontmatterSource(
            opening: lines[0],
            entries: entries(raw: Array(lines[1..<closing]), interpreted: block),
            closing: lines[closing],
            closingHasLineBreak: closing + 1 < lines.count,
            lineBreak: lineBreak,
            parsed: frontmatter
        )
        return NoteDocument(
            frontmatter: frontmatter,
            body: lines[(closing + 1)...].joined(separator: "\n"),
            hasFrontmatterBlock: true,
            source: source
        )
    }

    /// Groups the block's lines the way `FrontmatterParser` reads them, so the k-th foreign entry
    /// here is the k-th `ForeignKey` there.
    private static func entries(raw: [String], interpreted: [String]) -> [Entry] {
        var result: [Entry] = []
        var index = 0
        while index < raw.count {
            guard let name = FrontmatterParser.keyName(of: interpreted[index]) else {
                result.append(.opaque(raw[index]))
                index += 1
                continue
            }
            var end = index + 1
            while end < raw.count, FrontmatterParser.isContinuation(interpreted[end]) { end += 1 }
            result.append(.key(name: name, lines: Array(raw[index..<end])))
            index = end
        }
        return result
    }
}

// MARK: - Serializing in place (ADR-0065 §D1.3, §D2)

extension NoteDocument {
    /// Rebuilds the file text, changing only what the caller changed.
    ///
    /// A document built in code (no `source`) renders canonically, as it always has. A parsed one
    /// emits its block line by line: an unchanged key, an opaque line and a foreign key its codec
    /// left alone come back byte-identical; a changed schema key is rewritten at its governing
    /// occurrence, the last one, which is the one the reader uses (§D2); every line the app writes
    /// ends in the document's line break (§D3). `body` is appended verbatim.
    func serialized() -> String {
        guard let source else { return FrontmatterSerializer.render(frontmatter) + body }
        guard let closing = source.closing else { return serializedWithoutBlock(source) }

        var pieces = source.entries.map(Piece.init)
        let suffix = source.lineBreak.lineSuffix
        let written: ([String]) -> [String] = { $0.map { $0 + suffix } }

        placeSchemaKeys(into: &pieces, source: source, written: written)
        pieces = matchingForeignKeys(pieces, written: written)

        var lines = [source.opening]
        lines.append(contentsOf: pieces.flatMap(\.lines))
        lines.append(closing)
        var text = lines.joined(separator: "\n")
        if source.closingHasLineBreak {
            text += "\n"
        } else if !body.isEmpty {
            // §D1.3.9: a closing delimiter with no line break gains one only when a body now
            // follows it.
            text += closing.hasSuffix("\r") ? "\n" : source.lineBreak.characters
        }
        return text + body
    }

    /// §D1.3.8: a document that had no block gets one only when it now has something to write,
    /// at the top, after a leading U+FEFF.
    private func serializedWithoutBlock(_ source: FrontmatterSource) -> String {
        guard frontmatter != .empty else { return body }
        let block = FrontmatterSerializer.render(frontmatter, lineBreak: source.lineBreak)
        guard body.unicodeScalars.first == "\u{FEFF}" else { return block + body }
        return "\u{FEFF}" + block + String(String.UnicodeScalarView(body.unicodeScalars.dropFirst()))
    }

    private struct Piece {
        var name: String?
        var lines: [String]

        init(name: String?, lines: [String]) {
            self.name = name
            self.lines = lines
        }

        init(_ entry: FrontmatterSource.Entry) {
            switch entry {
            case .key(let name, let lines): self.init(name: name, lines: lines)
            case .opaque(let line): self.init(name: nil, lines: [line])
            }
        }
    }

    /// §D1.3.1-§D1.3.4 and §D2 for the four schema keys.
    private func placeSchemaKeys(
        into pieces: inout [Piece],
        source: FrontmatterSource,
        written: ([String]) -> [String]
    ) {
        let keys = FrontmatterSerializer.schemaKeys
        for (order, key) in keys.enumerated()
        where FrontmatterSerializer.differs(key, frontmatter, source.parsed) {
            let canonical = FrontmatterSerializer.canonicalLines(for: key, of: frontmatter)
            let occurrences = pieces.indices.filter { pieces[$0].name == key }
            if let governing = occurrences.last {
                if !canonical.isEmpty {
                    pieces[governing].lines = written(canonical)
                } else if occurrences.count > 1 {
                    // An emptied duplicate is written bare: omitting it would make an earlier
                    // occurrence the value on the next read, and the removal would not happen.
                    pieces[governing].lines = written(["\(key):"])
                } else {
                    pieces.remove(at: governing)
                }
            } else if !canonical.isEmpty {
                let current = pieces
                let anchor = keys[..<order].reversed()
                    .compactMap { preceding in current.lastIndex { $0.name == preceding } }
                    .first
                let position = anchor.map { $0 + 1 }
                    ?? pieces.firstIndex { $0.name != nil }
                    ?? pieces.endIndex
                pieces.insert(Piece(name: key, lines: written(canonical)), at: position)
            }
        }
    }

    /// §D2's foreign-key rule: the k-th entry named N in `foreignKeys` takes the place of the k-th
    /// occurrence of N in the file - verbatim when its lines are unchanged, replaced when they
    /// changed. An occurrence with no counterpart goes; an entry with none is appended at the end.
    private func matchingForeignKeys(_ pieces: [Piece], written: ([String]) -> [String]) -> [Piece] {
        let foreign = frontmatter.foreignKeys
        let schemaKeys = Set(FrontmatterSerializer.schemaKeys)
        var used = Set<Int>()
        var seen: [String: Int] = [:]
        var result: [Piece] = []

        for piece in pieces {
            guard let name = piece.name, !schemaKeys.contains(name) else {
                result.append(piece)
                continue
            }
            let ordinal = seen[name, default: 0]
            seen[name] = ordinal + 1
            let matches = foreign.indices.filter { foreign[$0].name == name }
            guard ordinal < matches.count else { continue }
            let match = matches[ordinal]
            used.insert(match)
            let interpretedLines = piece.lines.map { FrontmatterSource.interpreted($0) }
            result.append(
                foreign[match].lines == interpretedLines
                    ? piece
                    : Piece(name: name, lines: written(foreign[match].lines))
            )
        }
        for index in foreign.indices where !used.contains(index) {
            result.append(Piece(name: foreign[index].name, lines: written(foreign[index].lines)))
        }
        return result
    }
}

// MARK: - Damage the block carries, as advisory findings (ADR-0065 §D11, R-22)

extension FrontmatterRules {
    /// The three advisory damage findings, read from the block as written. `validate` asks only
    /// for a note with a block. Nothing blocks on them: a drop reads `.tags` only.
    static func damageFindings(of document: NoteDocument) -> [FrontmatterViolation] {
        guard let source = document.source else { return [] }
        var findings: [FrontmatterViolation] = []
        if opensWithSecondBlock(document.body) { findings.append(.secondFrontmatterBlock) }

        var counts: [String: Int] = [:]
        var names: [String] = []
        for case .key(let name, _) in source.entries {
            if counts[name] == nil { names.append(name) }
            counts[name, default: 0] += 1
        }
        findings.append(contentsOf: names.filter { counts[$0, default: 0] > 1 }.map { .duplicateKey($0) })

        for case .opaque(let raw) in source.entries {
            let line = FrontmatterSource.interpreted(raw).trimmingCharacters(in: .whitespaces)
            if !line.isEmpty, !line.contains(":") { findings.append(.lineWithoutColon(line)) }
        }
        return findings
    }

    /// The body's first line is a delimiter, once one leading U+FEFF and one trailing `\r` are
    /// removed; a later line is one too; and a line between them reads as a key. A body that
    /// opens with a horizontal rule has no key line before the next one, and is not a block.
    private static func opensWithSecondBlock(_ body: String) -> Bool {
        let lines = body.components(separatedBy: "\n").map { FrontmatterSource.interpreted($0) }
        guard let first = lines.first,
              FrontmatterSource.isDelimiter(FrontmatterSource.interpreted(first, isFirst: true))
        else { return false }
        guard let closing = lines.indices.dropFirst().first(where: { FrontmatterSource.isDelimiter(lines[$0]) })
        else { return false }
        return lines[1..<closing].contains { FrontmatterParser.keyName(of: $0) != nil }
    }
}
