import Foundation

/// The vaults opened before, most recent first (SPEC §10, File › Vault recenti).
///
/// A per-user preference rather than vault-private data, so it lives in
/// `UserDefaults`: the list of vaults *this Mac* has opened is not something to write
/// inside one of them.
struct RecentVaults {
    static let maximum = 8
    /// Internal rather than private so a test can name the key it is asserting on.
    static let key = "recentVaults"

    private let defaults: UserDefaults

    /// True when the list was handed to this launch on the command line, as
    /// `-recentVaults "(…)"`.
    ///
    /// The argument domain outranks the persistent one, so an override is what the app
    /// reads for the whole session no matter what is written underneath it. Writing
    /// underneath it anyway is how the UI suite emptied the user's real list: each run
    /// pointed the app at a throwaway vault, the app dutifully persisted it, the
    /// throwaway was deleted a moment later, and after enough runs nothing in the list
    /// still existed - so the app opened no vault at all.
    ///
    /// The tests cannot undo that from their side. The XCUITest runner is sandboxed,
    /// so the `UserDefaults(suiteName: "it.stefer.pergamenum")` it opens is a private
    /// copy inside its own container, and the snapshot-and-restore both suites used to
    /// perform was writing to a file the app never reads.
    private let isOverridden: Bool

    /// A list backed by a throwaway suite, for tests.
    ///
    /// Not a convenience: with the real `UserDefaults`, running the suite left the
    /// user's own recents list full of temporary vaults and the app reopened one of
    /// them at launch. Running the tests must not change the app.
    static func volatile() -> RecentVaults {
        RecentVaults(defaults: UserDefaults(suiteName: "pergamenum.tests.\(UUID())") ?? .standard)
    }

    init(defaults: UserDefaults = .standard, isOverridden: Bool? = nil) {
        self.defaults = defaults
        // Injectable because the argument domain is process-wide: every UserDefaults
        // instance shares it, so a test that set one would be setting it for the whole
        // run, and two tests doing so in parallel would read each other's.
        self.isOverridden = isOverridden
            ?? (defaults.volatileDomain(forName: UserDefaults.argumentDomain)[Self.key] != nil)
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
        // A temporary override stays temporary: promoting it to permanent user data is
        // not something a command-line argument should be able to do.
        guard !isOverridden else { return }
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
