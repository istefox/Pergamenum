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
    /// How a `![[nota]]` reaches the note it names (ADR-0010). Nil where there is no
    /// vault behind the view, and then a transclusion says so instead of drawing.
    var transclusions: TransclusionSource?
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
            // A transcluded note is an index entry too: `NoteOutline` lists it, so a view
            // that did not count it would send every click after the first one line short.
            case .heading, .embed, .transclusion: true
            default: false
            }
        }
        guard entry >= 0, entry < indexed.count else { return nil }
        return indexed[entry].offset
    }

    var body: some View {
        ScrollView {
            MarkdownBlocksView(
                blocks: blocks,
                notePath: notePath,
                vaultRoot: vaultRoot,
                thumbnails: thumbnails,
                transclusions: transclusions
            )
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
            guard url.scheme == MarkdownBlocksView.noteScheme else { return .systemAction }
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
}
