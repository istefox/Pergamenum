import SwiftUI

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 6 -
// R-33; DESIGN.md screen 1a, UX-BLUEPRINT "Navigation structure" (pane list column).
//
// The pane's own list column: client folder rows with a hand-drawn chevron, pratica
// rows under them, and «Chiuse» at the bottom for `status-archived`/`status-final`.
//
// **Flat recursive rows, never a `DisclosureGroup`** (CLAUDE.md's own trap, ADR-0024):
// a `DisclosureGroup`'s label is not a row of the enclosing `List`, so a `.tag` on it
// satisfies no binding and the column would light nothing and swallow every click.
// The client row is the same shape the note sidebar's folder rows use - drawn by hand,
// carrying no `.tag`, structurally unselectable.
struct PraticheListColumn: View {
    @Environment(\.theme) private var theme
    @Environment(PraticheController.self) private var pratiche
    @Environment(VaultController.self) private var vault

    /// The pane's one command runner, so every row's context menu draws the catalogue
    /// rather than a hand-written copy of it (ADR-0023 §D1).
    let actions: PraticaCommandActions
    /// «Nuova pratica…» - the same command the File menu and Cmd+Opt+P reach, handed
    /// in by the pane so this column owns no second creation path.
    let onNewPratica: () -> Void

    @State private var filter = ""
    @State private var collapsedClients: Set<String> = []
    /// Closed pratiche are collapsed on open (R-33): they are the ones a person is not
    /// working on.
    @State private var isShowingClosed = false

    var body: some View {
        VStack(spacing: 0) {
            header
            // A sibling row of the header, never a child of it (ADR-0022 §D8): the
            // header's own `accessibilityElement(children: .contain)` would otherwise
            // propagate its identifier onto every button placed inside it.
            toolbarRow
            filterField
            Divider()
            list
        }
        .background(theme.color(.backgroundSecondary))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-list")
    }

    private var header: some View {
        HStack(spacing: theme.spacing(.s)) {
            Text("Pratiche").themedText(.heading)
            Spacer()
            Text(countText).themedText(.caption, color: .textTertiary)
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.top, theme.spacing(.s))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-list-header")
    }

    private var countText: String {
        pratiche.pratiche.count == 1 ? "1 pratica" : "\(pratiche.pratiche.count) pratiche"
    }

    private var toolbarRow: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Button(action: onNewPratica) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .disabled(vault.root == nil)
            .help("Nuova pratica…")
            .accessibilityLabel("Nuova pratica…")
            .accessibilityIdentifier("pratiche-new")

            // Every pratica, not the chosen one: the top bar's own «Aggiorna ora»
            // (`pratiche-refresh`) is the per-pratica verb, and two controls answering
            // to one identifier is a UI test that finds whichever it meets first.
            Button {
                Task { await pratiche.syncAll(in: vault, kind: .manualRefresh) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(pratiche.pratiche.isEmpty)
            .help("Aggiorna tutte le pratiche")
            .accessibilityLabel("Aggiorna tutte le pratiche")
            .accessibilityIdentifier("pratiche-refresh-all")

            Spacer()
        }
        .padding(.horizontal, theme.spacing(.m))
        .padding(.vertical, theme.spacing(.xs))
    }

    private var filterField: some View {
        TextField("Filtra pratiche", text: $filter)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, theme.spacing(.m))
            .padding(.bottom, theme.spacing(.xs))
            .accessibilityIdentifier("pratiche-list-filter")
    }

    private var list: some View {
        // Filtered, grouped and sorted once per redraw, the way `TasksView+List` binds
        // `rolled`: every read of `grouped` is a pass over every pratica plus two sorts,
        // and the open rows, the «Chiuse» heading and its rows all want the same answer.
        let grouped = self.grouped
        return List(selection: selection) {
            ForEach(grouped.open) { group in
                clientRow(group)
                if !collapsedClients.contains(group.client) {
                    ForEach(group.pratiche) { pratica in
                        praticaRow(pratica, depth: 1)
                    }
                }
            }
            if !grouped.closed.isEmpty {
                closedRow(count: grouped.closed.count)
                if isShowingClosed {
                    ForEach(grouped.closed) { pratica in
                        praticaRow(pratica, depth: 1)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    /// No `.tag`: a client is a folder, not a destination. Clicking it opens and closes
    /// the group, which is the whole of what it does.
    private func clientRow(_ group: PraticaClientGroup) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: collapsedClients.contains(group.client) ? "chevron.right" : "chevron.down")
                .themedText(.caption, color: .textTertiary)
            Text(group.client).themedText(.caption, color: .textSecondary)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(client: group.client) }
        .accessibilityIdentifier("pratiche-client-\(group.client)")
    }

    private func closedRow(count: Int) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: isShowingClosed ? "chevron.down" : "chevron.right")
                .themedText(.caption, color: .textTertiary)
            Text("Chiuse \(count)").themedText(.caption, color: .textSecondary)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { isShowingClosed.toggle() }
        .accessibilityIdentifier("pratiche-closed")
    }

    /// `.badge` **before** `.tag`, and the order is the whole thing: applied after it,
    /// `.badge` drops the tag, the `List` falls back to the `ForEach`'s implicit id and
    /// no row can ever equal the selection (`RootView.swift`'s own note, ADR-0024).
    private func praticaRow(_ pratica: PraticaListItem, depth: Int) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            // The dot: this pratica has proposals waiting in its tray (R-33). Task 7
            // fills `trayCounts`; empty means no dot, never a wrong one.
            Circle()
                .fill(theme.color(.accentPrimary))
                .frame(width: 6, height: 6)
                .opacity(pratica.hasNonEmptyTray ? 1 : 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(pratica.title).themedText(.body).lineLimit(1)
                Text(PraticaRowFormat.day(pratica.lastActivity))
                    .themedText(.caption, color: .textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * theme.spacing(.s))
        // On the row's own body and never on a container of it (ADR-0023 §D2): a menu
        // placed higher up reaches every descendant row and would offer this pratica's
        // «Elimina» from the client heading above it.
        .contextMenu { PraticaMenuItems.menu(for: pratica, actions: actions) }
        .accessibilityIdentifier("pratiche-row-\(pratica.id)")
        .badge(pratica.messagesSinceLastOpen)
        .tag(pratica.id)
    }

    // MARK: - Model

    private var grouped: (open: [PraticaClientGroup], closed: [PraticaListItem]) {
        PraticheSidebarGrouping.grouped(filtered)
    }

    /// The filter narrows on title and client both: a person types «Rossi» meaning
    /// either, and a column that answered only one of them would look broken.
    private var filtered: [PraticaListItem] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return pratiche.pratiche }
        return pratiche.pratiche.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.client.localizedCaseInsensitiveContains(needle)
        }
    }

    /// Choosing a row goes through `select(_:in:)`, which also re-reads the timeline
    /// and marks the pratica opened - the badge going out is that write (R-33).
    private var selection: Binding<String?> {
        Binding(
            get: { pratiche.selection },
            set: { pratiche.select($0, in: vault) }
        )
    }

    private func toggle(client: String) {
        if collapsedClients.contains(client) {
            collapsedClients.remove(client)
        } else {
            collapsedClients.insert(client)
        }
    }
}
