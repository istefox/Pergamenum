import Foundation

/// Which callout bodies are hidden (ADR-0087 §D8), through the same hidden-line set folded headings
/// and the frontmatter use (ADR-0078). Read with the token layer's callout grammar, never a second
/// one: a body line is a `.calloutBody` token, a title line a `.calloutHeader`.
enum CalloutFold {
    /// `-` starts folded and `+` starts open; the tab's toggle flips either; no sign never folds.
    static func isFolded(_ fold: Callout.Fold, toggled: Bool) -> Bool {
        switch fold {
        case .fixed: false
        case .folded: !toggled
        case .open: toggled
        }
    }

    /// The body-line offsets to hide, given the title offsets the tab has toggled.
    static func hiddenLines(in text: String, toggled: Set<Int>) -> Set<Int> {
        folds(in: text, toggled: toggled).reduce(into: []) { $0.formUnion($1.lines) }
    }

    /// Every folded callout: its title line's UTF-16 offset and its body lines' offsets. An offset in
    /// `toggled` that is no title line is ignored (`NoteTab.toggledCallouts`' contract). A fragment of a
    /// note reads a frontmatter block only where it starts the note, as the styler's fragment does.
    static func folds(
        in text: String, toggled: Set<Int>, readsFrontmatter: Bool = true
    ) -> [(title: Int, lines: [Int])] {
        // Every header holds `[!`; a note without one pays for no tokenizing.
        guard text.contains("[!") else { return [] }
        let tokens = MarkdownBlockParser.lineTokens(
            in: text, readsFrontmatter: readsFrontmatter, endsLine: LineBreak.isTerminator
        )
        var result: [(title: Int, lines: [Int])] = []
        var folded = false
        for token in tokens {
            switch token.kind {
            case .calloutHeader(let header, _):
                let offset = token.range.lowerBound.utf16Offset(in: text)
                folded = isFolded(header.fold, toggled: toggled.contains(offset))
                if folded { result.append((offset, [])) }
            case .calloutBody where folded:
                result[result.count - 1].lines.append(token.range.lowerBound.utf16Offset(in: text))
            default:
                folded = false
            }
        }
        return result.filter { !$0.lines.isEmpty }
    }
}
