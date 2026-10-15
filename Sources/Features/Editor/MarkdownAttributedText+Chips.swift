import AppKit

/// The arms of `StyleContext.attributes(for:)` that draw a run as a pill (ADR-0087 §D5, §D9): inline
/// code, a highlight, an embed chip's punctuation, a tag and a date. A file of its own so
/// `MarkdownAttributedText.swift` stays under SwiftLint's `file_length`.
extension MarkdownAttributedText.StyleContext {
    /// One pill run's attributes; every other span is answered by `attributes(for:)` itself.
    mutating func chipAttributes(for span: MarkdownStyler.Span) -> [NSAttributedString.Key: Any] {
        let color = NSColor(theme.color(MarkdownAttributedText.colorToken(for: span)))
        switch span {
        case .code:
            // A pill over the whole run, backticks included (ADR-0087 §D5): the painter fills
            // it behind the glyphs, and the room either side is the `.kern` the delegate puts
            // on the concealed backticks.
            return [
                .font: monoFont,
                .foregroundColor: color,
                .pergamenumChip: InlineChip.Style(background: NSColor(theme.color(.codeInlineBackground))),
            ]
        case .highlight:
            return [.pergamenumChip: InlineChip.Style(background: NSColor(theme.color(.highlight)))]
        case .embedChipMarker:
            // An embed chip's punctuation (ADR-0087 §D9); `InlineChip.finish` spreads the pill,
            // with its file-type symbol, over the whole run once the closing marker is down.
            return [
                .foregroundColor: color,
                .pergamenumChip: InlineChip.Style(
                    background: NSColor(theme.color(.surfaceSunken)), leading: NSColor(theme.color(.textSecondary))
                ),
            ]
        case .tag, .scheduled:
            // The chip's two colours go on its parts in `InlineChip.finish`, after this run's
            // own attributes are down; the run keeps its colour until then (ADR-0087 §D5).
            let isTag = if case .tag = span { true } else { false }
            return [
                .foregroundColor: color,
                .pergamenumChip: InlineChip.Style(
                    background: NSColor(theme.color(isTag ? .accentMuted : .surfaceSunken)),
                    leading: NSColor(theme.color(.textSecondary)),
                    trailing: NSColor(theme.color(isTag ? .accentPrimary : .taskScheduled))
                ),
            ]
        default:
            return [.foregroundColor: color]
        }
    }
}
