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
    /// Another note on a line of its own: `![[nota]]` or `![[nota#sezione]]` (ADR-0010).
    ///
    /// Separate from `.embed` because the two resolve differently and fail differently: a
    /// file that is not there is a missing file, a note that is not there is a missing
    /// note, and saying the first about the second is the defect this case removes.
    case transclusion(reference: String, section: String?)

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

extension MarkdownBlock.Table.Column {
    /// The reading view's own spelling of what `GFMTable` parsed (ADR-0029 §D10).
    ///
    /// Two enums rather than one shared: `MarkdownBlock.Table` is a value the reading view
    /// and the HTML exporter already consume, and collapsing it onto `GFMTable`'s would be a
    /// change to that shape for no gain - the extraction's promise is one *grammar*, not one
    /// type.
    init(_ alignment: GFMTable.Alignment) {
        switch alignment {
        case .leading: self = .leading
        case .center: self = .center
        case .trailing: self = .trailing
        }
    }
}

enum MarkdownBlockParser {
    /// Splits a note body into blocks. Frontmatter is expected to be gone already:
    /// `NoteDocument.parse` owns that, and reading mode shows the note, not its
    /// metadata header.
    ///
    /// A projection of `lineTokens(in:)` (ADR-0082 §D1): the token layer decides what each line
    /// is, and this only groups runs of lines into blocks. The line split is the token layer's,
    /// `Character.isNewline`: a `"\r\n"` pair is one `Character` and ends one line, where a scalar
    /// split made it two and gave a CRLF note a blank line after every line (PG-317).
    static func blocks(in body: String) -> [MarkdownBlock] {
        var state = Accumulator()
        let tokens = lineTokens(in: body)
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            let line = body[token.range]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            switch token.kind {
            case .fenceOpen(let language):
                // A fence swallows everything up to the closing one, verbatim: a heading
                // or a dash inside a code block is code, not structure. An unclosed fence
                // ends at the end of the note rather than running off it, which would
                // render the rest of the note as nothing.
                state.flushAll()
                var content: [String] = []
                index += 1
                while index < tokens.count, tokens[index].kind == .fenceBody {
                    content.append(String(body[tokens[index].range]))
                    index += 1
                }
                if index < tokens.count, tokens[index].kind == .fenceClose { index += 1 }
                state.blocks.append(.code(language: language, lines: content))
                continue
            case .tableRow:
                state.flushAll()
                var end = index + 1
                while end < tokens.count, tokens[end].kind == .tableRow { end += 1 }
                let rows = tokens[(index + 1)..<end].map { String(body[$0.range]) }
                state.blocks.append(Self.table(header: trimmed, rows: rows))
                index = end
                continue
            default:
                break
            }
            // A remote target is deliberately left to the inline path, which renders it
            // as a link: this app fetches nothing over the network, so there is no
            // picture to draw for it - `Transclusion.target` returns nil for one.
            if let target = Transclusion.target(ofLine: trimmed) {
                state.flushAll()
                switch target {
                case .file(let name, let alt):
                    state.blocks.append(.embed(target: name, alt: alt))
                case .note(let reference, let section):
                    state.blocks.append(.transclusion(reference: reference, section: section))
                }
            } else {
                state.take(line, trimmed: trimmed, kind: token.kind)
            }
            index += 1
        }

        state.flushAll()
        return state.blocks
    }

    // MARK: Tables

    /// The table the token layer found at `header`, with the lines after it.
    ///
    /// The grammar itself moved to `GFMTable` (ADR-0029 §D10): the editor needs the same
    /// recognition *with ranges*, and a second recogniser is exactly what ADR-0018 §D1
    /// refused for the marker spans. `MarkdownBlock.Table`'s own shape is unchanged - only
    /// the alignment enum is translated on the way out, one case for one case. The token
    /// layer has already said these lines are one table, so the parse cannot fail; an empty
    /// table is the answer if it ever did, never a lost line.
    private static func table(header: String, rows: [String]) -> MarkdownBlock {
        guard let parsed = GFMTable.parsed(header: header, rest: rows[...]) else {
            return .table(MarkdownBlock.Table(header: [], alignments: [], rows: []))
        }
        return .table(MarkdownBlock.Table(
            header: parsed.header,
            alignments: parsed.alignments.map(MarkdownBlock.Table.Column.init),
            rows: parsed.rows
        ))
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

        /// `line` is the token's own line; its marker ranges index the same string.
        mutating func take(_ line: Substring, trimmed: String, kind: MarkdownLineToken.Kind) {
            func after(_ marker: Range<String.Index>) -> String {
                String(line[marker.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            switch kind {
            case .blank:
                flushAll()
            case .rule:
                flushAll()
                blocks.append(.rule)
            // A heading or a list item with nothing after its marker yet is drawn as the text it
            // is: the editor reads `## ` as a heading the moment it is typed, a reading view has
            // nothing to draw for it.
            case .heading(let level, let marker) where !after(marker).isEmpty:
                flushAll()
                blocks.append(.heading(level: level, text: after(marker)))
            case .task(_, let marker, _):
                flushExcept(.tasks)
                let box = line[line.index(marker.upperBound, offsetBy: -2)]
                tasks.append(MarkdownBlock.TaskLine(isDone: box == "x" || box == "X", marker: box, text: after(marker)))
            case .listItem(false, _, let marker, _) where !after(marker).isEmpty:
                flushExcept(.bullets)
                bullets.append(after(marker))
            case .listItem(true, _, let marker, _) where !after(marker).isEmpty:
                flushExcept(.numbers)
                numbers.append(after(marker))
            case .quote:
                flushExcept(.quote)
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            default:
                flushExcept(.paragraph)
                paragraph.append(String(line))
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

    /// Whether a line is a thematic break: three or more of `-`, `*` or `_`, optionally
    /// space-separated.
    ///
    /// Not `private`: `lineTokens(in:)` classifies a `.rule` line by this exact predicate,
    /// which `MarkdownStyler` maps onto `.horizontalRule` (ADR-0029 §D1, ADR-0082 §D2), and
    /// `EditorDecorationDelegate.stillSpellsARule` re-asks it of the live characters at layout
    /// time. A second spelling of "this line is a rule" is what would let the reading view and
    /// the editor disagree about a `- - -`, the same argument `CodeFence.marks` was extracted on.
    static func isRule(_ line: some StringProtocol) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" } || stripped.allSatisfy { $0 == "*" }
            || stripped.allSatisfy { $0 == "_" }
    }
}
