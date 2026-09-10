import Foundation

// ADR-0036 (Pratiche), SPEC "Rilevazione di nuove controparti nella wizard «Nuova
// pratica»" (docs/specs archive: rileva-nuove-controparti-wizard-pratiche) - R-01
// through R-07, R-10.
//
// A long Mail thread routinely gains new participants mid-conversation (typically
// via Cc), and one of them can go on to write directly without including any of the
// pratica's known counterparts. This reduces every message of the conversation(s)
// the wizard's step 3 ticked to the set of addresses that took part but are not yet
// a counterpart - `PraticaTrayModel.proposals(from:ownAddresses:)`'s own sibling: a
// pure reduction over already-fetched `MailMessageRow`s, no second Mail-store read.
enum NewCounterpartDetector {
    /// One address the wizard could offer as an additional counterpart.
    struct NewCounterpartCandidate: Equatable, Sendable, Identifiable {
        var id: String { address }
        var address: String
        /// Whether this address was ever the sender of a message, not only a
        /// recipient - the group a candidate is ranked into (R-04).
        var wroteAtLeastOnce: Bool
        /// Messages this address took part in (as sender or recipient), counted
        /// once per message even when both roles occur across different messages
        /// (R-04's edge case: sender-and-Cc-both counts as sender, count summed).
        var messageCount: Int
    }

    /// Every address in `messages` that is neither an existing counterpart nor one
    /// of the person's own addresses, ranked senders-first (each block descending
    /// by message count, ties broken alphabetically for a deterministic order).
    ///
    /// Returns the full ranked list, uncapped - the 10-item cap and "e altri N
    /// indirizzi ignorati" summary are what the wizard step draws, not what this
    /// reduction decides (`PraticaTrayModel`'s own split between reduction and
    /// display).
    static func candidates(
        in messages: [MailMessageRow], counterparts: [String], ownAddresses: Set<String>
    ) -> [NewCounterpartCandidate] {
        let known = Set(counterparts.map(normalize))
        let mine = Set(ownAddresses.map(normalize))
        var messageCountByAddress: [String: Int] = [:]
        var wroteFlag: Set<String> = []

        for message in messages {
            var participants = Set<String>()
            let sender = message.sender.map(normalize) ?? ""
            if !sender.isEmpty { participants.insert(sender) }
            for recipient in message.recipients.map(normalize) where !recipient.isEmpty {
                participants.insert(recipient)
            }
            for address in participants where !known.contains(address) && !mine.contains(address) {
                messageCountByAddress[address, default: 0] += 1
            }
            if !sender.isEmpty, !known.contains(sender), !mine.contains(sender) {
                wroteFlag.insert(sender)
            }
        }

        return messageCountByAddress
            .map { address, count in
                NewCounterpartCandidate(
                    address: address, wroteAtLeastOnce: wroteFlag.contains(address), messageCount: count
                )
            }
            .sorted { lhs, rhs in
                if lhs.wroteAtLeastOnce != rhs.wroteAtLeastOnce { return lhs.wroteAtLeastOnce }
                if lhs.messageCount != rhs.messageCount { return lhs.messageCount > rhs.messageCount }
                return lhs.address < rhs.address
            }
    }

    /// Lower-cased and trimmed - the comparison convention every other address in
    /// this feature area already follows (`PraticaTrayModel`, `MessageDocument`,
    /// `WizardState.makeDossier()`).
    private static func normalize(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
