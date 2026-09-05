import Foundation

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 3 -
// R-10, R-11, R-12; ADR §D12.
//
// Two JSON files beside the vault's own derived state: `plaud.json` (the ledger - the
// `days` window, the notes folder, and one `Entry` per recording) and `plaud-drafts.json`
// (pending review decisions, keyed by recording id).
//
// `directory` is injected and never resolved here: `VaultState.applicationSupportBase()`
// carries a `precondition` that fires under test (`VaultState.swift:67-71`), so the caller
// hands in `<state base>/vaults/<vaultID>/` in production and a scratch temporary directory
// under test (ADR-0017 §Consequences - 860 stray directories from one afternoon otherwise).
//
// These are this app's own local cache files, not the Plaud wire contract
// (`PlaudPayloads.swift`), so plain camelCase `Codable` is used throughout - there is no
// snake_case on either side of this boundary to avoid converting.
//
// STUB for this batch (ADR-0155, tester owns the interface / coder owns the body): every
// read/write method below ignores `directory` and returns a fixed placeholder. The
// `Ledger`, `Entry` and `Draft` shapes are real - `Tests/PlaudVaultStoreTests.swift` is
// written against them - only the disk I/O, the `decodeIfPresent`-with-fallback resilience
// (`VaultSettings.init(from:)`'s pattern, `VaultSettings.swift:161-211`) and the `days`
// clamp are the coder's next task.
struct PlaudVaultStore: Sendable {
    static let ledgerFileName = "plaud.json"
    static let draftsFileName = "plaud-drafts.json"
    static let defaultDays = 14
    static let minimumDays = 1
    static let maximumDays = 3650
    static let defaultNotesFolder = "Registrazioni"

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// `plaud.json`'s shape (ADR §D12).
    struct Ledger: Codable, Equatable, Sendable {
        var days: Int
        var notesFolder: String
        var recordings: [String: Entry]

        static let empty = Ledger(
            days: PlaudVaultStore.defaultDays,
            notesFolder: PlaudVaultStore.defaultNotesFolder,
            recordings: [:]
        )

        init(days: Int, notesFolder: String, recordings: [String: Entry]) {
            self.days = days
            self.notesFolder = notesFolder
            self.recordings = recordings
        }
    }

    /// One recording's local state inside the ledger: local status, the note once written,
    /// the accepted-quote fingerprints (ADR §D9), and whether the confirm call is still
    /// owed (ADR §D13).
    struct Entry: Codable, Equatable, Sendable {
        var status: String
        var notePath: String?
        var quoteFingerprints: [String]
        var pendingConfirmation: [String]
        var lastImportedAt: String?

        init(
            status: String,
            notePath: String? = nil,
            quoteFingerprints: [String] = [],
            pendingConfirmation: [String] = [],
            lastImportedAt: String? = nil
        ) {
            self.status = status
            self.notePath = notePath
            self.quoteFingerprints = quoteFingerprints
            self.pendingConfirmation = pendingConfirmation
            self.lastImportedAt = lastImportedAt
        }
    }

    /// `plaud-drafts.json`'s shape (ADR §D12): one pending review per recording, keyed by
    /// recording id. Invalidated by `draft(for:currentGeneratedAt:)` whenever `generatedAt`
    /// no longer matches the proposal just read (R-10's boundary) - task ids are stable
    /// only within one proposal.
    struct Draft: Codable, Equatable, Sendable {
        var generatedAt: String
        var decisions: [String: Bool]
        var speakerRenames: [String: String]

        init(generatedAt: String, decisions: [String: Bool] = [:], speakerRenames: [String: String] = [:]) {
            self.generatedAt = generatedAt
            self.decisions = decisions
            self.speakerRenames = speakerRenames
        }
    }

    // MARK: - plaud.json

    /// Reads `plaud.json`, returning `.empty` for a missing or corrupt file - never
    /// throwing, and never touching a corrupt file on disk (the person may want to recover
    /// it by hand).
    ///
    /// STUB (RED baseline, not yet implemented): ignores `directory` entirely and always
    /// returns `.empty`. The coder reads `directory/Self.ledgerFileName`, decodes key by key
    /// with a fallback (`VaultSettings.init(from:)`'s pattern), and clamps `days` to
    /// `Self.minimumDays...Self.maximumDays` on the way in.
    func loadLedger() -> Ledger {
        .empty
    }

    /// STUB (RED baseline, not yet implemented): a no-op. The coder creates `directory` if
    /// needed and writes atomically.
    func saveLedger(_ ledger: Ledger) throws {}

    // MARK: - plaud-drafts.json

    /// STUB (RED baseline, not yet implemented): always empty, ignoring `directory`.
    func loadDrafts() -> [String: Draft] {
        [:]
    }

    /// STUB (RED baseline, not yet implemented): a no-op.
    func saveDrafts(_ drafts: [String: Draft]) throws {}

    /// The draft for a recording, discarded when its `generatedAt` no longer matches the
    /// proposal just read (R-10's boundary, ADR §D12).
    ///
    /// STUB (RED baseline, not yet implemented): always `nil`, ignoring both `directory` and
    /// `currentGeneratedAt`. The coder compares `loadDrafts()[recordingID]?.generatedAt`
    /// against `currentGeneratedAt` and returns the stored draft only when they match.
    func draft(for recordingID: String, currentGeneratedAt: String) -> Draft? {
        nil
    }
}
