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
            .onChange(of: selectedIndex) { _, index in
                // Arrowing past the visible edge has to bring the row into view, or the
                // highlight walks off the bottom and the list looks stuck.
                proxy.scrollTo(index, anchor: .bottom)
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
            Image(systemName: item.symbol)
                .frame(width: 16)
                .foregroundStyle(theme.color(isSelected ? .textPrimary : .textSecondary))
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
    /// Reached for commands only. A `[[` or `#` that matches nothing hides the panel
    /// instead, which is what AppKit's list did and the right answer there: the candidates
    /// are the vault's own notes and tags, so "no match" while typing a title that does
    /// not exist yet is the ordinary case, not a dead end worth a box.
    private var nothingMatched: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("Nessun comando per «\(query)»").themedText(.body, color: .textSecondary)
            Text("Esc chiude e lascia il testo com'era")
                .themedText(.caption, color: .textTertiary)
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: theme.spacing(.s)) {
            Text("↑↓ scegli").themedText(.caption, color: .textTertiary)
            Text("↩ inserisci").themedText(.caption, color: .textTertiary)
            Spacer()
            Text("esc").themedText(.caption, color: .textTertiary)
        }
        .padding(.horizontal, theme.spacing(.s))
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
