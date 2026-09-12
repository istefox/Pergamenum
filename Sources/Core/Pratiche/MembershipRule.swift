import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 3 - R-13,
// R-14.

/// A snapshot of just the store facts `MembershipRule` needs, built once per sync from
/// the real `MailStoreReader` (which owns a live, non-`Sendable` SQLite connection and
/// cannot itself be the input of a pure function) - so the rule evaluation stays "a
/// pure function over value types" (SPEC "Membership rule") and a unit test can build
/// one by hand instead of standing up a fixture database for every case (R-13: "unit-
/// tested without touching `~/Library/Mail`").
struct MembershipStoreSnapshot: Equatable, Sendable {
    /// Every non-deleted message of every conversation this snapshot loaded, keyed by
    /// `conversation_id`. A conversation id absent here answers `.unrecoverable` from
    /// `MembershipRule.recoverConversationID` unless a member resolves through
    /// `messagesByID`.
    var conversations: [Int: [MailMessageRow]]
    /// Every message this snapshot loaded, by RFC `Message-ID` - the ledger-resolved
    /// lookup `MailStoreReader.row(forMessageID:)` cannot always answer on its own
    /// (ADR §D3), pre-resolved by the caller before this pure function ever runs.
    var messagesByID: [String: MailMessageRow]
    /// Every message of every conversation the counterpart search found inside the
    /// proposal window, followed or not - the pool rule 3's keyword arm scans and the
    /// tray proposes from. Separate from `conversations` on purpose: rule 1 imports
    /// what `dossier.conversations` names, and nothing here is followed yet.
    var unfollowed: [Int: [MailMessageRow]] = [:]

    static let empty = MembershipStoreSnapshot(conversations: [:], messagesByID: [:])

    /// One conversation's messages, followed or not (ADR §D22.1). Tester stub
    /// (ADR-0155 §D1): trivial and pure, implemented for real rather than left as a
    /// no-op stub, since there is no judgment call in a one-line union of two
    /// dictionary lookups. `MembershipRule.everyMessage(in:)` does not call this yet -
    /// that rewiring is coder work per §D22.1.
    func messages(inConversation id: Int) -> [MailMessageRow] {
        conversations[id] ?? unfollowed[id] ?? []
    }
}

enum MembershipRule {
    struct Candidates: Equatable, Sendable {
        /// The messages to import this sync (item 1 ∪ 2 ∪ 3, minus 4, minus 5 - SPEC
        /// "Membership rule").
        var messages: [MailMessageRow]
        /// Conversations a keyword match auto-followed this evaluation (item 3) -
        /// written back to `pratica.md`'s `pergamenum-dossier-conversations` by the
        /// ordinary write path, not by this pure function.
        var autoFollowedConversations: [Int]
    }

    /// R-13's candidate set: every non-deleted message in `store` whose
    /// `conversation_id ∈ dossier.conversations`, plus every message whose
    /// `Message-ID ∈ dossier.included`, plus (when `dossier.keywords` is non-empty)
    /// every message from/to a `dossier.counterparts` address whose subject contains
    /// one keyword - minus `dossier.excluded`, minus `onDisk` (dedup by `Message-ID`).
    static func candidates(
        dossier: Dossier,
        store: MembershipStoreSnapshot,
        onDisk: Set<String>
    ) -> Candidates {
        var collected: [MailMessageRow] = []
        var autoFollowed: [Int] = []

        // 1. every non-deleted message of a followed conversation - through
        //    `store.messages(inConversation:)` (§D22.3) so a conversation this very
        //    evaluation just auto-followed (rule 3, still only in `unfollowed` at this
        //    point) is reachable on the second pass without a second snapshot.
        for conversation in dossier.conversations {
            collected.append(contentsOf: store.messages(inConversation: conversation).filter { !$0.deleted })
        }
        // 2. plus every message added by hand, wherever it lives.
        for messageID in dossier.included {
            if let row = store.messagesByID[messageID], !row.deleted { collected.append(row) }
        }
        // 3. plus a keyword match on a counterpart's message - which also follows that
        //    conversation from now on. The caller (`PraticheController.runExclusive`,
        //    §D22.3) re-evaluates once more with the id written into `dossier`, so the
        //    rest of the thread arrives through rule 1 in this same sync.
        if !dossier.keywords.isEmpty {
            let counterparts = Set(dossier.counterparts.map { $0.lowercased() })
            let keywords = dossier.keywords.map { $0.lowercased() }
            // The two membership tests below run once per message in the store; the array
            // `autoFollowed` stays the answer, because its order is what the caller writes
            // into the dossier, and the Set beside it only answers "already seen".
            let followed = Set(dossier.conversations)
            var autoFollowedIDs = Set<Int>()
            for row in everyMessage(in: store) where !row.deleted {
                guard touches(row, counterparts: counterparts) else { continue }
                let subject = (row.subject ?? "").lowercased()
                guard keywords.contains(where: { !$0.isEmpty && subject.contains($0) }) else { continue }
                collected.append(row)
                if let conversation = row.conversationID,
                   !followed.contains(conversation),
                   autoFollowedIDs.insert(conversation).inserted {
                    autoFollowed.append(conversation)
                }
            }
        }

        // 4. minus what was removed by hand, 5. minus what is already on disk.
        let excluded = Set(dossier.excluded).union(onDisk)
        let kept = deduplicated(collected).filter { row in
            guard let messageID = row.messageID else { return true }
            return !excluded.contains(messageID)
        }
        // Newest first: the sync writes in this order, so what changed lands first
        // (SPEC "Sync algorithm").
        return Candidates(
            messages: kept.sorted { date(of: $0) > date(of: $1) },
            autoFollowedConversations: autoFollowed
        )
    }

    /// §D22.1: widens the keyword arm's pool to `unfollowed`, the counterpart-search
    /// results the tray already loads - used by rule 3 and by nothing else, so this
    /// change reaches only the keyword arm, never rule 1 or rule 2.
    private static func everyMessage(in store: MembershipStoreSnapshot) -> [MailMessageRow] {
        deduplicated(
            store.conversations.values.flatMap { $0 }
                + store.unfollowed.values.flatMap { $0 }
                + store.messagesByID.values
        )
    }

    /// SPEC "Membership rule": a message *from or to* a counterpart. The tray
    /// (`trayCandidates`) and the keyword arm (`candidates`, rule 3) ask this same
    /// question and must never answer it differently - the sender-only version of this
    /// check is what made an outgoing-only conversation invisible to both.
    private static func touches(_ row: MailMessageRow, counterparts: Set<String>) -> Bool {
        if let sender = row.sender?.lowercased(), counterparts.contains(sender) { return true }
        return row.recipients.contains { counterparts.contains($0.lowercased()) }
    }

    /// One message reaches a pratica through several routes at once (a followed
    /// conversation *and* a keyword), and Sent/Archive hold the same `Message-ID`
    /// twice (ADR §D15). Deduplicated on the RFC id where there is one, on the index
    /// ROWID otherwise, keeping the first occurrence.
    private static func deduplicated(_ rows: [MailMessageRow]) -> [MailMessageRow] {
        var seen: Set<String> = []
        var unique: [MailMessageRow] = []
        for row in rows {
            let key = row.messageID ?? "rowid:\(row.rowID)"
            guard seen.insert(key).inserted else { continue }
            unique.append(row)
        }
        return unique
    }

    private static func date(of row: MailMessageRow) -> Date {
        row.dateSent ?? row.dateReceived ?? .distantPast
    }

    struct TrayEntry: Equatable, Sendable {
        var conversationID: Int
        var messages: [MailMessageRow]
    }

    /// R-13's tray set: every conversation in `store` with at least one message
    /// from/to a `dossier.counterparts` address, dated within `window`, not in
    /// `dossier.conversations`, not in `dossier.ignored`, and not already claimed by
    /// another pratica following the same counterpart (`claimedByOtherPratiche`).
    static func trayCandidates(
        dossier: Dossier,
        store: MembershipStoreSnapshot,
        window: ClosedRange<Date>,
        claimedByOtherPratiche: Set<Int>
    ) -> [TrayEntry] {
        let counterparts = Set(dossier.counterparts.map { $0.lowercased() })
        let followed = Set(dossier.conversations)
        let ignored = Set(dossier.ignored)

        // §D22.2: `unfollowed` folded in so one snapshot serves both `candidates` and
        // this call - its own `!followed.contains` guard below already excludes
        // anything in `dossier.conversations`, so this changes no tray output.
        let allConversations = store.conversations.merging(store.unfollowed) { existing, _ in existing }

        var entries: [TrayEntry] = []
        for (conversationID, messages) in allConversations {
            guard !followed.contains(conversationID),
                  !ignored.contains(conversationID),
                  !claimedByOtherPratiche.contains(conversationID)
            else { continue }
            let live = messages.filter { !$0.deleted }
            let touchesCounterpart = live.contains { row in
                touches(row, counterparts: counterparts) && window.contains(date(of: row))
            }
            guard touchesCounterpart else { continue }
            entries.append(TrayEntry(conversationID: conversationID, messages: live))
        }
        // Newest conversation first, and the id as a tiebreak so the tray's order is a
        // function of its contents rather than of a dictionary's iteration.
        //
        // Each entry's newest date is taken once and carried beside it: read from inside
        // the comparator, a conversation's whole message list is walked again on every
        // comparison it takes part in.
        return entries
            .map { (newest: $0.messages.map(date).max() ?? .distantPast, entry: $0) }
            .sorted { left, right in
                if left.newest != right.newest { return left.newest > right.newest }
                return left.entry.conversationID < right.entry.conversationID
            }
            .map(\.entry)
    }

    enum ConversationRecovery: Equatable, Sendable {
        case recovered(Int)
        /// R-14: reported, never silently dropped - the tray's own «non più
        /// ricostruibile» state (SPEC "Edge cases").
        case unrecoverable
    }

    /// R-14: re-derives a `conversation_id` Mail may have renumbered, from any member
    /// message's `Message-ID` the ledger recorded for it - never from the index's own
    /// (unstable) integer.
    static func recoverConversationID(
        knownMemberMessageIDs: [String],
        store: MembershipStoreSnapshot
    ) -> ConversationRecovery {
        for messageID in knownMemberMessageIDs {
            guard let conversationID = store.messagesByID[messageID]?.conversationID else { continue }
            return .recovered(conversationID)
        }
        // Every member the ledger knows about is gone from the store: reported, so the
        // tray can draw «non più ricostruibile» (R-14). Silently dropping the
        // conversation would make a pratica quietly stop receiving mail.
        return .unrecoverable
    }
}
