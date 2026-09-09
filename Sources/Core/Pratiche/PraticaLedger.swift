import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 3 - §D3.

/// The `Message-ID` ↔ index-ROWID ↔ `conversation_id` bridge (ADR §D3): the index is
/// never asked to resolve a `Message-ID` string on this fixture's schema (and on
/// 3.1% of rows even on a real one), so this file is what makes R-14's re-derivation
/// possible. Regenerable from what is on disk (CLAUDE.md principle 3's rebuildable-
/// index rule, applied to non-index state): deleting it costs one full re-sync,
/// nothing else (SPEC "Per-vault state").
struct PraticaLedger: Equatable, Sendable, Codable {
    /// One imported message's bridge triple (ADR §D3).
    struct Entry: Equatable, Sendable, Codable {
        var messageID: String
        var rowID: Int
        var conversationID: Int
    }

    /// Per-pratica state, keyed by the pratica folder's vault-relative path (SPEC
    /// "Per-vault state": `{ praticaPath: { lastSyncAt, lastOpenedAt,
    /// importedMessageIDs, pending } }`).
    struct PraticaState: Equatable, Sendable, Codable {
        var lastSyncAt: Date?
        var lastOpenedAt: Date?
        var importedMessageIDs: [String]
        var pending: [String]
        /// The bridge triples this pratica has ever imported - what
        /// `memberMessageIDs(forConversation:praticaPath:)` reads for R-14.
        var entries: [Entry]

        static let empty = PraticaState(
            lastSyncAt: nil, lastOpenedAt: nil, importedMessageIDs: [], pending: [], entries: []
        )
    }

    var byPraticaPath: [String: PraticaState]

    static let empty = PraticaLedger(byPraticaPath: [:])

    /// Reads `ledger.json` from the per-vault state directory (ADR-0017 precedent).
    /// Missing or unreadable → `.empty`: a fresh ledger costs one full re-sync,
    /// nothing else.
    static func load(from url: URL) -> PraticaLedger {
        // Coder-owned.
        .empty
    }

    func save(to url: URL) throws {
        // Coder-owned.
    }

    /// R-14: every member `Message-ID` this ledger ever recorded for
    /// `conversationID` under `praticaPath`, in no particular order - what
    /// `MembershipRule.recoverConversationID` resolves against the store snapshot.
    func memberMessageIDs(forConversation conversationID: Int, praticaPath: String) -> [String] {
        // Coder-owned.
        []
    }
}
