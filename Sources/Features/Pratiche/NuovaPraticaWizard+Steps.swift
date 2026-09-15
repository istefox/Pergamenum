import SwiftUI

// ADR-0045 §D3 (PG-143 structure refactor): the four step views, the footer and the
// step-advance logic, split out of `NuovaPraticaWizard.swift` for its own struct-body
// length - moved verbatim, `NoteListPane.swift:23-30`'s convention for every property
// this file reaches into.

extension NuovaPraticaWizard {
    // MARK: - Step 1

    /// Not `private`: `NuovaPraticaWizard.swift`'s `body`, in the main file, switches
    /// on `state.step` and reads this case directly.
    @ViewBuilder
    var nameAndClient: some View {
        TextField("Titolo", text: $state.title)
            .accessibilityIdentifier("pratiche-wizard-title")
        HStack(spacing: theme.spacing(.s)) {
            TextField("Cliente", text: $state.clientFolder)
                .accessibilityIdentifier("pratiche-wizard-client")
            // A flat menu of the clients that already exist, never a folder tree - the
            // same reasoning ADR-0034 §D7 gives for the note folder picker.
            Menu {
                ForEach(knownClients, id: \.self) { client in
                    Button(client) { state.clientFolder = client }
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .fixedSize()
            .disabled(knownClients.isEmpty)
            .accessibilityLabel("Clienti esistenti")
            .accessibilityIdentifier("pratiche-wizard-client-menu")
        }
        HStack(spacing: theme.spacing(.s)) {
            TextField("Cartella radice", text: $state.rootFolder)
                .accessibilityIdentifier("pratiche-wizard-root")
            SettingsLink { Text("Impostazioni") }
                .accessibilityIdentifier("pratiche-wizard-settings")
        }
        Text(state.relativePath.isEmpty ? " " : state.relativePath)
            .themedText(.caption, color: .textTertiary)
            .accessibilityIdentifier("pratiche-wizard-path")
    }

    private var knownClients: [String] {
        Array(Set(pratiche.pratiche.map(\.client))).filter { !$0.isEmpty }.sorted()
    }

    // MARK: - Step 2

    /// Not `private`: `NuovaPraticaWizard.swift`'s `body`, in the main file, switches
    /// on `state.step` and reads this case directly.
    @ViewBuilder
    var seed: some View {
        Section("Da dove parte la pratica") {
            Button("Dalla selezione di Mail") { seedFromMailSelection() }
                .accessibilityIdentifier("pratiche-wizard-seed-mail")
            Button("Cerca nella posta…") { isShowingSeedPicker = true }
                .accessibilityIdentifier("pratiche-wizard-seed-search")
            Button("Più tardi") {
                state.seed = .later
                state.proposals = []
                state.selectedProposalIDs = []
            }
            .accessibilityIdentifier("pratiche-wizard-seed-later")
        }
        Section("Conversazione") {
            if let summary = seedSummary {
                Text(summary)
                    .themedText(.caption, color: .textSecondary)
                    .accessibilityIdentifier("pratiche-wizard-seed-summary")
            } else {
                Text("Nessun seme scelto: la pratica parte vuota e si riempie dalle parole chiave.")
                    .themedText(.caption, color: .textTertiary)
                    .accessibilityIdentifier("pratiche-wizard-seed-summary")
            }
        }
        Section("Controparti") {
            ForEach(candidateAddresses, id: \.self) { address in
                Toggle(address, isOn: chip(address))
                    .accessibilityIdentifier("pratiche-wizard-counterpart-\(address)")
            }
            HStack(spacing: theme.spacing(.s)) {
                TextField("Aggiungi un indirizzo", text: $typedAddress)
                    .onSubmit { addTypedAddress() }
                    .accessibilityIdentifier("pratiche-wizard-counterpart-field")
                Button("Aggiungi", action: addTypedAddress)
                    .disabled(typedAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("pratiche-wizard-counterpart-add")
            }
        }
    }

    private var seedSummary: String? {
        guard let first = state.proposals.first else { return nil }
        return "\(first.subject.isEmpty ? "(senza oggetto)" : first.subject) · \(MailSeedPicker.subtitle(first))"
    }

    private func chip(_ address: String) -> Binding<Bool> {
        Binding(
            get: { state.counterparts.contains(address) },
            set: { isOn in
                if isOn {
                    if !state.counterparts.contains(address) { state.counterparts.append(address) }
                } else {
                    state.counterparts.removeAll { $0 == address }
                }
            }
        )
    }

    private func addTypedAddress() {
        let address = typedAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !address.isEmpty else { return }
        if !candidateAddresses.contains(address) { candidateAddresses.append(address) }
        if !state.counterparts.contains(address) { state.counterparts.append(address) }
        typedAddress = ""
    }

    // MARK: - Step 3

    /// Not `private`: `NuovaPraticaWizard.swift`'s `body`, in the main file, switches
    /// on `state.step` and reads this case directly.
    @ViewBuilder
    var proposals: some View {
        Section("Conversazioni con queste controparti") {
            if isLoadingProposals {
                ProgressView().accessibilityIdentifier("pratiche-wizard-proposals-loading")
            } else if state.proposals.isEmpty {
                Text("Nessuna conversazione trovata: la pratica parte vuota.")
                    .themedText(.caption, color: .textTertiary)
                    .accessibilityIdentifier("pratiche-wizard-proposals-empty")
            } else {
                ForEach(state.proposals) { proposal in
                    Toggle(isOn: tick(proposal.id)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(proposal.subject.isEmpty ? "(senza oggetto)" : proposal.subject)
                                .themedText(.body)
                                .lineLimit(1)
                            Text(MailSeedPicker.subtitle(proposal))
                                .themedText(.caption, color: .textTertiary)
                        }
                    }
                    .accessibilityIdentifier("pratiche-wizard-proposal-\(proposal.id)")
                }
            }
        }
        Section("Parole chiave") {
            TextField("urgente, contratto", text: $state.keywords, axis: .vertical)
                .lineLimit(2...4)
                .accessibilityIdentifier("pratiche-wizard-keywords")
        }
    }

    private func tick(_ id: String) -> Binding<Bool> {
        Binding(
            get: { state.selectedProposalIDs.contains(id) },
            set: { isOn in
                if isOn { state.selectedProposalIDs.insert(id) } else { state.selectedProposalIDs.remove(id) }
                state.refreshNewCounterpartCandidates(ownAddresses: Set(vault.settings.pratiche.ownAddresses))
            }
        )
    }

    // MARK: - Step "Nuove controparti"

    /// Not `private`: `NuovaPraticaWizard.swift`'s `body`, in the main file, switches
    /// on `state.step` and reads this case directly.
    @ViewBuilder
    var newCounterparts: some View {
        Section("Indirizzi nuovi trovati nella conversazione") {
            ForEach(cappedCandidates.filter(\.wroteAtLeastOnce)) { candidate in
                newCounterpartRow(candidate, detail: Self.wroteDetail(candidate.messageCount))
            }
            ForEach(cappedCandidates.filter { !$0.wroteAtLeastOnce }) { candidate in
                newCounterpartRow(candidate, detail: "solo in copia, mai scritto direttamente")
            }
            if newCounterpartOverflowCount > 0 {
                Text("e altri \(newCounterpartOverflowCount) indirizzi ignorati")
                    .themedText(.caption, color: .textTertiary)
                    .accessibilityIdentifier("pratiche-wizard-new-counterpart-overflow")
            }
        }
    }

    private func newCounterpartRow(
        _ candidate: NewCounterpartDetector.NewCounterpartCandidate, detail: String
    ) -> some View {
        Toggle(isOn: newCounterpartTick(candidate.address)) {
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.address).themedText(.body)
                Text(detail).themedText(.caption, color: .textTertiary)
            }
        }
        .accessibilityIdentifier("pratiche-wizard-new-counterpart-\(candidate.address)")
    }

    private static func wroteDetail(_ count: Int) -> String {
        count == 1 ? "ha scritto 1 messaggio" : "ha scritto \(count) messaggi"
    }

    /// R-05: at most 10 shown individually, ranked/grouped order preserved.
    private var cappedCandidates: [NewCounterpartDetector.NewCounterpartCandidate] {
        Array(state.newCounterpartCandidates.prefix(10))
    }

    private var newCounterpartOverflowCount: Int {
        max(0, state.newCounterpartCandidates.count - 10)
    }

    private func newCounterpartTick(_ address: String) -> Binding<Bool> {
        Binding(
            get: { state.selectedNewCounterpartAddresses.contains(address) },
            set: { isOn in
                if isOn { state.selectedNewCounterpartAddresses.insert(address) }
                else { state.selectedNewCounterpartAddresses.remove(address) }
            }
        )
    }

    // MARK: - Footer

    /// Not `private`: `NuovaPraticaWizard.swift`'s `body`, in the main file, reads
    /// this directly.
    var footer: some View {
        HStack(spacing: theme.spacing(.s)) {
            Button("Annulla", action: onClose)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("pratiche-wizard-cancel")
            Spacer()
            if state.step != .nameAndClient {
                Button("Indietro") { step(by: -1) }
                    .accessibilityIdentifier("pratiche-wizard-back")
            }
            if state.isLastStep {
                Button("Crea", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!state.canCreate)
                    .accessibilityIdentifier("pratiche-wizard-create")
            } else {
                Button("Continua") { step(by: 1) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!state.canAdvance)
                    .accessibilityIdentifier("pratiche-wizard-continue")
            }
        }
    }

    private func step(by delta: Int) {
        guard delta < 0 || state.canAdvance else { return }
        guard let next = WizardState.Step(rawValue: state.step.rawValue + delta) else { return }
        state.step = next
        if next == .proposals { loadProposals() }
    }
}
