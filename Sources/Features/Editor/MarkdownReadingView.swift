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
    @Environment(\.theme) var theme
    let text: String
    /// Called when a `[[wikilink]]` is clicked, with the note's title.
    let onFollowLink: (String) -> Void
    /// Where the note lives, so an embedded file is looked for beside it first.
    var notePath: String = ""
    var vaultRoot: URL?
    var thumbnails: ThumbnailStore?
    /// Whether this view takes the keyboard when it appears.
    ///
    /// True in reading mode, where there is nothing else to type into. False when the
    /// rendering sits beside an editor, as it does in the Diario pane: a preview that
    /// steals focus takes the caret out of the note the moment it is drawn, and every
    /// keystroke after that goes to the scroller.
    var takesFocus = true
    /// The index entry the sidebar asked to be taken to, as its position in the index
    /// (M8). This view scrolls by block and the editor by character, so the ordinal is
    /// what the two have in common.
    var scrollToEntry: Int?
    var onScrollApplied: () -> Void = {}

    @State private var position = ScrollPosition()
    @State private var metrics = Metrics()
    @FocusState private var isFocused: Bool

    /// The note without its frontmatter: reading mode shows the note, and the
    /// metadata already has its own place in the inspector.
    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.blocks(in: NoteDocument.parse(text).body)
    }

    /// Which block draws the nth index entry.
    ///
    /// The bridge between the two surfaces, and the one place they can disagree: the nth
    /// heading-or-embed block is the nth entry of `NoteOutline`. A test asserts the two
    /// stay in step on a hostile note, because a click landing on the wrong section is
    /// not something anybody notices until it happens to them.
    private func blockIndex(ofEntry entry: Int) -> Int? {
        let indexed = blocks.enumerated().filter { _, block in
            switch block {
            case .heading, .embed: true
            default: false
            }
        }
        guard entry >= 0, entry < indexed.count else { return nil }
        return indexed[entry].offset
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
        .scrollPosition($position)
        .onChange(of: scrollToEntry) { _, entry in
            guard let entry, let block = blockIndex(ofEntry: entry) else { return }
            withAnimation(.easeOut(duration: 0.2)) { position.scrollTo(id: block) }
            onScrollApplied()
        }
        // A SwiftUI ScrollView on macOS takes the wheel and the trackpad but not the
        // keyboard: it is not focusable, so Page Down went nowhere and a note could
        // only be read with a hand on the trackpad. Focus is taken when the view
        // appears because in reading mode there is nothing else to type into.
        .focusable(takesFocus)
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { if takesFocus { isFocused = true } }
        .onScrollGeometryChange(for: Metrics.self) { geometry in
            Metrics(
                offset: geometry.contentOffset.y,
                viewport: geometry.containerSize.height,
                content: geometry.contentSize.height
            )
        } action: { _, updated in
            metrics = updated
        }
        .onKeyPress(.pageDown) { scroll(by: page) }
        .onKeyPress(.space) { scroll(by: page) }
        .onKeyPress(.pageUp) { scroll(by: -page) }
        .onKeyPress(.downArrow) { scroll(by: Self.lineStep) }
        .onKeyPress(.upArrow) { scroll(by: -Self.lineStep) }
        .onKeyPress(.home) { scroll(to: 0) }
        .onKeyPress(.end) { scroll(to: metrics.maximumOffset) }
        .background(theme.color(.backgroundPrimary))
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == Self.noteScheme else { return .systemAction }
            let title = (url.host(percentEncoded: false) ?? url.absoluteString)
                .removingPercentEncoding ?? ""
            onFollowLink(title)
            return .handled
        })
    }

    // MARK: Keyboard scrolling

    /// What the scroll view last reported about itself.
    ///
    /// Needed because the keys move by a distance rather than to a view: without the
    /// viewport height there is no "one page", and without the content height there is
    /// no bottom to stop at.
    private struct Metrics: Equatable {
        var offset: CGFloat = 0
        var viewport: CGFloat = 0
        var content: CGFloat = 0

        var maximumOffset: CGFloat { max(0, content - viewport) }
    }

    /// A hair under a full viewport, so the line you were reading is still on screen
    /// after the jump.
    private var page: CGFloat { max(1, metrics.viewport * 0.9) }
    private static let lineStep: CGFloat = 48

    private func scroll(by delta: CGFloat) -> KeyPress.Result {
        scroll(to: metrics.offset + delta)
    }

    private func scroll(to target: CGFloat) -> KeyPress.Result {
        let clamped = min(max(0, target), metrics.maximumOffset)
        // Already against that end: leave the key to whatever else wants it rather
        // than swallowing it into a scroll that cannot happen.
        guard abs(clamped - metrics.offset) > 0.5 else { return .ignored }
        position.scrollTo(y: clamped)
        return .handled
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

        case .bulletList, .numberedList, .tasks:
            listView(for: block)

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
                Text(highlighted(lines.joined(separator: "\n"), language: language))
                    .font(theme.font(.mono))
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

        case .table(let table):
            self.table(table)

        case .embed(let target, let alt):
            EmbeddedFileView(
                target: target, alt: alt, notePath: notePath, root: vaultRoot, thumbnails: thumbnails
            )
        }
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
