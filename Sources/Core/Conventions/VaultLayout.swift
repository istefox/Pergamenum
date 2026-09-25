import Foundation

/// The app's private directory inside the vault, and the file names in it.
///
/// `thumbnails/` and `cache.db` used to live here too; ADR-0017 moves both beside the
/// vault instead, and their names now live on `VaultState`.
enum VaultLayout {
    static let privateDirectory = ".pergamenum"
    static let settingsFile = "settings.json"
    static let vocabularyFile = "vocabolari.json"
    static let themesDirectory = "themes"
    /// The starred notes of ADR-0012 D6. In the vault because starring describes the notes and
    /// travels with them; the open tabs describe this machine and stay in `UserDefaults`.
    static let starredFile = "starred.json"
    /// The category registry of ADR-0047 §D2, beside `vocabolari.json`: a readable file
    /// that travels with the vault, and not an index - deleting it loses the registry
    /// and no task.
    static let categoriesFile = "categories.json"
    /// The stable note-id registry of ADR-0059 §D1, beside `starred.json` and
    /// `categories.json`: in the vault because an id names a note on every Mac that
    /// opens it, and it is not an index - `cache.db` is rebuildable and this is not.
    static let noteIDsFile = "note-ids.json"

    /// Directory names never scanned for notes.
    ///
    /// `.pergamenum` is ours, `.obsidian` and `.trash` belong to Obsidian, and any
    /// other dot-directory is somebody's tooling. Indexing `.git` on a vault kept
    /// under version control would be both slow and wrong.
    static func isExcludedDirectory(_ name: String) -> Bool {
        name.hasPrefix(".")
    }
}
