import SwiftUI

/// The completion panel's list, as the approved mockup drew it (M8).
///
/// The slash menu's two halves with a heading each, because forty-three flat rows is a
/// wall; an icon per row, because at a glance it separates "writes something here" from
/// "does something to the app" faster than any wording; and the keyboard shortcut on the
/// right where one exists, because a person who reached a command by typing learns the key
/// that would have got them there without the menu.
///
/// A list of note titles, headings or tags is flat and has none of that: there is one kind
/// of row, no shortcut to teach, and the heading would be a label over the only group.
/// Both shapes live here because they are one panel with one selection (PG-023).
struct CompletionPanelView: View {
    @Environment(\.theme) private var theme

    let items: [CompletionItem]
    let query: String
    /// How this trigger names an empty result. Only ever nil where the panel would not have
    /// been shown empty in the first place, so the fallback below is unreachable in the app
    /// and there purely so the type does not have to be forced open.
    let noMatch: String?
    let selectedIndex: Int
    /// The tallest the whole panel may be, which is the room beside the caret's line rather
    /// than a taste about lists. Below it the panel would have to be drawn over the text
    /// being typed into, and no list is worth that.
    let maxHeight: CGFloat
    let onChoose: (CompletionItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                nothingMatched
            } else {
                list
            }
            Divider().padding(.vertical, theme.spacing(.xs))
            footer
        }
        .padding(.vertical, theme.spacing(.xs))
        .frame(width: 340)
        .frame(maxHeight: max(maxHeight, Self.floorHeight), alignment: .top)
        .background(theme.color(.surfaceCard))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                .strokeBorder(theme.color(.borderSubtle), lineWidth: 1)
        )
        .themedShadow(.raised)
    }

    // MARK: The rows

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isCommandList {
                        section("SCRIVI", writing)
                        section("COMANDI", appCommands)
                    } else {
                        rows(numbered)
                    }
                }
            }
            // Capped rather than unbounded even when the screen would allow more: past this
            // the panel covers the note it is being used to write, and the list scrolls
            // anyway. The room beside the caret caps it again, lower, when there is less.
            .frame(maxHeight: 320)
            // `onAppear`, not `onChange`, and that is the whole fix: `CompletionPanel.render`
            // builds a brand-new `NSHostingView` on every arrow key, so this view never
            // *changes* selection - each instance is born with one. `onChange` therefore
            // never fired, the list never scrolled, and the highlight walked off the bottom
            // edge while the rows stood still. Seen on screen on 2026-08-18.
            //
            // No anchor: SwiftUI then scrolls the least it can to bring the row into view,
            // which is right in both directions. `.bottom` was the previous value and would
            // jerk the list on the way back up.
            .onAppear { proxy.scrollTo(selectedIndex) }
            .onChange(of: selectedIndex) { _, index in
                // Kept for the day the hosting view outlives a keystroke; harmless until then.
                proxy.scrollTo(index)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ entries: [(offset: Int, element: CompletionItem)]) -> some View {
        if !entries.isEmpty {
            Text(title)
                .themedText(.caption, color: .textTertiary)
                .padding(.horizontal, theme.spacing(.s))
                .padding(.top, theme.spacing(.s))
                .padding(.bottom, theme.spacing(.xs))
                .frame(maxWidth: .infinity, alignment: .leading)
            rows(entries)
        }
    }

    private func rows(_ entries: [(offset: Int, element: CompletionItem)]) -> some View {
        ForEach(entries, id: \.offset) { entry in
            row(entry.element, isSelected: entry.offset == selectedIndex)
                .id(entry.offset)
        }
    }

    private func row(_ item: CompletionItem, isSelected: Bool) -> some View {
        HStack(spacing: theme.spacing(.s)) {
            if case .emoji(let glyph, _) = item {
                // The glyph itself, which is the whole point of this row: choosing an emoji
                // by its name alone is choosing blind. SPEC §11.2 keeps emoji out of the
                // app's chrome and names this the exception - a picker showing what it is
                // about to insert is showing content.
                Text(glyph).frame(width: 16)
            } else {
                Image(systemName: item.symbol)
                    .frame(width: 16)
                    .foregroundStyle(theme.color(isSelected ? .textPrimary : .textSecondary))
            }
            Text(item.title)
                .themedText(.body, color: isSelected ? .textPrimary : .textSecondary)
                .lineLimit(1)
            Spacer(minLength: theme.spacing(.s))
            if let shortcut = item.shortcutCaption {
                Text(shortcut).themedText(.caption, color: .textTertiary)
            }
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .fill(isSelected ? theme.color(.accentMuted) : .clear)
                .padding(.horizontal, theme.spacing(.xs) / 2)
        )
        // The whole row, gaps included, not only where a glyph happens to be drawn.
        // AppKit's completion list could be clicked and this panel replaced it, so losing
        // the mouse here would be a regression for `[[` even though the slash menu never
        // had it.
        .contentShape(Rectangle())
        .onTapGesture { onChoose(item) }
    }

    /// Says what was typed and what it did not match, rather than showing an empty box.
    ///
    /// An empty list is indistinguishable from a broken one, which is the confusion
    /// ADR-0009 §D1 refuses for a view that matches nothing. Worth refusing twice.
    ///
    /// Reached for the two closed catalogues, commands and emoji, and for neither of the
    /// open-ended lists: `CompletingTextView.Context.noMatch` is where that is decided and
    /// says why. The sentence arrives already agreeing with its own noun, which is why this
    /// composes a phrase rather than inserting a word.
    private var nothingMatched: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("\(noMatch ?? "Nessun risultato") per «\(query)»").themedText(.body, color: .textSecondary)
            Text("Esc chiude e lascia il testo com'era")
                .themedText(.caption, color: .textTertiary)
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The keys, and - for a catalogue - the fact that typing narrows it.
    ///
    /// A search row at the top said the same thing and was tried first. It duplicated the
    /// query two centimetres from where the person was already reading it, in the note beside
    /// the caret: `:pac` on one line and `pac` on the next. What was actually missing shows
    /// only in the empty state, where `:` alone opens ninety-six rows with nothing to say that
    /// typing filters them - and a row that appears only when empty makes the panel jump by
    /// its own height on the first keystroke. The footer is already here, already teaches the
    /// keys, and never moves.
    ///
    /// Over an empty list only «esc» is left. The other two name a row to move to and a row to
    /// insert, and there is no row - a legend for keys that do nothing, on the one panel whose
    /// whole purpose at that moment is to say plainly that it has nothing. Seen on screen on
    /// 2026-08-18, on `/zzz` as much as on `:zqx`: it predates this change and was simply
    /// rarer before.
    private var footer: some View {
        HStack(spacing: theme.spacing(.s)) {
            if showsRowKeys {
                Text("↑↓ scegli").themedText(.caption, color: .textTertiary)
                Text("↩ inserisci").themedText(.caption, color: .textTertiary)
            }
            if showsFilterHint {
                Text("scrivi per filtrare").themedText(.caption, color: .textTertiary)
            }
            Spacer()
            Text("esc").themedText(.caption, color: .textTertiary)
        }
        .padding(.horizontal, theme.spacing(.s))
    }

    /// Whether the two keys that act on a row are worth naming, which is whether there is a
    /// row. Internal rather than private so a test can hold the rule: what the footer draws
    /// from it was checked on screen.
    var showsRowKeys: Bool { !items.isEmpty }

    /// The emoji list, and only it.
    ///
    /// The slash menu is also a catalogue narrowed by typing and would read the same, but its
    /// look was approved without this line (SPEC §11.1) and `SlashMenuMockup` draws a panel of
    /// its own - so adding it here would leave the shipped panel and the approved mockup
    /// quietly different. It goes there through a mockup or not at all. After `[[` or `#`
    /// there is nothing to explain: the query is the note's own text, beside the caret.
    private var showsFilterHint: Bool {
        items.contains { item in
            if case .emoji = item { return true }
            return false
        }
    }

    /// A panel shorter than this is not a list any more. A caret with almost no room on
    /// either side gets a panel that hangs off the screen edge rather than a sliver.
    private static let floorHeight: CGFloat = 120

    // MARK: The two shapes

    /// One kind of row per panel: a context offers commands or candidates, never both.
    private var isCommandList: Bool { items.contains(where: \.isCommand) }

    /// Indices are kept alongside the entries because the selection is an index into the
    /// flat list the keyboard walks, not into either half.
    private var numbered: [(offset: Int, element: CompletionItem)] {
        items.enumerated().map { ($0.offset, $0.element) }
    }

    private var writing: [(offset: Int, element: CompletionItem)] {
        numbered.filter { entry in
            guard case .command(let command) = entry.element else { return false }
            if case .insert = command.action { return true }
            return false
        }
    }

    private var appCommands: [(offset: Int, element: CompletionItem)] {
        numbered.filter { entry in
            guard case .command(let command) = entry.element else { return false }
            if case .app = command.action { return true }
            return false
        }
    }
}
