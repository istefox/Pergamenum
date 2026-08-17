import SwiftUI

/// The slash menu's list, as the approved mockup drew it (M8).
///
/// Two halves with a heading each, because forty-three flat rows is a wall; an icon per
/// row, because at a glance it separates "writes something here" from "does something to
/// the app" faster than any wording; and the keyboard shortcut on the right where one
/// exists, because a person who reached a command by typing learns the key that would have
/// got them there without the menu.
struct SlashMenuView: View {
    @Environment(\.theme) private var theme

    let commands: [EditorCommand]
    let query: String
    let selectedIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if commands.isEmpty {
                nothingMatched
            } else {
                list
            }
            Divider().padding(.vertical, theme.spacing(.xs))
            footer
        }
        .padding(.vertical, theme.spacing(.xs))
        .frame(width: 340)
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
                    section("SCRIVI", writing)
                    section("COMANDI", appCommands)
                }
            }
            // Capped rather than unbounded: past this the panel covers the note it is
            // being used to write, and the list scrolls anyway.
            .frame(maxHeight: 320)
            .onChange(of: selectedIndex) { _, index in
                // Arrowing past the visible edge has to bring the row into view, or the
                // highlight walks off the bottom and the list looks stuck.
                proxy.scrollTo(index, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ entries: [(offset: Int, element: EditorCommand)]) -> some View {
        if !entries.isEmpty {
            Text(title)
                .themedText(.caption, color: .textTertiary)
                .padding(.horizontal, theme.spacing(.s))
                .padding(.top, theme.spacing(.s))
                .padding(.bottom, theme.spacing(.xs))
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(entries, id: \.offset) { entry in
                row(entry.element, isSelected: entry.offset == selectedIndex)
                    .id(entry.offset)
            }
        }
    }

    private func row(_ command: EditorCommand, isSelected: Bool) -> some View {
        HStack(spacing: theme.spacing(.s)) {
            Image(systemName: command.symbol)
                .frame(width: 16)
                .foregroundStyle(theme.color(isSelected ? .textPrimary : .textSecondary))
            Text(command.title)
                .themedText(.body, color: isSelected ? .textPrimary : .textSecondary)
                .lineLimit(1)
            Spacer(minLength: theme.spacing(.s))
            if let shortcut = command.shortcutCaption {
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
    }

    /// Says what was typed and what it did not match, rather than showing an empty box.
    ///
    /// An empty list is indistinguishable from a broken one, which is the confusion
    /// ADR-0009 §D1 refuses for a view that matches nothing. Worth refusing twice.
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

    // MARK: The two halves

    /// Indices are kept alongside the entries because the selection is an index into the
    /// flat list the keyboard walks, not into either half.
    private var writing: [(offset: Int, element: EditorCommand)] {
        commands.enumerated().filter { entry in
            if case .insert = entry.element.action { return true }
            return false
        }
        .map { ($0.offset, $0.element) }
    }

    private var appCommands: [(offset: Int, element: EditorCommand)] {
        commands.enumerated().filter { entry in
            if case .app = entry.element.action { return true }
            return false
        }
        .map { ($0.offset, $0.element) }
    }
}
