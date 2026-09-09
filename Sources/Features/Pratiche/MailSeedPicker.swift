import SwiftUI

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 8 -
// R-20; DESIGN.md screen 1d, step «Seme» ("three choice buttons, conversation summary,
// counterpart chips").
//
// Two things, one file: the reader the wizard's step 2 and step 3 both need, and the
// «Cerca nella posta…» sheet DESIGN.md leaves to UX-BLUEPRINT.md.
//
// Every byte read here comes from the **published copy** of the Envelope Index
// (`MailStoreCopy.publish`), never from Mail's own file, and never on the main actor -
// the copy is 355 MB on this Mac. The loader is `nonisolated` for exactly that reason
// and returns `Sendable` values, the same crossing `PraticaLiveSync.prepare` makes.

/// What a seed/proposal read answers: the proposals, and the Italian sentence to show
/// when there are none because something went wrong rather than because there is
/// nothing to propose.
struct MailSeedResult: Sendable {
    var proposals: [WizardState.Proposal]
    var problem: String?

    static let empty = MailSeedResult(proposals: [], problem: nil)
}

/// The Mail-store half of «Nuova pratica…», off the main actor.
enum MailSeedLoader {
    /// Every conversation touching one of `counterparts` inside `window`, reduced to
    /// the wizard's own `Proposal` shape.
    ///
    /// Two addresses in one conversation are one proposal, not two - the map is keyed
    /// by `conversation_id`, the same fold `PraticaLiveSync.prepare` does for the tray.
    nonisolated static func proposals(
        counterparts: [String], within window: ClosedRange<Date>,
        mailRoot: URL, stateDirectory: URL
    ) -> MailSeedResult {
        let addresses = counterparts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !addresses.isEmpty else { return .empty }

        switch reader(mailRoot: mailRoot, stateDirectory: stateDirectory) {
        case .failed(let message):
            return MailSeedResult(proposals: [], problem: message)
        case .ready(let reader):
            var conversations: [Int: [MailMessageRow]] = [:]
            for address in addresses {
                for conversation in reader.conversations(counterpart: address, within: window) {
                    conversations[conversation.conversationID] = conversation.messages
                }
            }
            return MailSeedResult(proposals: reduce(conversations), problem: nil)
        }
    }

    /// The conversation a `Message-ID` belongs to, with the address that sent it -
    /// what «Dalla selezione di Mail» turns one `message://` link into.
    ///
    /// A store that cannot resolve an RFC id (ADR §D3: the index's own column is a
    /// hash) answers with a problem sentence, never with a silent empty result: the
    /// person picked a message and is owed an explanation for why it did not take.
    nonisolated static func seed(
        messageID: String, mailRoot: URL, stateDirectory: URL
    ) -> MailSeedResult {
        switch reader(mailRoot: mailRoot, stateDirectory: stateDirectory) {
        case .failed(let message):
            return MailSeedResult(proposals: [], problem: message)
        case .ready(let reader):
            guard case .found(let row) = reader.row(forMessageID: messageID),
                  let conversationID = row.conversationID
            else {
                return MailSeedResult(
                    proposals: [],
                    problem: "L'indice di Mail non riconosce questo messaggio: scegli la conversazione a mano."
                )
            }
            let messages = reader.messages(inConversation: conversationID)
            return MailSeedResult(proposals: reduce([conversationID: messages]), problem: nil)
        }
    }

    /// The `Message-ID` inside a `message://` link - `MailURL.forMessageID`'s inverse,
    /// which is what `MailLink.selectedMessage()`'s `Link.url` needs to be turned back
    /// into something the index can be asked about.
    ///
    /// Here and not in `MailURL`: that file is a `sharedSources` member compiled into
    /// `perg` and `pergamenum-mcp`, and neither connector may reach the Mail store
    /// (`SharedSourcesPurityTests`) - a decoder only this wizard calls belongs on this
    /// side of that line.
    nonisolated static func messageID(fromLinkURL url: String) -> String? {
        let scheme = "message://"
        guard url.hasPrefix(scheme) else { return nil }
        let encoded = String(url.dropFirst(scheme.count))
        let decoded = encoded.removingPercentEncoding ?? encoded
        let trimmed = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `PraticaTrayModel.proposals(from:)`'s own reduction, reused rather than written
    /// a second time: the wizard's step 3 and the tray strip show the same four fields
    /// about the same kind of thing, and two reductions would drift.
    private nonisolated static func reduce(_ conversations: [Int: [MailMessageRow]]) -> [WizardState.Proposal] {
        let entries = conversations
            .map { MembershipRule.TrayEntry(conversationID: $0.key, messages: $0.value) }
            .sorted { $0.conversationID < $1.conversationID }
        return PraticaTrayModel.proposals(from: entries).map { proposal in
            WizardState.Proposal(
                id: String(proposal.conversationID),
                subject: proposal.subject,
                counterpart: proposal.counterpart,
                dateRange: proposal.dateRange,
                messageCount: proposal.messageCount
            )
        }
        // Newest first, which is the order a person recognises a thread in - the
        // dictionary above has none, and the id order is Mail's own arrival order.
        .sorted { $0.dateRange.upperBound > $1.dateRange.upperBound }
    }

    /// Not a `Result`: the failure side is the Italian sentence the sheet shows, and a
    /// `String` is not an `Error` - `PraticaLiveSync.Preparation` answers the same
    /// question the same way, for the same reason.
    private enum ReaderOutcome {
        case ready(MailStoreReader)
        case failed(String)
    }

    private nonisolated static func reader(
        mailRoot: URL, stateDirectory: URL
    ) -> ReaderOutcome {
        let generation: URL
        switch MailStoreCopy.publish(from: mailRoot, into: stateDirectory) {
        case .published(let url), .unchanged(let url):
            generation = url
        case .mailIsWriting:
            return .failed("Mail sta scrivendo nel suo archivio: riprova fra qualche secondo.")
        case .storeMissing:
            return .failed("Nessun archivio di Mail trovato in \(mailRoot.path(percentEncoded: false)).")
        }
        let indexURL = generation.appending(path: "Envelope Index", directoryHint: .notDirectory)
        guard let reader = try? MailStoreReader(storeURL: indexURL) else {
            return .failed("La copia dell'indice di Mail non si è aperta.")
        }
        return .ready(reader)
    }
}

/// «Cerca nella posta…» (screen 1d's second seed choice): an address, the conversations
/// it appears in, and one of them chosen as the pratica's seed.
///
/// Not drawn by the design ("Not decided here"), so it follows UX-BLUEPRINT's own
/// shape: a filter field over a flat list, never a tree - the same reasoning ADR-0034
/// §D7 gives for the folder picker.
struct MailSeedPicker: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    /// Days back the search looks - the same window the tray proposes inside, so a
    /// person is never offered a seed the tray would then refuse to follow up.
    let windowDays: Int
    let onCancel: () -> Void
    /// The chosen address and the conversation under it.
    let onChoose: (_ address: String, _ proposal: WizardState.Proposal) -> Void

    @State private var address = ""
    @State private var proposals: [WizardState.Proposal] = []
    @State private var problem: String?
    @State private var isSearching = false
    @State private var chosen: String?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Cerca nella posta").themedText(.title)
            searchRow
            if let problem {
                Text(problem)
                    .themedText(.caption, color: .taskOverdue)
                    .accessibilityIdentifier("pratiche-seed-problem")
            }
            list
            footer
        }
        .padding(theme.spacing(.l))
        .frame(width: 520, height: 420)
        .background(theme.color(.backgroundPrimary))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pratiche-seed-picker")
    }

    private var searchRow: some View {
        HStack(spacing: theme.spacing(.s)) {
            TextField("Indirizzo della controparte", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit { search() }
                .accessibilityIdentifier("pratiche-seed-search")
            Button("Cerca", action: search)
                .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                .accessibilityIdentifier("pratiche-seed-run")
        }
    }

    @ViewBuilder
    private var list: some View {
        if isSearching {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if proposals.isEmpty {
            Text("Nessuna conversazione con questo indirizzo negli ultimi \(windowDays) giorni.")
                .themedText(.caption, color: .textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            List(selection: $chosen) {
                ForEach(proposals) { proposal in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(proposal.subject.isEmpty ? "(senza oggetto)" : proposal.subject)
                            .themedText(.body)
                            .lineLimit(1)
                        Text(Self.subtitle(proposal)).themedText(.caption, color: .textTertiary)
                    }
                    .accessibilityIdentifier("pratiche-seed-row-\(proposal.id)")
                    .tag(proposal.id)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Annulla", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("pratiche-seed-cancel")
            Button("Usa questa conversazione") {
                guard let chosen, let proposal = proposals.first(where: { $0.id == chosen }) else { return }
                onChoose(address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), proposal)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(chosen == nil)
            .accessibilityIdentifier("pratiche-seed-use")
        }
    }

    static func subtitle(_ proposal: WizardState.Proposal) -> String {
        [
            proposal.counterpart,
            PraticaTrayStrip.range(proposal.dateRange),
            proposal.messageCount == 1 ? "1 messaggio" : "\(proposal.messageCount) messaggi",
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private func search() {
        guard let session = vault.session else { return }
        let needle = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return }
        let stateDirectory = PraticheController.stateDirectory(for: session)
        let mailRoot = MailStoreLocation.resolve()
        let now = Date()
        let window = now.addingTimeInterval(-Double(windowDays) * 86_400)...now
        isSearching = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                MailSeedLoader.proposals(
                    counterparts: [needle], within: window,
                    mailRoot: mailRoot, stateDirectory: stateDirectory
                )
            }.value
            proposals = result.proposals
            problem = result.problem
            chosen = result.proposals.first?.id
            isSearching = false
        }
    }
}
