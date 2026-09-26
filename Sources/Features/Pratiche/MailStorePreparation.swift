import Foundation

// ADR-0045 §D6 (PG-143 structure refactor): the Envelope-Index publish-and-open block
// had four copies - `PraticaLiveSync.prepare`, `PraticaLiveSync.prepareRegeneration`,
// `MailSeedLoader.proposals`/`.seed` (through `MailSeedPicker`'s own private `reader`)
// and `PraticheSettingsTab.sentSenderAddresses` - three of them carrying the same two
// Italian sentences verbatim. `reader(mailRoot:stateDirectory:)` below is the one home
// for it; `prepare(...)` is `PraticaLiveSync`'s former `nonisolated static` body,
// moved here verbatim except for routing its own publish-and-open step through it.
//
// `Sources/Features/`, not `Sources/Core/`: this is app-side orchestration over
// `MailStoreCopy` and `MailStoreReader`, and ADR-0036 §D19 is explicit that the
// connectors are structurally unable to open the Mail store.
enum MailStorePreparation {
    /// Not a `Result`: the failure side is the Italian sentence the caller shows, and a
    /// `String` is not an `Error` - wrapping it in one would buy nothing, since nothing
    /// here is thrown or caught.
    enum ReaderOutcome {
        case ready(reader: MailStoreReader, indexURL: URL)
        case failed(String)
    }

    /// Publishes a fresh (or unchanged) copy of the Envelope Index and opens a reader
    /// onto it. Every caller that used to carry its own copy of this block - `prepare`
    /// below, `PraticaLiveSync.prepareRegeneration`, `MailSeedLoader.proposals`/`.seed`
    /// and `PraticheSettingsTab.sentSenderAddresses` - routes through this instead.
    nonisolated static func reader(mailRoot: URL, stateDirectory: URL) -> ReaderOutcome {
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
        return .ready(reader: reader, indexURL: indexURL)
    }

    struct Prepared: Sendable {
        var indexURL: URL
        /// R-30/§D22.3: `snapshot.unfollowed` already carries every conversation
        /// touching a counterpart inside the proposal window, followed or not - one
        /// snapshot serves both `MembershipRule.candidates` (rule 3 reads it through
        /// `everyMessage(in:)`) and `MembershipRule.trayCandidates` (merges it with
        /// `conversations`), so there is no second field to keep in step with this one.
        var snapshot: MembershipStoreSnapshot
        /// §D23.3/§D23.4: `old → new` for every followed conversation `prepare` found
        /// renumbered this run - defaulted empty so every existing construction site
        /// keeps compiling.
        var conversationRemap: [Int: Int] = [:]
        /// §D23.5: followed conversations whose every known member has vanished from
        /// the store - reported through `controller.report(_:)`, never removed from
        /// the dossier (R-14).
        var unrecoverableConversations: [Int] = []
        /// §D24.4: `false` when the store's schema has no queryable `recipients`
        /// table - reported through `controller.report(_:)` once per sync, since a
        /// store in that shape silently reduces the tray and the keyword arm to
        /// sender-only matching.
        var recipientsUnsupported: Bool = false
    }

    /// What `prepare(...)` answers. Not a `Result`: the failure side is the Italian
    /// sentence the banner shows, and a `String` is not an `Error` - wrapping it in one
    /// would buy nothing, since nothing here is thrown or caught.
    enum Preparation: Sendable {
        case ready(Prepared)
        case failed(String)
    }

    /// The whole Mail-touching half, off the main actor. A named failure rather than an
    /// optional: «Mail sta scrivendo» and «nessun archivio di Mail» are different
    /// sentences and only one of them is worth a second attempt (ADR §D2).
    nonisolated static func prepare(
        mailRoot: URL, stateDirectory: URL, dossier: Dossier, ledgerEntries: [PraticaLedger.Entry],
        proposalWindow: ClosedRange<Date>
    ) -> Preparation {
        let indexURL: URL
        let reader: MailStoreReader
        switch Self.reader(mailRoot: mailRoot, stateDirectory: stateDirectory) {
        case .failed(let message):
            return .failed(message)
        case .ready(let openedReader, let openedIndexURL):
            reader = openedReader
            indexURL = openedIndexURL
        }

        // `messagesByID` first (§D23.3): recovery below resolves against it, so it must
        // exist before the conversation loop that may need it.
        let messagesByID = resolveMessagesByID(reader: reader, dossier: dossier, ledgerEntries: ledgerEntries)

        // §D23.3/R-14: an empty result for a followed conversation is only evidence of
        // renumbering when this pratica has actually imported from it - nothing
        // imported means nothing to re-derive, and a conversation whose every message
        // a person deleted is not a bug to report.
        let followed = resolveFollowedConversations(
            reader: reader, dossier: dossier, ledgerEntries: ledgerEntries, messagesByID: messagesByID
        )

        // R-30: the counterpart query the tray is made of
        // (`MailStoreReader.conversations(counterpart:within:)`, written for exactly
        // this), asked once per counterpart and folded into one map - two counterparts
        // in one conversation are one proposal, not two.
        let unfollowed = unfollowedConversations(reader: reader, dossier: dossier, proposalWindow: proposalWindow)

        return .ready(Prepared(
            indexURL: indexURL,
            snapshot: MembershipStoreSnapshot(
                conversations: followed.conversations, messagesByID: messagesByID, unfollowed: unfollowed
            ),
            conversationRemap: followed.remap,
            unrecoverableConversations: followed.unrecoverable,
            recipientsUnsupported: !reader.supportsRecipients()
        ))
    }

    /// The ledger's own triples first (ADR §D3): they are what resolves an id the
    /// index cannot answer for on its own.
    private nonisolated static func resolveMessagesByID(
        reader: MailStoreReader, dossier: Dossier, ledgerEntries: [PraticaLedger.Entry]
    ) -> [String: MailMessageRow] {
        var messagesByID: [String: MailMessageRow] = [:]
        for messageID in Set(dossier.included).union(ledgerEntries.map(\.messageID)) {
            if case .found(let row) = reader.row(forMessageID: messageID) {
                messagesByID[messageID] = row
            }
        }
        return messagesByID
    }

    /// `resolveFollowedConversations`'s three answers, named rather than a raw tuple
    /// so `prepare` reads `followed.conversations`, not `followed.0`.
    private struct FollowedConversations {
        var conversations: [Int: [MailMessageRow]]
        var remap: [Int: Int]
        var unrecoverable: [Int]
    }

    /// §D23.3's recovery: a followed conversation the index answers empty for is
    /// re-derived from the ledger's own known members, and reported as unrecoverable
    /// only once that re-derivation also fails.
    private nonisolated static func resolveFollowedConversations(
        reader: MailStoreReader, dossier: Dossier, ledgerEntries: [PraticaLedger.Entry],
        messagesByID: [String: MailMessageRow]
    ) -> FollowedConversations {
        var conversations: [Int: [MailMessageRow]] = [:]
        var remap: [Int: Int] = [:]
        var unrecoverable: [Int] = []
        let resolved = MembershipStoreSnapshot(conversations: [:], messagesByID: messagesByID)
        for conversation in dossier.conversations {
            let rows = reader.messages(inConversation: conversation)
            guard rows.isEmpty else { conversations[conversation] = rows; continue }
            let members = PraticaLedger.memberMessageIDs(in: ledgerEntries, forConversation: conversation)
            guard !members.isEmpty else { conversations[conversation] = []; continue }
            switch MembershipRule.recoverConversationID(knownMemberMessageIDs: members, store: resolved) {
            case .recovered(let recovered) where recovered != conversation:
                remap[conversation] = recovered
                conversations[recovered] = reader.messages(inConversation: recovered)
            case .recovered:
                conversations[conversation] = []
            case .unrecoverable:
                unrecoverable.append(conversation)
            }
        }
        return FollowedConversations(conversations: conversations, remap: remap, unrecoverable: unrecoverable)
    }

    /// R-30: every conversation touching a counterpart inside the proposal window,
    /// followed or not - the raw material `MembershipRule.trayCandidates` merges
    /// with `conversations` above.
    private nonisolated static func unfollowedConversations(
        reader: MailStoreReader, dossier: Dossier, proposalWindow: ClosedRange<Date>
    ) -> [Int: [MailMessageRow]] {
        var unfollowed: [Int: [MailMessageRow]] = [:]
        for address in dossier.counterparts {
            for conversation in reader.conversations(counterpart: address, within: proposalWindow) {
                unfollowed[conversation.conversationID] = conversation.messages
            }
        }
        return unfollowed
    }
}
