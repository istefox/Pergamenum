import SwiftUI

/// The tabs of the Note pane, drawn as the mockup approved on 2026-08-19 (ADR-0012 D1).
///
/// **It takes the editor header's place rather than sitting above it.** The header showed the
/// note's title, and so does a tab; keeping both would put the title on screen twice and spend
/// sixty points of the editor's height saying it. What the header carried and a tab cannot -
/// the path, the Modifica/Lettura choice, the save state - is here too: the path on a line of
/// its own under the strip, the other two at the strip's right end.
///
/// The bar is present with one note open as with six. That costs nothing now that it replaced
/// the header, and it means nothing on screen moves when the second note arrives.
struct NoteTabBar: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    /// Asked before a tab with unsaved changes is closed (ADR-0012 D3). The dialog belongs to
    /// the pane, which can show one; this view only says which tab was aimed at.
    let onCloseRequested: (NoteTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            strip
            Divider()
            if let note = vault.openNote {
                Text(note.relativePath)
                    .themedText(.caption, color: .textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, theme.spacing(.s))
                    .padding(.vertical, theme.spacing(.xs))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Scrolls rather than shrinking: a tab narrow enough to fit twelve of them is a tab whose
    /// title cannot be read, and Cmd+1…Cmd+9 reaches the ones off the edge anyway.
    private var strip: some View {
        HStack(spacing: theme.spacing(.xs)) {
            ScrollView(.horizontal) {
                HStack(spacing: theme.spacing(.xs)) {
                    ForEach(tabs) { tab in
                        NoteTabChip(
                            tab: tab,
                            isActive: tab.id == vault.focusedTab?.id,
                            onSelect: { vault.focusTab(tab.id) },
                            onMakeStable: { vault.makeStable(tab.id) },
                            onClose: { onCloseRequested(tab) }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)

            Button { vault.beginNewTab() } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.color(.textTertiary))
            .help("Nuova tab")
            .accessibilityLabel("Nuova tab")
            .accessibilityIdentifier("new-tab")

            if vault.openNote != nil {
                // The two the header carried, unchanged in behaviour and moved in place.
                Picker("", selection: Bindable(vault).isReadingMode) {
                    Text("Modifica").tag(false)
                    Text("Lettura").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                if vault.openNote?.hasUnsavedChanges == true {
                    Button("Salva", action: vault.saveOpenNote)
                } else {
                    Label("Salvato", systemImage: "checkmark.circle")
                        .themedText(.caption, color: .textSecondary)
                }
            }
        }
        .padding(.horizontal, theme.spacing(.xs))
        .padding(.vertical, theme.spacing(.xs))
        .background(theme.color(.backgroundSecondary))
    }

    private var tabs: [NoteTab] {
        vault.columns.indices.contains(vault.focusedColumnIndex)
            ? vault.columns[vault.focusedColumnIndex].tabs
            : []
    }
}

/// One tab: a dot when the note has unsaved edits, its title, and a close button.
private struct NoteTabChip: View {
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    let tab: NoteTab
    let isActive: Bool
    let onSelect: () -> Void
    let onMakeStable: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            if tab.note.hasUnsavedChanges {
                Circle()
                    .fill(theme.color(.accentPrimary))
                    .frame(width: 8, height: 8)
                    .help("Modifiche non salvate")
                    .accessibilityLabel("\(tab.note.title), modifiche non salvate")
            }
            Text(tab.note.title)
                // `.body` and not `.caption`: 11 points is a label under something, and this
                // is the name of what you are reading. Safari and Xcode both title a tab at
                // the body size, and at 11 the row read as a caption strip.
                .themedText(.body, color: isActive ? .textPrimary : .textSecondary)
                // Weight as well as fill: in the light theme `accentMuted` and `surfaceSunken`
                // sit at almost the same luminance, so the colour alone carries the active tab
                // in the dark theme and barely in the other. Weight reads in both.
                .fontWeight(isActive ? .semibold : .regular)
                // Italic says "this one is on its way out": the next single click in the list
                // reuses this tab. VS Code's convention, and the only cue that distinguishes
                // a preview from a tab that will still be here in ten minutes.
                .italic(tab.isPreview)
                .lineLimit(1)
                .truncationMode(.tail)
                // The title is what decides the width, up to a cap: a fixed 168 left «test»
                // sitting in a 168-point slot, so short titles floated far apart with nothing
                // between them and the bar read as scattered words rather than as tabs.
                .frame(maxWidth: 160, alignment: .leading)
            closeButton
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.xs))
        .frame(minWidth: 72, alignment: .leading)
        .background(background)
        // The whole chip is the target, not only the glyphs on it: a `.clear` background
        // leaves a SwiftUI button clickable on its own drawing alone.
        .contentShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        // Declared before the single tap: SwiftUI resolves the higher count first, and the
        // other order swallows the double click entirely.
        //
        // Safe here and *not* on a row of the note list, where the same pair broke the click
        // that opens a note: inside a `List` the single tap belongs to the selection, and a
        // count-2 gesture waiting to see whether a second click arrives holds it up long
        // enough to lose it. Found by clicking, on 2026-08-19; no unit test reaches this.
        .onTapGesture(count: 2, perform: onMakeStable)
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .accessibilityIdentifier("note-tab")
    }

    /// The close button, shown on the active tab and under the pointer, so a row of tabs
    /// reads as titles rather than as a row of crosses.
    ///
    /// **The unsaved dot used to live here, in the close button's place, and that was wrong
    /// in a way only using it showed.** It was hidden while the pointer was on the tab - which
    /// is precisely when someone is looking at that tab to check. A mark that disappears when
    /// examined is not a mark. It sits before the title now, where nothing takes its place.
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .themedText(.caption, color: .textTertiary)
        }
        .buttonStyle(.plain)
        .opacity(isActive || isHovering ? 1 : 0)
        .help("Chiudi la tab")
        .accessibilityLabel("Chiudi \(tab.note.title)")
    }

    /// Every tab has a shape; the active one has the accent.
    ///
    /// The inactive ones were transparent, which left the bar as words floating at intervals
    /// with no telling where one tab ended and the next began - the gaps between short titles
    /// read as separation between groups rather than between tabs. `surfaceSunken` gives them
    /// an edge without competing with the active one, which keeps `accentMuted`: the grey
    /// alone said "a tab", not "*this* tab".
    ///
    /// Both are tokens, in both themes, because a view that picks a colour does not pass
    /// review (design system rule).
    private var background: some View {
        RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
            .fill(theme.color(isActive ? .accentMuted : .surfaceSunken))
    }
}
