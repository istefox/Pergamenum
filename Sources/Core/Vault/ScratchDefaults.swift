import Foundation

/// A `UserDefaults` that keeps every value in memory and never reaches `cfprefsd`, for the
/// stores a test builds through `.volatile()` (R-01).
///
/// A throwaway suite was not enough: `UserDefaults(suiteName: "pergamenum.tests.<UUID>")` writes
/// `~/Library/Preferences/pergamenum.tests.<UUID>.plist` on its first `set`, and
/// `removePersistentDomain(forName:)` empties the domain but leaves the file (measured on macOS
/// 27, 2026-10-31). Every unit run left one per controller that opened a vault, 1.1 million of
/// them by 2026-10-30. Here nothing is written anywhere: the convenience getters
/// (`stringArray`, `data`, `bool`, ...) all read through `object(forKey:)`, and the setters
/// through `set(_:forKey:)`, so overriding the three primitives keeps every value in this
/// instance and the suite name only isolates whatever falls through to Foundation.
///
/// Under `Sources/Core` although only tests build one: `RecentVaults.volatile()` and
/// `PinnedTagsStore.volatile()` name it, and those two files are in `sharedSources`
/// (`Project.swift`), so `perg` and `pergamenum-mcp` compile them and need the type beside them.
/// Moving it into the test target would break both tool builds; nothing in either tool calls it.
final class ScratchDefaults: UserDefaults, @unchecked Sendable {
    /// Guarded by `lock`: `UserDefaults` is documented thread-safe, and a test may read one from
    /// a detached task.
    private var values: [String: Any] = [:]
    private let lock = NSLock()

    /// A store of its own, under a suite name no other instance shares.
    static func make() -> UserDefaults {
        ScratchDefaults(suiteName: "pergamenum.tests.\(UUID().uuidString)") ?? ScratchDefaults()
    }

    override func object(forKey defaultName: String) -> Any? {
        lock.withLock { values[defaultName] }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock { values[defaultName] = value }
    }

    override func removeObject(forKey defaultName: String) {
        lock.withLock { values[defaultName] = nil }
    }

    /// Clears this store and touches no domain on disk: a test that tidies up after itself with
    /// the usual call must not be what creates the file.
    override func removePersistentDomain(forName domainName: String) {
        lock.withLock { values.removeAll() }
    }
}
