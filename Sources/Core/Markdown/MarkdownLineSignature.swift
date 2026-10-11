import Foundation

/// What a line says about the structure around it (ADR-0091 §D3). Compared before and after an edit
/// to decide between restyling a paragraph and restyling the note.
///
/// Each member is read with the predicate of the parser it restates, never with a second copy of
/// it: `CodeFence.marks` and `WikilinkParser.marksCodeFence` for the fence mark, `GFMTable.alignments`
/// for a pipe-less delimiter row, `ListNesting.role(of:)` for the list role, and
/// `WikilinkParser.inlineCodeRanges(inLine:)` for a bracket that sits in code.
///
/// Foundation only: this file compiles into `perg` and `pergamenum-mcp` (ADR-0001 §D1).
struct MarkdownLineSignature: Equatable, Sendable {
    /// The trimmed line starts with three backticks or three tildes.
    var fenceMark: Bool
    /// The trimmed line contains `|`, or reads as a delimiter row.
    var tableCapable: Bool
    var listRole: ListNesting.Role
    /// The line's `[[`, `![[` and `]]` tokens, in order.
    var brackets: [Bracket]

    enum Bracket: Equatable, Sendable {
        case open(embed: Bool, inCode: Bool)
        case close
    }

    /// The signature of one styler line, its terminator excluded.
    static func of(_ line: Substring) -> MarkdownLineSignature {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return MarkdownLineSignature(
            fenceMark: CodeFence.marks(trimmed) || WikilinkParser.marksCodeFence(trimmed),
            tableCapable: isTableCapable(trimmed),
            listRole: ListNesting.role(of: line),
            brackets: brackets(in: line)
        )
    }

    /// A delimiter row's every cell starts with `:` or `-`, so a pipe-less line that starts with
    /// neither is never one and skips the cell split.
    private static func isTableCapable(_ trimmed: String) -> Bool {
        if trimmed.contains("|") { return true }
        guard let first = trimmed.first, first == "-" || first == ":" else { return false }
        return GFMTable.alignments(in: trimmed) != nil
    }

    /// The `[[` and `]]` tokens in the order `WikilinkParser.links` meets them: a scan that takes
    /// two brackets at a time, so `[[[` is one opener and a `[`.
    private static func brackets(in line: Substring) -> [Bracket] {
        guard line.contains("[") || line.contains("]") else { return [] }
        var result: [Bracket] = []
        var code: [Range<String.Index>]?
        var previous: Character?
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            let next = line.index(after: index)
            if character == "[" || character == "]", next < line.endIndex, line[next] == character {
                if character == "[" {
                    let spans = code ?? WikilinkParser.inlineCodeRanges(inLine: line)
                    code = spans
                    result.append(.open(embed: previous == "!", inCode: spans.contains { $0.contains(index) }))
                } else {
                    result.append(.close)
                }
                previous = line[next]
                index = line.index(after: next)
            } else {
                previous = character
                index = next
            }
        }
        return result
    }
}
