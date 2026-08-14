import Foundation

/// The per-vault settings stored in `.pergamenum/settings.json`.
///
/// They live in the vault rather than in `UserDefaults` because they describe the
/// vault: opening the same folder on another Mac must find the same daily folder,
/// and a vault copied to a colleague carries its own configuration.
struct VaultSettings: Codable, Equatable, Sendable {
    /// Folder holding the `YYYYMMDD.md` daily notes, relative to the vault root.
    var dailyFolder: String
    /// Where the `harness-system` checkout lives, for "Importa convenzioni…".
    /// Absolute, and absent until the user points at it.
    var harnessRepositoryPath: String?
    /// Copy a dropped file into the vault, or reference it where it lies.
    var copyDroppedFiles: Bool
    /// Whether the Workspace draws its grid (SPEC §12, "Canvas").
    var boardShowsGrid: Bool
    /// Whether cards land on that grid when nothing else aligns them.
    var boardSnapsToGrid: Bool
    /// How long a time block lasts when the app makes one (SPEC §8.3 puts the default
    /// at 30 minutes; this is that default, made settable).
    var blockMinutes: Int

    static let `default` = VaultSettings(
        dailyFolder: "Calendar",
        harnessRepositoryPath: nil,
        copyDroppedFiles: true,
        boardShowsGrid: true,
        boardSnapsToGrid: false,
        blockMinutes: TimeBlock.defaultDuration
    )

    /// The durations the settings offer, in minutes.
    static let blockDurations = [15, 30, 45, 60, 90, 120]

    /// Decoded key by key, each falling back to its default.
    ///
    /// The synthesised initialiser would reject a `settings.json` written before a
    /// key existed, and the whole file would be discarded for one missing line: a
    /// vault would silently lose its daily folder the first time this struct grows.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = VaultSettings.default
        dailyFolder = try container.decodeIfPresent(String.self, forKey: .dailyFolder)
            ?? fallback.dailyFolder
        harnessRepositoryPath = try container.decodeIfPresent(String.self, forKey: .harnessRepositoryPath)
        copyDroppedFiles = try container.decodeIfPresent(Bool.self, forKey: .copyDroppedFiles)
            ?? fallback.copyDroppedFiles
        boardShowsGrid = try container.decodeIfPresent(Bool.self, forKey: .boardShowsGrid)
            ?? fallback.boardShowsGrid
        boardSnapsToGrid = try container.decodeIfPresent(Bool.self, forKey: .boardSnapsToGrid)
            ?? fallback.boardSnapsToGrid
        // Clamped as well as defaulted: a hand-edited settings.json holding 0 would
        // make every block zero minutes long and every one of them invisible.
        let minutes = try container.decodeIfPresent(Int.self, forKey: .blockMinutes)
            ?? fallback.blockMinutes
        blockMinutes = min(max(minutes, 5), 480)
    }

    init(
        dailyFolder: String,
        harnessRepositoryPath: String?,
        copyDroppedFiles: Bool,
        boardShowsGrid: Bool,
        boardSnapsToGrid: Bool,
        blockMinutes: Int = TimeBlock.defaultDuration
    ) {
        self.dailyFolder = dailyFolder
        self.harnessRepositoryPath = harnessRepositoryPath
        self.copyDroppedFiles = copyDroppedFiles
        self.boardShowsGrid = boardShowsGrid
        self.boardSnapsToGrid = boardSnapsToGrid
        self.blockMinutes = blockMinutes
    }
}

/// The app's private directory inside the vault, and the file names in it.
enum VaultLayout {
    static let privateDirectory = ".pergamenum"
    static let settingsFile = "settings.json"
    static let vocabularyFile = "vocabolari.json"
    static let themesDirectory = "themes"
    static let thumbnailsDirectory = "thumbnails"
    static let cacheFile = "cache.db"

    /// Directory names never scanned for notes.
    ///
    /// `.pergamenum` is ours, `.obsidian` and `.trash` belong to Obsidian, and any
    /// other dot-directory is somebody's tooling. Indexing `.git` on a vault kept
    /// under version control would be both slow and wrong.
    static func isExcludedDirectory(_ name: String) -> Bool {
        name.hasPrefix(".")
    }
}
