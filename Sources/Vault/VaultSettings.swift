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

    static let `default` = VaultSettings(
        dailyFolder: "Calendar",
        harnessRepositoryPath: nil,
        copyDroppedFiles: true
    )
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
