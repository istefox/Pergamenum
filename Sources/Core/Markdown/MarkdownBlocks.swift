import Foundation

/// A note broken into the blocks a reading view draws.
///
/// Reading mode is not the live preview SPEC §14 excludes from v1: that one hides
/// the syntax while you type, in the editor, and stays out. This is the separate,
/// read-only rendering §6.5 already asks for on note cards - the same note, shown
/// rather than edited, with the editor one click away.
///
/// A value type with no SwiftUI in it, so what the parser decides can be checked
/// directly instead of through a view that only a person can look at.
enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    /// One list, with its items already grouped: a list is a block, not a run of
    /// unrelated lines that happen to start with a dash.
    case bulletList([String])
    case numberedList([String])
    /// A checklist line of SPEC §7.1, with the marker it carried.
    case tasks([TaskLine])
    case quote([String])
    case code(language: String?, lines: [String])
    case rule
    /// A GFM table, which SPEC §5 puts in the required dialect alongside CommonMark
    /// and task lists - and which the Inserisci menu already writes.
    case table(Table)
    /// A file on a line of its own: `![[foto.png]]` or `![didascalia](foto.png)`.
    ///
    /// Only a whole line becomes one. Inside a paragraph an embed stays a span, because
    /// a picture in the middle of a sentence would cut the sentence in two.
    case embed(target: String, alt: String?)

    struct TaskLine: Equatable, Sendable {
        var isDone: Bool
        /// The raw marker, so a cancelled or scheduled task is not flattened into
        /// "not done" - the vocabulary is `[ ]`, `[x]`, `[-]`, `[>]` (SPEC §7.1).
        var marker: Character
        var text: String
    }

    struct Table: Equatable, Sendable {
        var header: [String]
        /// One per column, taken from the delimiter row. Always the same count as
        /// `header`: a table whose delimiter row disagrees is not a table at all.
        var alignments: [Column]
        /// Every row padded or truncated to the header's width, as GFM requires, so
        /// a view can index a row by column without checking its length.
        var rows: [[String]]

        enum Column: Equatable, Sendable { case leading, center, trailing }
    }
}

enum MarkdownBlockParser {
    /// Splits a note body into blocks. Frontmatter is expected to be gone already:
    /// `NoteDocument.parse` owns that, and reading mode shows the note, not its
    /// metadata header.
    static func blocks(in body: String) -> [MarkdownBlock] {
        var state = Accumulator()
        var lines = body.components(separatedBy: .newlines)[...]

        while let line = lines.first {
            lines = lines.dropFirst()
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // A fence swallows everything up to the closing one, verbatim: a heading
            // or a dash inside a code block is code, not structure.
            if trimmed.hasPrefix("```") {
                state.flushAll()
                state.blocks.append(Self.fence(opening: trimmed, consuming: &lines))
                continue
            }
            // Needs the line after this one to decide, which is why it lives here and
            // not in the accumulator: `| a | b |` is a table only when a delimiter row
            // follows it, and an ordinary paragraph may well contain a pipe.
            if let table = Self.table(header: trimmed, consuming: &lines) {
                state.flushAll()
                state.blocks.append(table)
                continue
            }
            // A remote target is deliberately left to the inline path, which renders it
            // as a link: this app fetches nothing over the network, so there is no
            // picture to draw for it.
            if let embed = Attachment.embed(inLine: trimmed), !Attachment.isRemote(embed.target) {
                state.flushAll()
                state.blocks.append(.embed(target: embed.target, alt: embed.alt))
                continue
            }
            state.take(line, trimmed: trimmed)
        }

        state.flushAll()
        return state.blocks
    }

    private static func fence(
        opening: String,
        consuming lines: inout ArraySlice<String>
    ) -> MarkdownBlock {
        let language = String(opening.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        var content: [String] = []
        while let next = lines.first {
            lines = lines.dropFirst()
            if next.trimmingCharacters(in: .whitespaces).hasPrefix("```") { break }
            content.append(next)
        }
        // An unclosed fence ends at the end of the note rather than running off it,
        // which would render the rest of the note as nothing.
        return .code(language: language.isEmpty ? nil : language, lines: content)
    }

    // MARK: Tables

    /// A table starting at `header`, or nil when these lines are not one.
    ///
    /// Consumes nothing unless it returns a table, so a paragraph that happens to
    /// contain a pipe is handed back untouched.
    private static func table(
        header: String,
        consuming lines: inout ArraySlice<String>
    ) -> MarkdownBlock? {
        guard header.contains("|") else { return nil }
        guard let delimiter = lines.first?.trimmingCharacters(in: .whitespaces) else { return nil }
        let columns = cells(in: header)
        guard let alignments = alignments(in: delimiter), alignments.count == columns.count else {
            return nil
        }

        lines = lines.dropFirst()
        var rows: [[String]] = []
        // The table runs to the first blank line or the first line with no pipe in it,
        // which is where GFM ends one.
        while let next = lines.first?.trimmingCharacters(in: .whitespaces),
              !next.isEmpty, next.contains("|") {
            lines = lines.dropFirst()
            rows.append(fit(cells(in: next), to: columns.count))
        }
        return .table(MarkdownBlock.Table(header: columns, alignments: alignments, rows: rows))
    }

    /// The column alignments a delimiter row declares, or nil when the line is not one.
    private static func alignments(in line: String) -> [MarkdownBlock.Table.Column]? {
        let parts = cells(in: line)
        guard !parts.isEmpty else { return nil }
        var result: [MarkdownBlock.Table.Column] = []
        for part in parts {
            let left = part.hasPrefix(":")
            let right = part.hasSuffix(":")
            let dashes = part.dropFirst(left ? 1 : 0).dropLast(right && part.count > 1 ? 1 : 0)
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            switch (left, right) {
            case (true, true): result.append(.center)
            case (false, true): result.append(.trailing)
            default: result.append(.leading)
            }
        }
        return result
    }

    /// Splits a row on its unescaped pipes, dropping the optional outer ones.
    private static func cells(in row: String) -> [String] {
        var body = row.trimmingCharacters(in: .whitespaces)[...]
        if body.hasPrefix("|") { body = body.dropFirst() }
        if body.hasSuffix("|"), !body.hasSuffix("\\|") { body = body.dropLast() }

        var result: [String] = []
        var current = ""
        var escaped = false
        for character in body {
            if escaped {
                // Only `\|` is an escape here; anything else keeps its backslash,
                // so a Windows path in a cell survives the trip.
                if character != "|" { current.append("\\") }
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

    /// Pads a short row and drops a long one's extra cells, as GFM specifies.
    private static func fit(_ row: [String], to width: Int) -> [String] {
        if row.count == width { return row }
        if row.count > width { return Array(row.prefix(width)) }
        return row + Array(repeating: "", count: width - row.count)
    }

    /// The lines seen so far that have not yet become a block.
    ///
    /// A separate type because the run-grouping is the whole difficulty here: a list
    /// item ends the paragraph above it, a paragraph ends the list, and every one of
    /// those transitions has to flush exactly the right accumulators.
    private struct Accumulator {
        var blocks: [MarkdownBlock] = []
        private var paragraph: [String] = []
        private var bullets: [String] = []
        private var numbers: [String] = []
        private var tasks: [MarkdownBlock.TaskLine] = []
        private var quote: [String] = []

        mutating func take(_ line: String, trimmed: String) {
            if trimmed.isEmpty {
                flushAll()
            } else if MarkdownBlockParser.isRule(trimmed) {
                flushAll()
                blocks.append(.rule)
            } else if let heading = MarkdownBlockParser.heading(in: trimmed) {
                flushAll()
                blocks.append(heading)
            } else if let task = MarkdownBlockParser.taskLine(in: trimmed) {
                flushExcept(.tasks)
                tasks.append(task)
            } else if let item = MarkdownBlockParser.bulletItem(in: trimmed) {
                flushExcept(.bullets)
                bullets.append(item)
            } else if let item = MarkdownBlockParser.numberedItem(in: trimmed) {
                flushExcept(.numbers)
                numbers.append(item)
            } else if trimmed.hasPrefix(">") {
                flushExcept(.quote)
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            } else {
                flushExcept(.paragraph)
                paragraph.append(line)
            }
        }

        private enum Run { case paragraph, bullets, numbers, tasks, quote }

        /// Closes every run but the one about to be extended.
        private mutating func flushExcept(_ kept: Run) {
            if kept != .paragraph, !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
            if kept != .bullets, !bullets.isEmpty {
                blocks.append(.bulletList(bullets))
                bullets = []
            }
            if kept != .numbers, !numbers.isEmpty {
                blocks.append(.numberedList(numbers))
                numbers = []
            }
            if kept != .tasks, !tasks.isEmpty {
                blocks.append(.tasks(tasks))
                tasks = []
            }
            if kept != .quote, !quote.isEmpty {
                blocks.append(.quote(quote))
                quote = []
            }
        }

        mutating func flushAll() {
            // No run is kept: `paragraph` is only a placeholder for "none of them",
            // and it is flushed by the first branch like the rest.
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
            flushExcept(.paragraph)
        }
    }

    // MARK: Line shapes

    private static func isRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" } || stripped.allSatisfy { $0 == "*" }
            || stripped.allSatisfy { $0 == "_" }
    }

    private static func heading(in line: String) -> MarkdownBlock? {
        var level = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "#", level < 6 {
            level += 1
            index = line.index(after: index)
        }
        // `#tag` is a tag, not a heading: the hash has to be followed by a space.
        guard level > 0, index < line.endIndex, line[index] == " " else { return nil }
        return .heading(level: level, text: String(line[index...]).trimmingCharacters(in: .whitespaces))
    }

    private static func taskLine(in line: String) -> MarkdownBlock.TaskLine? {
        guard let rest = afterBullet(line), rest.hasPrefix("["), rest.count >= 3 else { return nil }
        let marker = rest[rest.index(rest.startIndex, offsetBy: 1)]
        let closing = rest.index(rest.startIndex, offsetBy: 2)
        guard rest[closing] == "]" else { return nil }
        let text = String(rest[rest.index(after: closing)...]).trimmingCharacters(in: .whitespaces)
        return MarkdownBlock.TaskLine(isDone: marker == "x" || marker == "X", marker: marker, text: text)
    }

    private static func bulletItem(in line: String) -> String? {
        afterBullet(line)
    }

    /// The text after a `-`, `*` or `+` bullet, or nil when the line is not one.
    private static func afterBullet(_ line: String) -> String? {
        guard let first = line.first, first == "-" || first == "*" || first == "+" else { return nil }
        let rest = line.dropFirst()
        guard rest.first == " " else { return nil }
        return String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func numberedItem(in line: String) -> String? {
        var digits = ""
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber {
            digits.append(line[index])
            index = line.index(after: index)
        }
        guard !digits.isEmpty, index < line.endIndex else { return nil }
        guard line[index] == "." || line[index] == ")" else { return nil }
        let afterMarker = line.index(after: index)
        guard afterMarker < line.endIndex, line[afterMarker] == " " else { return nil }
        return String(line[line.index(after: afterMarker)...]).trimmingCharacters(in: .whitespaces)
    }
}
