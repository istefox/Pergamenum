import Foundation

// ADR-0045 §D3 (PG-143 structure refactor): the Mail-seed resolution and the «Crea»
// write path, split out of `NuovaPraticaWizard.swift` for its own struct-body length -
// moved verbatim, `NoteListPane.swift:23-30`'s convention for every member this file
// widens.

extension NuovaPraticaWizard {
    // MARK: - Title

    static func title(of step: WizardState.Step) -> String {
        switch step {
        case .nameAndClient: "Nome e cliente"
        case .seed: "Seme"
        case .proposals: "Proposte"
        case .newCounterparts: "Nuove controparti"
        }
    }

    // MARK: - The Mail seed

    /// R-20/§D21: a refusal of the Automation dialog is reported in the person's own
    /// words, never read as "nothing selected" - `MailLink.selectedMessage()`'s own
    /// contract, and the reason it answers a `Result` rather than an optional.
    ///
    /// Not `private`: `NuovaPraticaWizard+Steps.swift`'s `seed` is an extension of this
    /// same struct in a separate file, and calls it.
    func seedFromMailSelection() {
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
    ///
    /// Not `private`: `NuovaPraticaWizard.swift`'s `body`, in the main file, calls it
    /// directly from the seed-picker sheet's `onChoose`.
    func adopt(seed: WizardState.Seed, address: String, proposal: WizardState.Proposal) {
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
    ///
    /// Not `private`: `NuovaPraticaWizard+Steps.swift`'s `step(by:)` is an extension of
    /// this same struct in a separate file, and calls it.
    func loadProposals() {
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
    ///
    /// Not `private`: `NuovaPraticaWizard+Steps.swift`'s `footer` is an extension of
    /// this same struct in a separate file, and calls it.
    func create() {
        guard !state.selectedNewCounterpartAddresses.isEmpty else {
            Task { await performCreate() }
            return
        }
        for address in state.selectedNewCounterpartAddresses where !state.counterparts.contains(address) {
            state.counterparts.append(address)
        }
        Task {
            await performLoadProposals(preselectingNew: true)
            await performCreate()
        }
    }

    /// `async` since ADR-0041 Task 8 (`VaultSession.write`'s actor-hop overload); `create()`
    /// itself stays synchronous and wraps both call sites in `Task { }`.
    private func performCreate() async {
        guard let session = vault.session else { return }
        let folder = state.relativePath
        let path = PraticaNaming.praticaNotePath(of: folder)
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
            try await session.write(document.serialized(), to: path)
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
