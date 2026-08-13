import AppKit
import SwiftUI

/// A note, rendered rather than edited.
///
/// The counterpart of the styled source editor, not a replacement for it: SPEC §7.1
/// keeps the editor at "source visible with style applied" and §14 rules out a live
/// preview that hides syntax while typing. Reading mode is the other thing §6.5 asks
/// for, a read-only rendering of the same note, and it is a mode you switch into.
///
/// Every colour, size and spacing comes from the theme, so a customised theme changes
/// this view too.
struct MarkdownReadingView: View {
    @Environment(\.theme) private var theme
    let text: String
    /// Called when a `[[wikilink]]` is clicked, with the note's title.
    let onFollowLink: (String) -> Void

    /// The note without its frontmatter: reading mode shows the note, and the
    /// metadata already has its own place in the inspector.
    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.blocks(in: NoteDocument.parse(text).body)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.m)) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .padding(theme.spacing(.l))
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(theme.color(.backgroundPrimary))
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == Self.noteScheme else { return .systemAction }
            let title = (url.host(percentEncoded: false) ?? url.absoluteString)
                .removingPercentEncoding ?? ""
            onFollowLink(title)
            return .handled
        })
    }

    /// A scheme of this view's own, distinct from the app's `pergamenum://` router:
    /// a wikilink is followed inside the window, and routing it through the URL
    /// handler would open it as if it had arrived from another app.
    private static let noteScheme = "pergamenum-wikilink"

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
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

        case .bulletList(let items):
            list(items) { _, item in marker("•", Text(inline(item))) }

        case .numberedList(let items):
            list(items) { index, item in marker("\(index + 1).", Text(inline(item))) }

        case .tasks(let lines):
            list(lines) { _, line in taskRow(line) }

        case .quote(let lines):
            HStack(alignment: .top, spacing: theme.spacing(.s)) {
                Rectangle()
                    .fill(theme.color(.borderStrong))
                    .frame(width: 3)
                Text(inline(lines.joined(separator: "\n")))
                    .themedText(.body, color: .textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code(let language, let lines):
            VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
                if let language {
                    Text(language).themedText(.caption, color: .textTertiary)
                }
                Text(lines.joined(separator: "\n"))
                    .themedText(.mono, color: .textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(theme.spacing(.s))
            .background(theme.color(.surfaceSunken))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))

        case .rule:
            Rectangle()
                .fill(theme.color(.borderSubtle))
                .frame(height: 1)
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

    // MARK: Inline

    /// Turns one block's text into an attributed string, with the theme's fonts and
    /// with links the view can act on.
    private func inline(_ text: String, base: Font? = nil) -> AttributedString {
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
            case .note(let title):
                piece.link = Self.noteURL(title)
                piece.foregroundColor = theme.color(.accentPrimary)
                piece.underlineStyle = .single
            case .url(let target):
                piece.link = URL(string: target)
                piece.foregroundColor = theme.color(.accentPrimary)
            case nil:
                break
            }
            result.append(piece)
        }
        return result
    }

    private static func noteURL(_ title: String) -> URL? {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? title
        return URL(string: "\(noteScheme)://\(encoded)")
    }
}
