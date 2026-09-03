import SwiftUI

/// The tabs of the Note pane, drawn as the mockup approved on 2026-08-19 (ADR-0012 D1).
///
/// **It takes the editor header's place rather than sitting above it.** The header showed the
/// note's title, and so does a tab; keeping both would put the title on screen twice and spend
/// sixty points of the editor's height saying it. What the header carried and a tab cannot -
/// the save state - is here too, at the strip's right end. The Modifica/Lettura choice was
/// there beside it until ADR-0029 §D13: there is one editor now, always editable and always
/// styled, so there is no mode left to choose.
///
/// The bar is present with one note open as with six. That costs nothing now that it replaced
/// the header, and it means nothing on screen moves when the second note arrives.
///
/// **The path no longer lives here (2026-08-28, breadcrumb parity chain).** It moved up to
/// `VaultTopBar`, the strip above the whole Note pane - one path shown once, at pane level,
/// rather than once per column. The trade-off is deliberate and asymmetric: with the editor
/// split in two, the top bar follows only the focused column (`VaultController.breadcrumb`
/// reads `openNote`, which resolves through `focusedTab`), so the unfocused column's path is
/// not shown anywhere until it is clicked into.
struct NoteTabBar: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    /// Which column this bar belongs to (ADR-0012 D4). The bar of the column without the
    /// focus is dimmed rather than absent: it still says what is open over there.
    let columnIndex: Int
    /// Asked before a tab with unsaved changes is closed (ADR-0012 D3). The dialog belongs to
    /// the column, which can show one; this view only says which tab was aimed at.
    let onCloseRequested: (NoteTab) -> Void

    private var isFocused: Bool { vault.focusedColumnIndex == columnIndex }

    var body: some View {
        strip
    }

    /// Scrolls rather than shrinking: a tab narrow enough to fit twelve of them is a tab whose
    /// title cannot be read, and Cmd+1…Cmd+9 reaches the ones off the edge anyway.
    private var strip: some View {
        HStack(spacing: theme.spacing(.xs)) {
            ScrollView(.horizontal) {
                HStack(spacing: theme.spacing(.xs)) {
                    ForEach(tabs) { tab in
                        NoteTabChip(
                            // Only the focused column's active tab wears the accent. Two tabs
                            // marked active in one window is two answers to "where am I".
                            tab: tab,
                            isActive: isFocused && tab.id == activeID,
                            onSelect: { focus { vault.focusTab(tab.id) } },
                            onMakeStable: { focus { vault.makeStable(tab.id) } },
                            onClose: { focus { onCloseRequested(tab) } }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)

            // No «+» on the bar, deliberately. It opened the quick switcher, which is a third
            // search field beside the filter above the list and the global search, for a note
            // either of those already opens. Cmd+T still does it from the keyboard.
            if activeID != nil {
                // The save state the header used to carry, moved in place. The
                // Modifica/Lettura picker stood beside it until ADR-0029 §D13 removed the
                // mode itself.
                //
                // **A glyph and not a word, because of the split.** Spelled out, these
                // controls took some 230 points of a column that is 585 wide when the editor
                // is divided, and two tabs were all that fitted beside them. The word survives
                // as the accessibility label of the `Label`, which is also what the UI tests
                // click on.
                if tabs.first(where: { $0.id == activeID })?.note.hasUnsavedChanges == true {
                    Button { focus { vault.saveOpenNote() } } label: {
                        Label("Salva", systemImage: "arrow.down.doc")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.color(.textSecondary))
                    .help("Salva la nota")
                } else {
                    Label("Salvato", systemImage: "checkmark.circle")
                        .labelStyle(.iconOnly)
                        .themedText(.caption, color: .textSecondary)
                        .help("Salvato")
                }
            }
        }
        .padding(.horizontal, theme.spacing(.xs))
        .padding(.vertical, theme.spacing(.xs))
        // Lit when this column has the focus, sunken when it does not: the index in the sidebar,
        // the inspector and every menu command answer for the focused column, so which one it is
        // has to be legible without clicking to find out.
        //
        // `surfaceSunken` and not `backgroundPrimary`, which is what this was: against
        // `backgroundSecondary` that is #1A1917 against #222120 in the dark theme, eight points
        // per channel, which is nothing on a screen. The accent on the active tab was carrying
        // the whole signal alone.
        .background(theme.color(isFocused ? .backgroundSecondary : .surfaceSunken))
    }

    private var column: EditorColumn? {
        vault.columns.indices.contains(columnIndex) ? vault.columns[columnIndex] : nil
    }

    private var tabs: [NoteTab] { column?.tabs ?? [] }
    private var activeID: NoteTab.ID? { column?.activeID }

    /// Anything done on this bar is done in this column, so the click takes the focus first.
    private func focus(_ change: () -> Void) {
        vault.focusColumn(columnIndex)
        change()
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

    /// **The padding lives inside the two halves, not on the chip.** The tab's gestures cannot
    /// sit on the chip: a `count: 2` gesture on an ancestor holds a click while it waits to see
    /// whether a second one arrives, and the × underneath it needed two or three clicks before
    /// one got through. Moving them onto the title alone fixed that and shrank the target to the
    /// width of the word - clicking beside «Delta» did nothing. So the chip is now two areas
    /// that each carry their own padding: everything up to the button selects the tab, the
    /// button closes it, and the whole rectangle is live.
    var body: some View {
        HStack(spacing: 0) {
            title
                .padding(.leading, theme.spacing(.s))
                .padding(.trailing, theme.spacing(.xs))
                .padding(.vertical, theme.spacing(.xs))
                .frame(minWidth: 64, alignment: .leading)
                .contentShape(Rectangle())
                // Declared before the single tap: SwiftUI resolves the higher count first, and
                // the other order swallows the double click entirely.
                .onTapGesture(count: 2, perform: onMakeStable)
                .onTapGesture(perform: onSelect)
            closeButton
                .padding(.trailing, theme.spacing(.s))
                .padding(.vertical, theme.spacing(.xs))
        }
        .background(background)
        .onHover { isHovering = $0 }
        .accessibilityIdentifier("note-tab")
    }

    private var title: some View {
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
        }
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
