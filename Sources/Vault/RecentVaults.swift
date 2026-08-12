import Foundation

/// The vaults opened before, most recent first (SPEC §10, File › Vault recenti).
///
/// A per-user preference rather than vault-private data, so it lives in
/// `UserDefaults`: the list of vaults *this Mac* has opened is not something to write
/// inside one of them.
struct RecentVaults {
    static let maximum = 8
    private static let key = "recentVaults"

    private let defaults: UserDefaults

    /// A list backed by a throwaway suite, for tests.
    ///
    /// Not a convenience: with the real `UserDefaults`, running the suite left the
    /// user's own recents list full of temporary vaults and the app reopened one of
    /// them at launch. Running the tests must not change the app.
    static func volatile() -> RecentVaults {
        RecentVaults(defaults: UserDefaults(suiteName: "pergamenum.tests.\(UUID())") ?? .standard)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Paths of the vaults opened before, most recent first, filtered to those that
    /// still exist.
    ///
    /// A vault on an unmounted disk or since deleted is dropped rather than offered:
    /// a recents menu whose entries fail when clicked is worse than a shorter one.
    var paths: [String] {
        (defaults.stringArray(forKey: Self.key) ?? []).filter { path in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        }
    }

    var urls: [URL] { paths.map { URL(filePath: $0, directoryHint: .isDirectory) } }

    /// The vault to reopen at launch, when there is one.
    var mostRecent: URL? { urls.first }

    /// Moves a vault to the front of the list.
    func remember(_ url: URL) {
        // Symlinks resolved: /tmp and /private/tmp are the same vault, and listing it
        // twice would offer the user a choice that is not one.
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        var updated = paths.filter { $0 != path }
        updated.insert(path, at: 0)
        defaults.set(Array(updated.prefix(Self.maximum)), forKey: Self.key)
    }

    func forgetAll() {
        defaults.removeObject(forKey: Self.key)
    }
}
