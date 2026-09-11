import SwiftUI

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 8 -
// R-21; DESIGN.md screen 1e ("Header with the selected Mail message, «Filtra
// pratiche», pratiche grouped by client with «Ultima attività … · N messaggi», final
// row «Nuova pratica…», footer Annulla/Aggiungi").
//
// Reached from the Inserisci menu, from Cmd+Shift+P and from the pane's own empty
// state - three surfaces, one declaration (`ShortcutCommand.addToPraticaFromMail` +
// `Navigation.isShowingAddToPratica`), which is ADR-0023 §D1 applied to a command that
// opens a sheet rather than one that writes a file.
//
// «Aggiungi» writes the message's own `Message-ID` into the chosen pratica's
// `pergamenum-dossier-included` and then asks for that pratica's ordinary sync: the
// import is `PraticaSyncEngine`'s, never a second one written here (ADR §D5 - a
// message file has exactly one writer).
struct AddToPraticaSheet: View {
    @Environment(\.theme) private var theme
    @Environment(PraticheController.self) private var pratiche
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation
    @Environment(\.undoManager) private var undoManager

    let onClose: () -> Void
    /// «Nuova pratica…», the last row (screen 1e): the same command the File menu and
    /// the list column's «+» reach, so this sheet does not grow a second creation path.
    let onNewPratica: () -> Void

    @State private var filter = ""
    @State private var chosen: String?
    @State private var link: MailLink.Link?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            header
            TextField("Filtra pratiche", text: $filter)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("pratiche-add-filter")
            list
            footer
        }
        .padding(theme.spacing(.l))
        .frame(width: 520, height: 460)
        .background(theme.color(.backgroundPrimary))
        .accessibilityElement(children: .contain)
        // UX-BLUEPRINT's checklist calls this sheet `pratiche-picker`, and a UI test
        // finds a control by identifier and never by the words on it: the name is the
        // contract, so it is the checklist's spelling rather than a second one.
        .accessibilityIdentifier("pratiche-picker")
        .onAppear {
            readSelection()
            // R-21's list is `pratiche.pratiche` (`readSelection` above), which stays
            // empty until something has called `load(from:)` - the pane and the
            // Settings tab both do on `.task`/`onAppear`, but this sheet is reachable
            // from Cmd+Shift+P and the Inserisci menu before either has ever run.
            pratiche.load(from: vault)
        }
    }

    // MARK: - The message

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Aggiungi a pratica da Mail").themedText(.title)
            if let link {
                Text(link.subject)
                    .themedText(.body, color: .textSecondary)
                    .lineLimit(2)
                    .accessibilityIdentifier("pratiche-add-message")
            } else {
                Text(problem ?? "Nessun messaggio selezionato in Mail.")
                    .themedText(.caption, color: problem == nil ? .textTertiary : .taskOverdue)
                    .accessibilityIdentifier("pratiche-add-message")
            }
        }
    }

    /// R-21/§D21: a refusal of the Automation dialog is its own sentence, never read as
    /// "nothing selected" - the two are different problems with different answers.
    private func readSelection() {
        switch MailLink.selectedMessage() {
        case .success(let value):
            link = value
            problem = nil
        case .failure(let failure):
            link = nil
            problem = "Mail non ha risposto: \(failure.description)"
        }
    }

    // MARK: - The pratiche

    private var list: some View {
        List(selection: $chosen) {
            ForEach(groups, id: \.client) { group in
                Section(group.client.isEmpty ? "Senza cliente" : group.client) {
                    ForEach(group.pratiche) { pratica in
                        row(pratica)
                    }
                }
            }
            Section {
                Button("Nuova pratica…") {
                    onClose()
                    onNewPratica()
                }
                .buttonStyle(.plain)
                .themedText(.body, color: .accentPrimary)
                .accessibilityIdentifier("pratiche-add-new")
            }
        }
        .scrollContentBackground(.hidden)
    }

    /// `.badge` before `.tag` - applied the other way round the badge drops the tag and
    /// no row can ever equal the selection (`RootView.swift`'s own note, ADR-0024).
    private func row(_ pratica: PraticaListItem) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(pratica.title).themedText(.body).lineLimit(1)
            Text(subtitle(pratica)).themedText(.caption, color: .textTertiary).lineLimit(1)
        }
        // `pratiche-picker-row-<slug>` in the checklist; the slug is the pratica's own
        // folder path, the same value `pratiche-row-<pratica.id>` carries in the
        // sidebar, so one pratica answers to one spelling on both surfaces.
        .accessibilityIdentifier("pratiche-picker-row-\(pratica.id)")
        .badge(pratica.messagesSinceLastOpen)
        .tag(pratica.id)
    }

    /// «Ultima attività 10 giugno · 24 messaggi» - the count is what the ledger says
    /// this pratica has imported, which is the only message count this side of a sync
    /// knows without walking the folder.
    private func subtitle(_ pratica: PraticaListItem) -> String {
        let imported = pratiche.ledger.byPraticaPath[pratica.id]?.importedMessageIDs.count ?? 0
        return [
            "Ultima attività \(PraticaRowFormat.day(pratica.lastActivity))",
            imported == 1 ? "1 messaggio" : "\(imported) messaggi",
        ].joined(separator: " · ")
    }

    /// Recent first (R-21, `AddToPraticaOrdering.recentFirst`), then grouped by client
    /// in the order that flat list first meets each one - so the grouping never
    /// reorders what the ordering decided.
    private var groups: [PraticaClientGroup] {
        var order: [String] = []
        var byClient: [String: [PraticaListItem]] = [:]
        for pratica in AddToPraticaOrdering.recentFirst(filtered) {
            if byClient[pratica.client] == nil { order.append(pratica.client) }
            byClient[pratica.client, default: []].append(pratica)
        }
        return order.map { PraticaClientGroup(client: $0, pratiche: byClient[$0] ?? []) }
    }

    private var filtered: [PraticaListItem] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return pratiche.pratiche }
        return pratiche.pratiche.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.client.localizedCaseInsensitiveContains(needle)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Annulla", action: onClose)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("pratiche-add-cancel")
            Button("Aggiungi", action: add)
                .keyboardShortcut(.defaultAction)
                .disabled(chosen == nil || link == nil)
                .accessibilityIdentifier("pratiche-add-confirm")
        }
    }

    /// R-21: the id joins `pergamenum-dossier-included`, which is what makes the next
    /// sync import a message that belongs to no followed conversation
    /// (`MembershipRule.candidates`' own `included` arm), and that sync is asked for
    /// straight away rather than waited for.
    private func add() {
        guard let praticaPath = chosen, let link,
              let messageID = MailSeedLoader.messageID(fromLinkURL: link.url)
        else { return }
        let actions = PraticaCommandActions(
            pratiche: pratiche, vault: vault, navigation: navigation, undoManager: undoManager
        )
        actions.updateDossier(at: praticaPath) { dossier in
            if !dossier.included.contains(messageID) { dossier.included.append(messageID) }
        }
        onClose()
        navigation.pane = .pratiche
        pratiche.select(praticaPath, in: vault)
        Task { await pratiche.refreshNow(praticaPath, in: vault) }
    }
}
