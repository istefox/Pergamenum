import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 3 - §D10.
//
// Lives here, under `Sources/Core/Pratiche` (globbed into `sharedSources`), rather
// than under `Sources/Vault`: a new file there is not in the explicit `sharedSources`
// list (`Project.swift`) and would break both connector builds (C11).

/// Settings › Pratiche (SPEC), nested inside `VaultSettings.pratiche`.
struct PraticheSettings: Codable, Equatable, Sendable {
    /// Folder holding every pratica, relative to the vault root.
    var rootFolder: String
    /// Addresses that count as "me" for `MessageDocument.direction`'s R-12 rule -
    /// per-vault, since the vault is personal (ADR §D10).
    var ownAddresses: [String]
    /// Whether the RFC 822 bytes are kept beside the markdown as `.eml` (R-09).
    var keepOriginalEML: Bool
    /// MB above which an attachment is recorded as a store reference instead of
    /// copied (R-10).
    var attachmentThresholdMB: Int
    /// Days back the tray's proposal window looks (SPEC "Membership rule").
    var proposalWindowDays: Int
    /// Whether a manual entry also appends a line to that day's daily note (SPEC
    /// "Manual entries").
    var mirrorsToDailyNote: Bool

    static let defaultRootFolder = "01 Progetti"
    static let defaultAttachmentThresholdMB = 100
    static let defaultProposalWindowDays = 90

    static let `default` = PraticheSettings(
        rootFolder: PraticheSettings.defaultRootFolder,
        ownAddresses: [],
        keepOriginalEML: true,
        attachmentThresholdMB: PraticheSettings.defaultAttachmentThresholdMB,
        proposalWindowDays: PraticheSettings.defaultProposalWindowDays,
        mirrorsToDailyNote: true
    )

    /// A hand-edited `0` must not silently mean "propose nothing"/"never threshold"
    /// (ADR §D10, the same reasoning `VaultSettings.blockMinutes`/`rolloverDays`
    /// already apply).
    static let attachmentThresholdRange = 1...10_000
    static let proposalWindowRange = 1...365

    init(
        rootFolder: String,
        ownAddresses: [String],
        keepOriginalEML: Bool,
        attachmentThresholdMB: Int,
        proposalWindowDays: Int,
        mirrorsToDailyNote: Bool
    ) {
        self.rootFolder = rootFolder
        self.ownAddresses = ownAddresses
        self.keepOriginalEML = keepOriginalEML
        self.attachmentThresholdMB = attachmentThresholdMB
        self.proposalWindowDays = proposalWindowDays
        self.mirrorsToDailyNote = mirrorsToDailyNote
    }

    /// Decoded key by key like `VaultSettings.init(from:)`, so a `settings.json`
    /// written before a key existed does not lose the whole nested value.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = PraticheSettings.default
        rootFolder = try container.decodeIfPresent(String.self, forKey: .rootFolder) ?? fallback.rootFolder
        ownAddresses = try container.decodeIfPresent([String].self, forKey: .ownAddresses)
            ?? fallback.ownAddresses
        keepOriginalEML = try container.decodeIfPresent(Bool.self, forKey: .keepOriginalEML)
            ?? fallback.keepOriginalEML
        let thresholdMB = try container.decodeIfPresent(Int.self, forKey: .attachmentThresholdMB)
            ?? fallback.attachmentThresholdMB
        attachmentThresholdMB = PraticheSettings.attachmentThresholdRange.clamp(thresholdMB)
        let windowDays = try container.decodeIfPresent(Int.self, forKey: .proposalWindowDays)
            ?? fallback.proposalWindowDays
        proposalWindowDays = PraticheSettings.proposalWindowRange.clamp(windowDays)
        mirrorsToDailyNote = try container.decodeIfPresent(Bool.self, forKey: .mirrorsToDailyNote)
            ?? fallback.mirrorsToDailyNote
    }
}

private extension ClosedRange where Bound == Int {
    func clamp(_ value: Int) -> Int {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
