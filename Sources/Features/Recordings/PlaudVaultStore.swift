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

        /// Decoded key by key, each falling back to its default - `VaultSettings.init(from:)`'s
        /// pattern (`VaultSettings.swift:161-211`): a `plaud.json` written before a key existed
        /// must not be discarded whole, or a vault would silently lose every fingerprint it has
        /// recorded the first time this struct grows.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let fallback = Ledger.empty
            // Clamped as well as defaulted, like `VaultSettings.blockMinutes`: the service
            // answers 400 `invalid_days` outside 1...3650, and this file is meant to be
            // readable and editable by hand.
            let storedDays = try container.decodeIfPresent(Int.self, forKey: .days) ?? fallback.days
            days = min(max(storedDays, PlaudVaultStore.minimumDays), PlaudVaultStore.maximumDays)
            notesFolder = try container.decodeIfPresent(String.self, forKey: .notesFolder)
                ?? fallback.notesFolder
            recordings = try container.decodeIfPresent([String: Entry].self, forKey: .recordings)
                ?? fallback.recordings
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

        /// Key by key with a fallback, for the same reason as `Ledger.init(from:)` and with
        /// one extra: an entry that loses its fingerprints would re-import every task it had
        /// already imported, so a partial entry is kept and read defensively rather than
        /// dropped along with the whole file.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // `new` is the state a recording has before this app has done anything to it,
            // and the safest reading of an entry whose status went missing.
            status = try container.decodeIfPresent(String.self, forKey: .status) ?? "new"
            notePath = try container.decodeIfPresent(String.self, forKey: .notePath)
            quoteFingerprints = try container.decodeIfPresent([String].self, forKey: .quoteFingerprints)
                ?? []
            pendingConfirmation = try container.decodeIfPresent([String].self, forKey: .pendingConfirmation)
                ?? []
            lastImportedAt = try container.decodeIfPresent(String.self, forKey: .lastImportedAt)
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

        /// Key by key with a fallback, and the fallback for `generatedAt` fails closed: an
        /// empty string matches no proposal's own `generated_at`, so a draft that lost it is
        /// discarded by `draft(for:currentGeneratedAt:)` rather than applied to task ids it
        /// was never decided against.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
            decisions = try container.decodeIfPresent([String: Bool].self, forKey: .decisions) ?? [:]
            speakerRenames = try container.decodeIfPresent([String: String].self, forKey: .speakerRenames)
                ?? [:]
        }
    }

    // MARK: - plaud.json

    var ledgerURL: URL {
        directory.appending(path: Self.ledgerFileName, directoryHint: .notDirectory)
    }

    /// Reads `plaud.json`, returning `.empty` for a missing or corrupt file - never
    /// throwing, and never touching a corrupt file on disk (the person may want to recover
    /// it by hand). `StarredStore.load`'s call, for the same reason: losing the ledger costs
    /// a duplicate-detection pass, and refusing to open the pane over it would be the tail
    /// wagging the dog.
    func loadLedger() -> Ledger {
        guard let data = try? Data(contentsOf: ledgerURL),
              let ledger = try? JSONDecoder().decode(Ledger.self, from: data)
        else { return .empty }
        return ledger
    }

    /// Writes `plaud.json`, creating `directory` first if the vault has never had one.
    ///
    /// Throwing where `loadLedger` swallows: a failed read is recoverable by re-deriving
    /// from the notes, a failed write means the caller's `pendingConfirmation` never reached
    /// disk and the caller has to know (ADR §D13's two-phase import rests on it).
    func saveLedger(_ ledger: Ledger) throws {
        try write(ledger, to: ledgerURL)
    }

    // MARK: - plaud-drafts.json

    var draftsURL: URL {
        directory.appending(path: Self.draftsFileName, directoryHint: .notDirectory)
    }

    func loadDrafts() -> [String: Draft] {
        guard let data = try? Data(contentsOf: draftsURL),
              let drafts = try? JSONDecoder().decode([String: Draft].self, from: data)
        else { return [:] }
        return drafts
    }

    func saveDrafts(_ drafts: [String: Draft]) throws {
        try write(drafts, to: draftsURL)
    }

    /// The draft for a recording, discarded when its `generatedAt` no longer matches the
    /// proposal just read (R-10's boundary, ADR §D12) - task ids are stable only within one
    /// proposal, so decisions taken against an older run name different tasks.
    func draft(for recordingID: String, currentGeneratedAt: String) -> Draft? {
        guard let draft = loadDrafts()[recordingID],
              draft.generatedAt == currentGeneratedAt
        else { return nil }
        return draft
    }

    // MARK: - Writing

    /// Sorted keys because both files are meant to be read by a person: a dictionary written
    /// in hash order would look different on every save (`StarredStore.save`'s reasoning).
    private func write(_ value: some Encodable, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
