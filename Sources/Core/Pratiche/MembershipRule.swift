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

    static let empty = MembershipStoreSnapshot(conversations: [:], messagesByID: [:])
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

        // 1. every non-deleted message of a followed conversation.
        for conversation in dossier.conversations {
            collected.append(contentsOf: (store.conversations[conversation] ?? []).filter { !$0.deleted })
        }
        // 2. plus every message added by hand, wherever it lives.
        for messageID in dossier.included {
            if let row = store.messagesByID[messageID], !row.deleted { collected.append(row) }
        }
        // 3. plus a keyword match on a counterpart's message - which also follows that
        //    conversation from now on, so the rest of the thread arrives by rule 1 next
        //    sync instead of depending on every subject repeating the keyword.
        if !dossier.keywords.isEmpty {
            let counterparts = Set(dossier.counterparts.map { $0.lowercased() })
            let keywords = dossier.keywords.map { $0.lowercased() }
            for row in everyMessage(in: store) where !row.deleted {
                guard let sender = row.sender?.lowercased(), counterparts.contains(sender) else { continue }
                let subject = (row.subject ?? "").lowercased()
                guard keywords.contains(where: { !$0.isEmpty && subject.contains($0) }) else { continue }
                collected.append(row)
                if let conversation = row.conversationID,
                   !dossier.conversations.contains(conversation),
                   !autoFollowed.contains(conversation) {
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

    private static func everyMessage(in store: MembershipStoreSnapshot) -> [MailMessageRow] {
        deduplicated(store.conversations.values.flatMap { $0 } + store.messagesByID.values)
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

        var entries: [TrayEntry] = []
        for (conversationID, messages) in store.conversations {
            guard !followed.contains(conversationID),
                  !ignored.contains(conversationID),
                  !claimedByOtherPratiche.contains(conversationID)
            else { continue }
            let live = messages.filter { !$0.deleted }
            let touchesCounterpart = live.contains { row in
                guard let sender = row.sender?.lowercased() else { return false }
                return counterparts.contains(sender) && window.contains(date(of: row))
            }
            guard touchesCounterpart else { continue }
            entries.append(TrayEntry(conversationID: conversationID, messages: live))
        }
        // Newest conversation first, and the id as a tiebreak so the tray's order is a
        // function of its contents rather than of a dictionary's iteration.
        return entries.sorted { left, right in
            let leftDate = left.messages.map(date).max() ?? .distantPast
            let rightDate = right.messages.map(date).max() ?? .distantPast
            if leftDate != rightDate { return leftDate > rightDate }
            return left.conversationID < right.conversationID
        }
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
