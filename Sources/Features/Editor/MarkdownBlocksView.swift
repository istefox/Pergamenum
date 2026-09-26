import SwiftUI

/// A note's blocks, drawn. No scrolling, no keyboard, no focus - just the rendering.
///
/// Extracted from `MarkdownReadingView` so that more than one place can draw a note:
/// reading mode puts this inside its scroller, and a transcluded note (ADR-0010) draws
/// the same blocks inside a host note. Two renditions of the same markdown that did not
/// share this code would drift within a week.
///
/// Every colour, size and spacing comes from the theme, so a customised theme changes
/// both callers at once.
struct MarkdownBlocksView: View {
    @Environment(\.theme) var theme

    let blocks: [MarkdownBlock]
    /// Where the note lives, so an embedded file is looked for beside it first.
    var notePath: String = ""
    var vaultRoot: URL?
    var thumbnails: ThumbnailStore?
    /// How a transcluded note is reached (ADR-0010). Nil where there is no vault behind
    /// the view, and then a transclusion draws as unresolved rather than as nothing.
    var transclusions: TransclusionSource?
    /// False inside a transcluded note: depth one, so the second level is a link.
    var expandsTransclusions = true
    /// How a `pergamenum-view` fence gets its rows (ADR-0009). Nil where there is no vault
    /// behind the view, and then the block says so rather than drawing an empty result.
    var queries: ViewQuerySource?

    /// A scheme of this view's own, distinct from the app's `pergamenum://` router:
    /// a wikilink is followed inside the window, and routing it through the URL
    /// handler would open it as if it had arrived from another app.
    static let noteScheme = "pergamenum-wikilink"

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    @ViewBuilder
    func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            // The base font is passed into the runs, not applied to the Text: an
            // attributed string carries a font per run, and a per-run font wins over
            // the view's, so every heading came out at body size.
            Text(inline(text, base: headingFont(level)))
                .foregroundStyle(theme.color(.textPrimary))
                .padding(.top, level <= 2 ? theme.spacing(.s) : 0)

        case .paragraph(let text):
            Text(inline(text))
                .themedText(.body)
                .textSelection(.enabled)

        case .bulletList, .numberedList, .tasks:
            listView(for: block)

        case .quote(let lines):
            quoteView(lines)

        case .code(let language, let lines):
            // A view is a fenced block that something runs (ADR-0009 §D1). Only here, in
            // Lettura: in Modifica the fence stays source, which is also what Obsidian shows
            // a reader that cannot run it.
            if language == ViewBlock.language {
                RenderedViewBlock(
                    source: lines.joined(separator: "\n"),
                    notePath: notePath,
                    vaultRoot: vaultRoot,
                    thumbnails: thumbnails,
                    queries: queries
                )
            } else {
                codeView(language: language, lines: lines)
            }

        case .rule:
            Rectangle()
                .fill(theme.color(.borderSubtle))
                .frame(height: 1)

        case .table(let table):
            self.table(table)

        case .embed(let target, let alt):
            EmbeddedFileView(
                target: target, alt: alt, notePath: notePath, root: vaultRoot, thumbnails: thumbnails
            )

        case .transclusion(let reference, let section):
            TranscludedNoteView(
                reference: reference,
                section: section,
                source: transclusions,
                vaultRoot: vaultRoot,
                thumbnails: thumbnails,
                expands: expandsTransclusions
            )
        }
    }

    private func quoteView(_ lines: [String]) -> some View {
        HStack(alignment: .top, spacing: theme.spacing(.s)) {
            Rectangle()
                .fill(theme.color(.borderStrong))
                .frame(width: 3)
            Text(inline(lines.joined(separator: "\n")))
                .themedText(.body, color: .textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func codeView(language: String?, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            if let language {
                Text(language).themedText(.caption, color: .textTertiary)
            }
            Text(highlighted(lines.joined(separator: "\n"), language: language))
                .font(theme.font(.mono))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(theme.spacing(.s))
        .background(theme.color(.surfaceSunken))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }

    /// The three list shapes, together in one place: bullets, numbers and tasks differ
    /// only in what leads each row.
    @ViewBuilder
    private func listView(for block: MarkdownBlock) -> some View {
        switch block {
        case .bulletList(let items):
            list(items) { _, item in marker("•", Text(inline(item))) }
        case .numberedList(let items):
            list(items) { index, item in marker("\(index + 1).", Text(inline(item))) }
        case .tasks(let lines):
            list(lines) { _, line in taskRow(line) }
        default:
            EmptyView()
        }
    }

    /// The three list blocks differ only in what a row looks like.
    private func list<Item, Row: View>(
        _ items: [Item],
        @ViewBuilder row: @escaping (Int, Item) -> Row
    ) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                row(index, item)
            }
        }
    }

    private func taskRow(_ line: MarkdownBlock.TaskLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.s)) {
            Image(systemName: symbol(for: line))
                .foregroundStyle(theme.color(color(for: line)))
            Text(inline(line.text))
                .themedText(.body, color: line.isDone ? .taskDone : .textPrimary)
                .strikethrough(line.isDone)
        }
    }

    private func marker(_ label: String, _ content: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.s)) {
            Text(label)
                .themedText(.body, color: .textTertiary)
                .frame(minWidth: 18, alignment: .trailing)
            content.themedText(.body)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: theme.font(.title)
        case 2: theme.font(.heading)
        default: theme.font(.body).weight(.semibold)
        }
    }

    private func symbol(for line: MarkdownBlock.TaskLine) -> String {
        switch line.marker {
        case "x", "X": "checkmark.square.fill"
        case "-": "minus.square"
        case ">": "calendar.badge.clock"
        default: "square"
        }
    }

    private func color(for line: MarkdownBlock.TaskLine) -> ColorToken {
        switch line.marker {
        case "x", "X": .taskDone
        case "-": .taskCancelled
        case ">": .taskScheduled
        default: .taskOpen
        }
    }

    // MARK: Code

    /// A fenced block with the local grammar applied.
    ///
    /// The same `CodeSyntax.spans` the editor calls, so the two panes cannot colour the
    /// same block differently. Where the grammar says nothing - no language, a language
    /// it does not know, a run of plain identifiers - the text keeps `textPrimary`, which
    /// is what makes an unknown language degrade to plain monospace instead of to
    /// something half-coloured.
    func highlighted(_ code: String, language: String?) -> AttributedString {
        var result = AttributedString(code)
        result.foregroundColor = theme.color(.textPrimary)
        for span in CodeSyntax.spans(in: code[...], language: language) {
            guard let range = Range(span.range, in: result) else { continue }
            result[range].foregroundColor = theme.color(span.token.colorToken)
        }
        return result
    }

    // MARK: Inline

    /// Turns one block's text into an attributed string, with the theme's fonts and
    /// with links the view can act on.
    func inline(_ text: String, base: Font? = nil) -> AttributedString {
        let baseFont = base ?? theme.font(.body)
        var result = AttributedString()
        for span in MarkdownInlineParser.spans(in: text) {
            var piece = AttributedString(span.text)
            if span.styles.contains(.code) {
                piece.font = theme.font(.mono)
                piece.foregroundColor = theme.color(.accentPrimary)
            } else {
                var font = baseFont
                if span.styles.contains(.strong) { font = font.weight(.semibold) }
                if span.styles.contains(.emphasis) { font = font.italic() }
                piece.font = font
            }
            if span.styles.contains(.strikethrough) {
                piece.strikethroughStyle = .single
                piece.foregroundColor = theme.color(.textTertiary)
            }
            switch span.link {
            case .note(let title), .embed(target: let title):
                // An embed reads as a link to what it embeds (ADR-0065 §D9.2, R-17).
                piece.link = Self.noteURL(title)
                piece.foregroundColor = theme.color(.accentPrimary)
                piece.underlineStyle = .single
            case .url(let target):
                // Refused here, where the link is made, rather than by an `openURL`
                // override at each caller: the Pratiche rows install none, and a caller
                // added later would inherit the hole by omission (PG-124). A refused
                // scheme renders as the plain text it is.
                if let url = URL(string: target), LinkPolicy.isOpenable(url) {
                    piece.link = url
                    piece.foregroundColor = theme.color(.accentPrimary)
                }
            case nil:
                break
            }
            result.append(piece)
        }
        return result
    }

    static func noteURL(_ title: String) -> URL? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? title
        return URL(string: "\(noteScheme)://\(encoded)")
    }
}
