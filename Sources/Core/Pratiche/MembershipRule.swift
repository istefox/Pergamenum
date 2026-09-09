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
        // Coder-owned. Stubbed empty so every positive membership assertion in
        // `Tests/MembershipRuleTests.swift` is red until the real set-algebra lands.
        Candidates(messages: [], autoFollowedConversations: [])
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
        // Coder-owned.
        []
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
        // Coder-owned.
        .unrecoverable
    }
}
