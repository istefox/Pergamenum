import Foundation

// ADR-0087 §D2 and §D3, plan docs/plans/note-workflow-n5.md, Task 1 (R-38).
//
// The shared grammar of a callout: `> [!type] Titolo`, the foldable `-` and `+` forms, and the
// block `MarkdownBlockParser` folds a run of quote lines into. Foundation only: this file compiles
// into `perg` and `pergamenum-mcp` (ADR-0001 §D1), so what a callout looks like (a colour, an
// SF Symbol) is an extension outside `Sources/Core` (`CalloutStyle.swift`).

/// The type a callout names. The app writes the five English keywords and reads the Italian aliases
/// (ADR-0087 §D3); anything else is `other`, drawn neutral.
enum CalloutKind: Hashable, Sendable {
    case note, tip, important, warning, caution
    case other(String)

    /// Case-insensitive; `nota`, `suggerimento`, `importante`, `avviso` and `attenzione` read as the
    /// five cases, anything else as `other` with the type as written.
    init(keyword: some StringProtocol) {
        switch keyword.lowercased() {
        case "note", "nota": self = .note
        case "tip", "suggerimento": self = .tip
        case "important", "importante": self = .important
        case "warning", "avviso": self = .warning
        case "caution", "attenzione": self = .caution
        default: self = .other(String(keyword))
        }
    }

    /// What the app writes: the English keyword, or the written type for `other`.
    var keyword: String {
        switch self {
        case .note: "note"
        case .tip: "tip"
        case .important: "important"
        case .warning: "warning"
        case .caution: "caution"
        case .other(let written): written
        }
    }

    /// What the interface shows: «Nota», «Suggerimento», «Importante», «Avviso», «Attenzione», and
    /// the written type capitalised for `other`.
    var label: String {
        switch self {
        case .note: "Nota"
        case .tip: "Suggerimento"
        case .important: "Importante"
        case .warning: "Avviso"
        case .caution: "Attenzione"
        case .other(let written): written.prefix(1).uppercased() + written.dropFirst()
        }
    }

    /// `callout-<keyword>` for the five, `callout-other` otherwise: one of six fixed values, never
    /// text from the note (ADR-0087 §D12).
    var exportClass: String {
        if case .other = self { return "callout-other" }
        return "callout-\(keyword)"
    }
}

/// A callout read from a quote run: its header line and the rest of the run.
struct Callout: Equatable, Sendable {
    var kind: CalloutKind
    /// The written title, or nil when the header names none.
    var title: String?
    var fold: Fold
    /// The rest of the run, each line's level reduced by one (level 0 is the callout's own text).
    var body: [MarkdownBlock.QuoteLine]

    /// `-` starts folded, `+` starts open, no sign is not foldable.
    enum Fold: Equatable, Sendable { case fixed, open, folded }

    /// What `header(inLine:)` recognised on the title line.
    struct Header: Equatable, Sendable {
        var kind: CalloutKind
        var fold: Fold
        var title: String?
        /// UTF-16 length of `>`, the spaces, `[!type]`, the sign and one following space: what the
        /// editor conceals. Never the title.
        var markerLength: Int
    }

    /// The one predicate for "this line is a callout's title line": a level-1 quote line whose text
    /// opens with `[!type]`.
    ///
    /// The line opens with one `>` and any spaces, then `[!type]` with a non-empty type holding no
    /// space, then an optional `-` or `+`, then one optional space; the rest, trimmed, is the title.
    /// A second `>` before the `[` makes it a level-2 line, which is quote text (§D2).
    static func header(inLine line: some StringProtocol) -> Header? {
        let text = Substring(line)
        guard text.first == ">" else { return nil }
        let open = text.dropFirst().drop(while: { $0 == " " })
        guard open.hasPrefix("[!"), let close = open.firstIndex(of: "]") else { return nil }
        let type = open[open.index(open.startIndex, offsetBy: 2)..<close]
        guard !type.isEmpty, !type.contains(where: \.isWhitespace) else { return nil }
        var rest = open[open.index(after: close)...]
        var fold = Fold.fixed
        if let sign = rest.first, sign == "-" || sign == "+" {
            fold = sign == "-" ? .folded : .open
            rest = rest.dropFirst()
        }
        if rest.first == " " { rest = rest.dropFirst() }
        let title = rest.trimmingCharacters(in: .whitespaces)
        return Header(
            kind: CalloutKind(keyword: type),
            fold: fold,
            title: title.isEmpty ? nil : title,
            markerLength: text[..<rest.startIndex].utf16.count
        )
    }
}
