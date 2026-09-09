import SwiftUI

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 6 -
// R-32, R-33; DESIGN.md screens 1a/1c, UX-BLUEPRINT "Timeline column anatomy" §1.
//
// One strip for the whole pane, above the split and never inside a column of it - the
// same placement `VaultTopBar` has over `NoteListPane` and the editor, for the same
// reason: it is chrome of the pane, not furniture of one of its columns.
struct PraticaTopBar: View {
    @Environment(\.theme) private var theme
    @Environment(PraticheController.self) private var pratiche
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation

    /// The pane's one command runner (ADR-0023 §D1), so the status pill is a third
    /// rendering of `PraticaCommand.close`/`.reopen` rather than a hand-written swap.
    let actions: PraticaCommandActions
    /// Focus for Cmd+F, owned by the pane so `Esc` can hand it back (UX-BLUEPRINT
    /// "Keyboard shortcuts"). Task 7 wires the two shortcuts to it.
    var filterFocus: FocusState<Bool>.Binding?

    var body: some View {
        @Bindable var pratiche = pratiche
        return BreadcrumbBar(
            segments: segments,
            isUnsaved: false,
            identifierPrefix: "pratiche-crumb",
            // The only ancestor a crumb of this pane has is the pane itself, and
            // going there means "no pratica chosen" - the empty state (screen 1g).
            onSelectAncestor: { _ in pratiche.select(nil, in: vault) }
        ) {
            HStack(spacing: theme.spacing(.s)) {
                statusPill
                refreshButton
                filterField($pratiche.filter.text)
                senderMenu
                attachmentsToggle($pratiche.filter.attachmentsOnly)
                inspectorToggle
            }
        }
    }

    /// `Pratiche › <Cliente> › <Pratica>` (UX-BLUEPRINT §1). The root crumb alone
    /// while nothing is chosen, so the bar never claims a pratica that is not there.
    private var segments: [BreadcrumbSegment] {
        var segments = [BreadcrumbSegment(title: "Pratiche", folder: "")]
        guard let pratica = pratiche.selectedPratica else { return segments }
        segments.append(BreadcrumbSegment(title: pratica.client, folder: ""))
        segments.append(BreadcrumbSegment(title: pratica.title, folder: pratica.id))
        return segments
    }

    /// Reads the pratica's `status-*` (R-33/R-34's own vocabulary), and is the
    /// affordance for changing it (DESIGN.md: "Status pill in the breadcrumb bar shows
    /// the pratica's `status-*` and is the affordance for changing it").
    ///
    /// The verbs come from `PraticaCommand.available(isActive:)`, filtered to the two
    /// that change a status - never a hand-written «Chiudi»/«Riapri» pair, which is
    /// exactly the divergence the catalogue exists to prevent (ADR-0023 §D1).
    @ViewBuilder
    private var statusPill: some View {
        if let pratica = pratiche.selectedPratica {
            Menu {
                ForEach(statusCommands(for: pratica), id: \.self) { command in
                    Button(command.title) { actions.run(command, on: pratica) }
                        .accessibilityIdentifier(command.identifier)
                }
            } label: {
                Text(Self.statusTitle(pratica.status))
                    .themedText(.caption, color: .textSecondary)
                    .padding(.horizontal, theme.spacing(.s))
                    .padding(.vertical, 2)
                    .background(theme.color(.backgroundTertiary))
                    .clipShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Self.statusTitle(pratica.status))
            .accessibilityIdentifier("pratiche-status-pill")
        }
    }

    /// The status half of the catalogue, in the catalogue's own order. Asked of
    /// `available(isActive:)` rather than derived here, so the pill offers «Riapri» on
    /// exactly the pratiche the row menu does.
    private func statusCommands(for pratica: PraticaListItem) -> [PraticaCommand] {
        actions.commands(for: pratica).filter { $0 == .close || $0 == .reopen }
    }

    static func statusTitle(_ status: String) -> String {
        switch status {
        case "waiting": "In attesa"
        case "archived", "final": "Chiusa"
        default: "Attiva"
        }
    }

    private var refreshButton: some View {
        Button {
            guard let selection = pratiche.selection else { return }
            Task { await pratiche.refreshNow(selection, in: vault) }
        } label: {
            Image(systemName: "arrow.clockwise")
                // The one moving part of the pane while a sync runs; the thin bar
                // under this strip carries the numbers (screen 1a).
                .symbolEffect(.rotate, isActive: pratiche.syncingPraticaPath != nil)
        }
        .buttonStyle(.borderless)
        .disabled(pratiche.selection == nil)
        .help("Aggiorna ora")
        .accessibilityLabel("Aggiorna ora")
        .accessibilityIdentifier("pratiche-refresh")
    }

    private func filterField(_ text: Binding<String>) -> some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "magnifyingglass")
                .themedText(.caption, color: .textTertiary)
            TextField("Filtra", text: text)
                .textFieldStyle(.plain)
                .themedText(.caption)
                .frame(width: 140)
                .accessibilityIdentifier("pratiche-filter")
        }
        .padding(.horizontal, theme.spacing(.xs))
        .padding(.vertical, 2)
        .background(theme.color(.backgroundTertiary))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .modifier(OptionalFocus(focus: filterFocus))
    }

    /// Addresses rather than display names (R-32): two people share a name far more
    /// often than they share a mailbox.
    private var senderMenu: some View {
        Menu {
            Button("Tutti i mittenti") { pratiche.filter.sender = nil }
            Divider()
            ForEach(pratiche.senderAddresses, id: \.self) { address in
                Button(address) { pratiche.filter.sender = address }
            }
        } label: {
            Image(systemName: pratiche.filter.sender == nil ? "person" : "person.fill")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(pratiche.filter.sender ?? "Mittente")
        .accessibilityLabel("Mittente")
        .accessibilityIdentifier("pratiche-sender-menu")
    }

    private func attachmentsToggle(_ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Image(systemName: "paperclip")
        }
        .toggleStyle(.button)
        .help("Solo con allegati")
        .accessibilityLabel("Solo con allegati")
        .accessibilityIdentifier("pratiche-attachments-only")
    }

    private var inspectorToggle: some View {
        Button {
            navigation.isShowingPraticaInspector.toggle()
        } label: {
            Image(systemName: "sidebar.trailing")
        }
        .buttonStyle(.borderless)
        .help("Nota della pratica")
        .accessibilityLabel("Nota della pratica")
        .accessibilityIdentifier("pratiche-inspector-toggle")
    }
}

/// `.focused` needs a real `FocusState` binding and this bar's is optional, because a
/// preview and the pane's own empty state both build it without one. A modifier rather
/// than an `if` in the body: a `TextField` that changes identity when focus arrives
/// loses what is being typed into it.
private struct OptionalFocus: ViewModifier {
    let focus: FocusState<Bool>.Binding?

    func body(content: Content) -> some View {
        if let focus {
            content.focused(focus)
        } else {
            content
        }
    }
}
