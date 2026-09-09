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
        /// `Message-ID`s the ledger has recorded as deleted from Mail after import
        /// (R-16/R-26): the batch-4/5 gap this field closes - `PraticaTimelineModel.
        /// subjectLink(messageID:isInMail:)` already draws «non più in Mail» for
        /// `isInMail == false`, and the coder's `PraticaSyncEngine`/
        /// `PraticheController.readTimeline` wire this list into that `isInMail`
        /// (plan Task 7/8's "R-16/R-26 gap left by batch 4", ADR follow-up "Task 5/6
        /// implementation notes"). Never a locator miss (§D4) - only an outcome the
        /// sync itself records.
        var notInStore: [String]

        static let empty = PraticaState(
            lastSyncAt: nil, lastOpenedAt: nil, importedMessageIDs: [], pending: [], entries: [],
            notInStore: []
        )

        // Manual `Codable` rather than the synthesised one: `notInStore` is a field
        // added after this struct's first shipped shape, and a ledger written by an
        // earlier build of this branch (no key for it at all) must still decode
        // instead of silently resetting the whole ledger to `.empty`
        // (`PraticaLedger.load(from:)`'s own fallback would otherwise discard every
        // other field too, costing a full re-sync for a one-field addition).
        private enum CodingKeys: String, CodingKey {
            case lastSyncAt, lastOpenedAt, importedMessageIDs, pending, entries, notInStore
        }

        init(
            lastSyncAt: Date?, lastOpenedAt: Date?, importedMessageIDs: [String], pending: [String],
            entries: [Entry], notInStore: [String]
        ) {
            self.lastSyncAt = lastSyncAt
            self.lastOpenedAt = lastOpenedAt
            self.importedMessageIDs = importedMessageIDs
            self.pending = pending
            self.entries = entries
            self.notInStore = notInStore
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            lastSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncAt)
            lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
            importedMessageIDs = try container.decodeIfPresent([String].self, forKey: .importedMessageIDs) ?? []
            pending = try container.decodeIfPresent([String].self, forKey: .pending) ?? []
            entries = try container.decodeIfPresent([Entry].self, forKey: .entries) ?? []
            notInStore = try container.decodeIfPresent([String].self, forKey: .notInStore) ?? []
        }
    }

    var byPraticaPath: [String: PraticaState]

    static let empty = PraticaLedger(byPraticaPath: [:])

    /// Reads `ledger.json` from the per-vault state directory (ADR-0017 precedent).
    /// Missing or unreadable → `.empty`: a fresh ledger costs one full re-sync,
    /// nothing else.
    static func load(from url: URL) -> PraticaLedger {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(PraticaLedger.self, from: data)) ?? .empty
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Sorted and pretty-printed on purpose: this file is meant to be readable by
        // the person whose mail it describes, and a stable key order keeps a diff of it
        // meaningful.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // Atomic: a ledger torn by a crash mid-write costs a full re-sync, and the
        // whole point of the file is that it survives one.
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// R-14: every member `Message-ID` this ledger ever recorded for
    /// `conversationID` under `praticaPath`, in no particular order - what
    /// `MembershipRule.recoverConversationID` resolves against the store snapshot.
    func memberMessageIDs(forConversation conversationID: Int, praticaPath: String) -> [String] {
        guard let state = byPraticaPath[praticaPath] else { return [] }
        return state.entries
            .filter { $0.conversationID == conversationID }
            .map(\.messageID)
    }
}
