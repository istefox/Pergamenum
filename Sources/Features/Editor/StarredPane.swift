import SwiftUI

/// The starred notes, as a place (ADR-0012 §D6).
///
/// They already had a section at the top of the note list, which is the right home for
/// them while you are reading notes. What they did not have is a *destination*: the
/// sidebar row that opened that section landed on the Note pane, so the highlight moved
/// to «Note» and the click read as one that had gone nowhere.
///
/// The list is `vault.starredNotes`, the same one the section draws, so starring in
/// either place shows in both without anything being kept twice.
struct StarredPane: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation
    /// For the empty state, which names the key that puts a star on a note - the user's
    /// own binding, never the default, or the pane would teach a shortcut that does
    /// nothing.
    @Environment(ShortcutStore.self) private var shortcuts
    @Environment(ThemeEngine.self) private var themeEngine

    private var notes: [NoteRecord] { vault.starredNotes }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.s)) {
                header
                if notes.isEmpty { empty }
                ForEach(notes, id: \.relativePath) { note in
                    row(note)
                }
            }
            .padding(theme.spacing(.l))
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.color(.backgroundPrimary))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("starred-pane")
        .toolbar { ToolbarItemGroup(placement: .primaryAction) { themeToggleToolbarItem(themeEngine) } }
    }

    private var header: some View {
        HStack(spacing: theme.spacing(.s)) {
            Text("Preferite").themedText(.title)
            Text(notes.count == 1 ? "1 nota" : "\(notes.count) note")
                .themedText(.caption, color: .textTertiary)
            Spacer()
        }
        .padding(.bottom, theme.spacing(.xs))
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("Nessuna nota preferita.").themedText(.body, color: .textSecondary)
            Text("""
                La stella si mette dalla nota aperta con \
                \(shortcuts.binding(for: .toggleStar).displayString), dal menu File o dal menu \
                contestuale di una riga nella lista. Le preferite stanno in \
                `.pergamenum/starred.json`, dentro il vault, quindi viaggiano con esso.
                """)
                .themedText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The note, where it lives, and when it last changed - which is what tells two
    /// notes with similar names apart in a list this short.
    private func row(_ note: NoteRecord) -> some View {
        Button { open(note) } label: {
            ThemedCard {
                HStack(alignment: .firstTextBaseline, spacing: theme.spacing(.xs)) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(theme.color(.accentPrimary))
                    Text(note.title).themedText(.body)
                    Text(note.folder.isEmpty ? "/" : note.folder)
                        .themedText(.caption, color: .textTertiary)
                    Spacer()
                    Text(modified(note)).themedText(.caption, color: .textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .help(note.relativePath)
        .contextMenu {
            Button("Togli dalle preferite") { vault.toggleStar(note.relativePath) }
        }
        .accessibilityIdentifier("starred-pane-note")
    }

    /// Opens the note where notes are read. Unlike the rows that used to do this from the
    /// sidebar, here the pane you leave is one you chose to leave.
    private func open(_ note: NoteRecord) {
        vault.openChosenNote(at: note.relativePath)
        navigation.pane = .notes
    }

    private func modified(_ note: NoteRecord) -> String {
        note.modifiedAt.formatted(
            .relative(presentation: .named).locale(Locale(identifier: "it_IT"))
        )
    }
}
