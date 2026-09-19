import SwiftUI

// MARK: - Il menu comandi (M8)

/// The slash menu with the app's own appearance, before it exists.
///
/// The menu already works: `/` opens AppKit's completion list, which handles arrow keys,
/// Escape, scrolling and placement for free. What it cannot do is look like this app - a
/// system list takes no design tokens, shows no icons, and highlights with the system blue
/// instead of the accent. `EditorCommand.symbol` has been carrying an SF Symbol for every
/// command since the first slice with nothing to draw it.
///
/// Four scenes, because what has to be judged is not one screen. Whether forty-three
/// entries read as two halves rather than as a wall. Whether a filtered list still tells
/// you what it filtered. What "nothing matched" looks like, which is the state a list gets
/// wrong most often. And whether the panel reads as belonging to the note it opens in,
/// which is why every scene draws it over text rather than on a plain background.
struct SlashMenuMockup: View {
    @Environment(\.theme) private var theme

    var body: some View {
        MockupPage {
            scene(
                "Appena premuto «/», con le due metà del catalogo",
                SlashPanelMock(state: .open)
            )
            scene(
                "«/ta», filtrato mentre si scrive",
                SlashPanelMock(state: .filtered)
            )
            scene(
                "«/xyz», nessuna corrispondenza",
                SlashPanelMock(state: .empty)
            )
            scene(
                "Un comando che l'app non può eseguire adesso non compare",
                SlashPanelMock(state: .noVault)
            )
        }
    }

    private func scene(_ caption: String, _ panel: SlashPanelMock) -> some View {
        MockupScene(caption) {
            ZStack(alignment: .topLeading) {
                NoteBackdrop()
                panel.padding(.leading, 96).padding(.top, 92)
            }
        }
    }
}

// MARK: - The panel

private struct SlashPanelMock: View {
    @Environment(\.theme) private var theme

    enum State { case open, filtered, empty, noVault }

    let state: State

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                nothingMatched
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    switch row {
                    case .header(let title): header(title)
                    case .command(let item): self.row(item, isSelected: index == selectedIndex)
                    }
                }
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

    // MARK: A row

    /// The first command in the list, not the first line: a section header cannot be
    /// chosen, and a selection sitting on one would be a list that starts unusable.
    private var selectedIndex: Int {
        rows.firstIndex { if case .command = $0 { return true } else { return false } } ?? 0
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .themedText(.caption, color: .textTertiary)
            .padding(.horizontal, theme.spacing(.s))
            .padding(.top, theme.spacing(.s))
            .padding(.bottom, theme.spacing(.xs))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ item: Item, isSelected: Bool) -> some View {
        HStack(spacing: theme.spacing(.s)) {
            // The icon is the reason this panel exists rather than the system one: at a
            // glance it separates "writes something here" from "does something to the app"
            // faster than any wording could.
            Image(systemName: item.symbol)
                .frame(width: 16)
                .foregroundStyle(theme.color(isSelected ? .textPrimary : .textSecondary))
            Text(item.title)
                .themedText(.body, color: isSelected ? .textPrimary : .textSecondary)
            Spacer(minLength: theme.spacing(.s))
            // Shown only where it exists, and it teaches: a person who reaches a command
            // by typing learns the key that would have got them there without the menu.
            if let shortcut = item.shortcut {
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

    // MARK: The two states a list usually gets wrong

    /// Says what was typed and what it means, rather than showing an empty box.
    ///
    /// An empty list is indistinguishable from a broken one - the same confusion ADR-0009
    /// §D1 refuses for a view that matches nothing, and it is worth refusing twice.
    private var nothingMatched: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            Text("Nessun comando per «xyz»").themedText(.body, color: .textSecondary)
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

    // MARK: What each scene shows

    private enum Row {
        case header(String)
        case command(Item)
    }

    private struct Item {
        let title: String
        let symbol: String
        var shortcut: String?
    }

    private var rows: [Row] {
        switch state {
        case .open:
            [
                .header("SCRIVI"),
                .command(Item(title: "Titolo 1", symbol: "textformat.size.larger")),
                .command(Item(title: "Titolo 2", symbol: "textformat.size")),
                .command(Item(title: "Elenco puntato", symbol: "list.bullet")),
                .command(Item(title: "Task", symbol: "checklist")),
                .command(Item(title: "Blocco di codice", symbol: "curlybraces")),
                .command(Item(title: "Tabella", symbol: "tablecells")),
                .header("COMANDI"),
                .command(Item(title: "Nuova nota", symbol: "square.and.pencil", shortcut: "⌘N")),
                .command(Item(title: "Nota di oggi", symbol: "calendar", shortcut: "⌘T")),
                .command(Item(title: "Verifica conformità", symbol: "checkmark.seal", shortcut: "⌃⌘L")),
            ]
        case .filtered:
            [
                .header("SCRIVI"),
                .command(Item(title: "Tabella", symbol: "tablecells")),
                .command(Item(title: "Task", symbol: "checklist")),
                .command(Item(title: "Tag", symbol: "number")),
                .header("COMANDI"),
                .command(Item(title: "Nuovo task rapido", symbol: "checklist", shortcut: "⇧⌘N")),
                .command(Item(title: "Vai ad Attività", symbol: "checklist", shortcut: "⌃⌘4")),
            ]
        case .empty:
            []
        case .noVault:
            // No vault open, so everything that needs one is absent - and the writing
            // half is untouched, because `## ` works with no notes folder at all.
            [
                .header("SCRIVI"),
                .command(Item(title: "Titolo 1", symbol: "textformat.size.larger")),
                .command(Item(title: "Titolo 2", symbol: "textformat.size")),
                .command(Item(title: "Elenco puntato", symbol: "list.bullet")),
                .header("COMANDI"),
                .command(Item(title: "Apri cartella note", symbol: "folder", shortcut: "⇧⌘O")),
                .command(Item(title: "Vai a Note", symbol: "doc.text", shortcut: "⌃⌘1")),
            ]
        }
    }
}

// MARK: - The note the menu opens in

/// A stand-in for the note being written, with the `/` where the caret is.
///
/// Not the dull grey blocks the capture mockup floats over: that panel appears over
/// another application and this one appears inside our own editor, so the thing to judge
/// is whether it sits in the text rather than on top of it.
private struct NoteBackdrop: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text("Mescole per il forno").themedText(.heading)
            Text("Il fornitore ha confermato la curva di trasmissibilità.")
                .themedText(.body, color: .textSecondary)
            HStack(spacing: 0) {
                Text("/").themedText(.body)
                Rectangle().fill(theme.color(.accentPrimary)).frame(width: 1, height: 16)
            }
            Spacer(minLength: 0)
        }
        .padding(theme.spacing(.m))
        .frame(height: 460)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(.backgroundSecondary))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous))
    }
}
