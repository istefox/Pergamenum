import SwiftUI

/// The quote and callout half of reading mode (ADR-0087 §D7, §D8), in a file of its own so the view
/// stays inside its length budget. The nesting is drawn from `QuoteLine.level` with the editor's
/// `QuoteGeometry`: one step per level, one full-height bar per level in `color.quote.bar`.
extension MarkdownBlocksView {
    /// One quote step at the body size, the editor's `EditorGutter.quoteStepInEms`.
    private var quoteStep: CGFloat { EditorGutter.quoteStepInEms * theme.nsFont(.body).pointSize }

    /// A quote: a row per line, its bars beside it. A level-0 line (a callout's own text) has none.
    func quoteView(_ lines: [MarkdownBlock.QuoteLine]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<max(line.level, 0), id: \.self) { _ in quoteBar }
                    Text(inline(line.text))
                        .themedText(.body, color: .textSecondary)
                        .padding(.leading, line.level > 0 ? theme.spacing(.xs) : 0)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One level's step with its bar inside it, at `QuoteGeometry.barOffsets`' first offset.
    private var quoteBar: some View {
        let offset = QuoteGeometry.barOffsets(level: 1, step: quoteStep).first ?? 0
        return Rectangle()
            .fill(theme.color(.quoteBar))
            .frame(width: QuoteGeometry.barWidth)
            .padding(.leading, offset)
            .padding(.trailing, max(0, quoteStep - offset - QuoteGeometry.barWidth))
    }

    /// A callout as the editor's card, always open: reading mode has no tab to remember a fold.
    func calloutView(_ callout: Callout) -> some View {
        let accent = callout.kind.colorToken.map { theme.color($0) } ?? theme.color(.quoteBar)
        let band = callout.kind.colorToken.map { theme.color($0).opacity(CalloutStyle.backgroundOpacity) }
            ?? theme.color(.surfaceSunken)
        return VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.s)) {
                Image(systemName: callout.kind.symbolName)
                    .foregroundStyle(accent)
                Text(inline(callout.title ?? callout.kind.label, base: theme.font(.body).weight(.semibold)))
                    .foregroundStyle(accent)
            }
            if !callout.body.isEmpty {
                quoteView(callout.body)
            }
        }
        .padding(.vertical, theme.spacing(.s))
        .padding(.leading, quoteStep)
        .padding(.trailing, theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(band)
        .overlay(alignment: .leading) {
            Rectangle().fill(accent).frame(width: QuoteGeometry.barWidth)
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }
}
