import SwiftUI

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 8 -
// R-20; DESIGN.md screen 1d and its Binding decision ("Wizard uses an eyebrow «PASSO n
// DI 3», a Form layout and footers Annulla/Continua, Indietro/Continua, Indietro/Crea").
//
// The sheet holds one `WizardState` and nothing else: every gate it draws
// (`canContinueFromNameAndClient`, `canAdvance`, `canCreate`) and the `Dossier` «Crea»
// writes (`makeDossier()`) are that value's own, so the sheet cannot disagree with
// what the tests pin.
//
// «Crea» writes `pratica.md` once, through `VaultSession.write` (ADR §D5), and then
// asks for the first sync - which runs in the background with the pane's own progress
// bar, because it is the ordinary per-pratica sync and not a second import path.
struct NuovaPraticaWizard: View {
    @Environment(\.theme) private var theme
    @Environment(PraticheController.self) private var pratiche
    @Environment(VaultController.self) private var vault

    let onClose: () -> Void

    @State private var state = WizardState()
    @State private var problem: String?
    @State private var isLoadingProposals = false
    @State private var isShowingSeedPicker = false
    /// The addresses step 2 offers as chips, and which of them are ticked - kept apart
    /// from `state.counterparts` (the ticked ones) so unticking a chip does not lose it
    /// from the list.
    @State private var candidateAddresses: [String] = []
    @State private var typedAddress = ""

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("PASSO \(state.step.rawValue + 1) DI \(state.newCounterpartCandidates.isEmpty ? 3 : 4)")
                .themedText(.caption, color: .textTertiary)
                .accessibilityIdentifier("pratiche-wizard-step")
            Text(Self.title(of: state.step)).themedText(.title)
            Form {
                switch state.step {
                case .nameAndClient: nameAndClient
                case .seed: seed
                case .proposals: proposals
                case .newCounterparts: newCounterparts
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            if let problem {
                Text(problem)
                    .themedText(.caption, color: .taskOverdue)
                    .accessibilityIdentifier("pratiche-wizard-problem")
            }
            footer
        }
        .padding(theme.spacing(.l))
        .frame(width: 560, height: 520)
        .background(theme.color(.backgroundPrimary))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-wizard")
        .onAppear { state.rootFolder = vault.settings.pratiche.rootFolder }
        .sheet(isPresented: $isShowingSeedPicker) {
            MailSeedPicker(
                windowDays: vault.settings.pratiche.proposalWindowDays,
                onCancel: { isShowingSeedPicker = false },
                onChoose: { address, proposal, messages in
                    isShowingSeedPicker = false
                    if let id = Int(proposal.id) { state.conversationMessages[id] = messages }
                    adopt(seed: .search, address: address, proposal: proposal)
                }
            )
        }
    }

    static func title(of step: WizardState.Step) -> String {
        switch step {
        case .nameAndClient: "Nome e cliente"
        case .seed: "Seme"
        case .proposals: "Proposte"
        case .newCounterparts: "Nuove controparti"
        }
    }

    // MARK: - Step 1

    @ViewBuilder
    private var nameAndClient: some View {
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

    @ViewBuilder
    private var seed: some View {
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

    @ViewBuilder
    private var proposals: some View {
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

    @ViewBuilder
    private var newCounterparts: some View {
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

    private var footer: some View {
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

    // MARK: - The Mail seed

    /// R-20/§D21: a refusal of the Automation dialog is reported in the person's own
    /// words, never read as "nothing selected" - `MailLink.selectedMessage()`'s own
    /// contract, and the reason it answers a `Result` rather than an optional.
    private func seedFromMailSelection() {
        switch MailLink.selectedMessage() {
        case .failure(let failure):
            problem = "Mail non ha risposto: \(failure.description)"
        case .success(let link):
            problem = nil
            state.seed = .mailSelection(link)
            resolveSeed(link)
        }
    }

    /// The `message://` link carries a `Message-ID`; the index turns it into the
    /// conversation and the address that sent it, which is what the pratica actually
    /// follows.
    private func resolveSeed(_ link: MailLink.Link) {
        guard let session = vault.session,
              let messageID = MailSeedLoader.messageID(fromLinkURL: link.url)
        else {
            problem = "Il messaggio selezionato non ha un id utilizzabile."
            return
        }
        let stateDirectory = PraticheController.stateDirectory(for: session)
        let mailRoot = MailStoreLocation.resolve()
        let ownAddresses = Set(vault.settings.pratiche.ownAddresses)
        isLoadingProposals = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                MailSeedLoader.seed(
                    messageID: messageID, mailRoot: mailRoot, stateDirectory: stateDirectory,
                    ownAddresses: ownAddresses
                )
            }.value
            isLoadingProposals = false
            problem = result.problem
            state.conversationMessages.merge(result.messagesByConversationID) { _, new in new }
            guard let proposal = result.proposals.first else { return }
            adopt(seed: state.seed, address: proposal.counterpart, proposal: proposal)
        }
    }

    /// One place both seed paths land: the conversation becomes the first proposal,
    /// ticked, and its address becomes the first counterpart chip - which is what makes
    /// step 3's own fetch find the rest of the thread's neighbours.
    private func adopt(seed: WizardState.Seed, address: String, proposal: WizardState.Proposal) {
        state.seed = seed
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !address.isEmpty {
            if !candidateAddresses.contains(address) { candidateAddresses.append(address) }
            if !state.counterparts.contains(address) { state.counterparts.append(address) }
        }
        if !state.proposals.contains(where: { $0.id == proposal.id }) {
            state.proposals.insert(proposal, at: 0)
        }
        state.selectedProposalIDs.insert(proposal.id)
    }

    /// Step 3's own read: every conversation touching the ticked counterparts inside
    /// the proposal window. Anything already ticked stays ticked - a person moving back
    /// and forth between steps must not lose their choices.
    private func loadProposals() {
        Task { await performLoadProposals(preselectingNew: false) }
    }

    /// Step 3's own read: every conversation touching the ticked counterparts,
    /// inside the proposal window. Anything already ticked stays ticked.
    ///
    /// `preselectingNew`: false for the ordinary step-3 fetch (today's behavior -
    /// a person ticks conversations by hand); true only for the post-accept
    /// re-fetch in `createAfterAcceptingNewCounterparts()`, where a newly found
    /// conversation must join the pratica automatically (R-08), the same
    /// treatment `adopt()` already gives the seed's own conversation.
    private func performLoadProposals(preselectingNew: Bool) async {
        guard let session = vault.session, !state.counterparts.isEmpty else { return }
        let counterparts = state.counterparts
        let stateDirectory = PraticheController.stateDirectory(for: session)
        let mailRoot = MailStoreLocation.resolve()
        let now = Date()
        let window = now.addingTimeInterval(
            -Double(vault.settings.pratiche.proposalWindowDays) * 86_400
        )...now
        let ownAddresses = Set(vault.settings.pratiche.ownAddresses)
        isLoadingProposals = true
        let result = await Task.detached(priority: .userInitiated) {
            MailSeedLoader.proposals(
                counterparts: counterparts, within: window,
                mailRoot: mailRoot, stateDirectory: stateDirectory, ownAddresses: ownAddresses
            )
        }.value
        isLoadingProposals = false
        problem = result.problem
        state.conversationMessages.merge(result.messagesByConversationID) { _, new in new }
        let known = Set(state.proposals.map(\.id))
        let newOnes = result.proposals.filter { !known.contains($0.id) }
        state.proposals += newOnes
        if preselectingNew { state.selectedProposalIDs.formUnion(newOnes.map(\.id)) }
        state.refreshNewCounterpartCandidates(ownAddresses: ownAddresses)
    }

    // MARK: - «Crea»

    /// R-20: one conformant `pratica.md` (ADR §D11's tag set plus the dossier keys),
    /// then the ordinary per-pratica sync - the pane's own progress bar reports it, and
    /// rows arrive newest-last because the timeline is ascending by design.
    /// R-08: a checked new-counterpart candidate must become a real counterpart,
    /// pull in whatever else in Mail already involves it, and only then let the
    /// pratica be created - so a checked box never leaves anyone off the pratica's
    /// counterparts. An empty selection (R-09) is exactly today's «Crea».
    private func create() {
        guard !state.selectedNewCounterpartAddresses.isEmpty else {
            performCreate()
            return
        }
        for address in state.selectedNewCounterpartAddresses where !state.counterparts.contains(address) {
            state.counterparts.append(address)
        }
        Task {
            await performLoadProposals(preselectingNew: true)
            performCreate()
        }
    }

    private func performCreate() {
        guard let session = vault.session else { return }
        let folder = state.relativePath
        let path = PraticaCommandActions.praticaNotePath(of: folder)
        guard !session.exists(path) else {
            problem = "«\(folder)» esiste già."
            return
        }
        var frontmatter = Frontmatter.empty
        frontmatter.date = CalendarDate(Date())
        frontmatter.tags = TagRules.ordered(tags(for: folder))
        frontmatter.foreignKeys = Dossier.render(state.makeDossier())
        let document = NoteDocument(
            frontmatter: frontmatter, body: "\n", hasFrontmatterBlock: true
        )
        do {
            try session.write(document.serialized(), to: path)
        } catch {
            problem = "«\(path)» non è stato creato: \(error.localizedDescription)"
            return
        }
        onClose()
        pratiche.load(from: vault)
        pratiche.select(folder, in: vault)
        Task { await pratiche.refreshNow(folder, in: vault) }
    }

    /// ADR §D11: `type-note`, `topic-pratica`, `client-<slug>`, `status-active`,
    /// `source-email` - the set the real linter accepts, `status-final` never written.
    private func tags(for folder: String) -> [Tag] {
        var tags = [Tag("type-note"), Tag("topic-pratica"), Tag("status-active"), Tag("source-email")]
            .compactMap { $0 }
        if let client = PraticaNaming.clientTag(forPraticaAt: folder, root: state.rootFolder) {
            tags.append(client)
        }
        return tags
    }
}
