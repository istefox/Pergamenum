import Foundation

/// Where a vault's derived, per-machine state lives, beside the vault rather than
/// inside it (ADR-0017).
///
/// Foundation only, on purpose: this file is named explicitly in `sharedSources`
/// (`Project.swift`), so `perg` and `pergamenum-mcp` compile it too, and an `import
/// AppKit` or `import SwiftUI` here breaks both connector builds, naming the compiler
/// rather than the cause (CLAUDE.md). The same is true of `VaultState+Migration.swift`
/// and `VaultState+DirectoryMove.swift`, which carry `migrateIfNeeded` and its helpers
/// - split out purely to stay under SwiftLint's file and type length limits, not
/// because the migration is a different concern from the resolver.
struct VaultState: Sendable {
    static let vaultsDirectoryName = "vaults"
    static let cacheFileName = "cache.db"
    static let thumbnailsDirectoryName = "thumbnails"
    /// The names of what is beside the vault, named here rather than as bare literals
    /// inside `NoteHistory` and `WriteJournal` themselves.
    static let historyDirectoryName = "history"
    static let journalDirectoryName = "ai-journal"
    static let descriptorFileName = "vault.json"

    /// The names `vault.json`'s `migrated` array uses for each derived store, one
    /// entry per store, appended only once that store's migration step has succeeded
    /// or had nothing to do.
    static let cacheStoreName = "cache"
    static let thumbnailsStoreName = "thumbnails"
    static let historyStoreName = "history"
    static let journalStoreName = "ai-journal"

    /// `<base>/<vaultID>`.
    let directory: URL
    var cacheFile: URL
    var thumbnails: URL
    var history: URL
    var journal: URL
    var descriptor: URL

    init(id: String, base: URL) {
        directory = base.appending(path: id, directoryHint: .isDirectory)
        cacheFile = directory.appending(path: Self.cacheFileName, directoryHint: .notDirectory)
        thumbnails = directory.appending(path: Self.thumbnailsDirectoryName, directoryHint: .isDirectory)
        history = directory.appending(path: Self.historyDirectoryName, directoryHint: .isDirectory)
        journal = directory.appending(path: Self.journalDirectoryName, directoryHint: .isDirectory)
        descriptor = directory.appending(path: Self.descriptorFileName, directoryHint: .notDirectory)
    }

    /// True when this process is `xcodebuild test` - set by the test runner for the
    /// host app process, which is where the unit suite runs.
    static var isRunningUnderTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// `~/Library/Application Support/it.stefer.pergamenum/vaults`, asked for through
    /// `FileManager` rather than joined onto `NSHomeDirectory()` (ADR-0017 D2), so a
    /// future sandbox returns the container and everything keeps working.
    ///
    /// `isExcludedFromBackup` is set once here, the moment `…/it.stefer.pergamenum/`
    /// itself is created, and on nothing inside the vault: the four stores that stay
    /// there are exactly the four a person would want back from a backup (ADR-0017 D4).
    ///
    /// A `precondition` rather than a quiet guard: `.claude/test-cmd` runs the unit
    /// suite at the end of every turn, and this call must never resolve the real
    /// directory from inside it, loudly or not at all - the same failure
    /// `RecentVaults.volatile()` exists to prevent, now with files. `VaultController`
    /// does not call this directly under test; see `processDefaultBase()`.
    static func applicationSupportBase() throws -> URL {
        precondition(
            !isRunningUnderTest,
            "ADR-0017: resolving the real Application Support directory from a test run"
        )
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let root = support.appending(path: AppInfo.bundleIdentifier, directoryHint: .isDirectory)

        if !FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var excluded = root
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? excluded.setResourceValues(values)
        }
        return root.appending(path: vaultsDirectoryName, directoryHint: .isDirectory)
    }

    /// The base `VaultController` resolves when nobody hands it one: the real
    /// Application Support outside a test run, and an isolated per-process temporary
    /// directory inside one.
    ///
    /// `VaultController` has no injectable `stateBase` of its own - none of the
    /// fourteen test files that build one and call `open(_:)` need a directory tied to
    /// a particular `TemporaryVault`, only one that is never the real Application
    /// Support. Before this existed, every one of them resolved the real directory:
    /// `~/Library/Application Support/it.stefer.pergamenum/` accumulated 860 stray
    /// vault directories from a single afternoon of `.claude/test-cmd` runs.
    static func processDefaultBase() throws -> URL {
        // `-stateBase <path>`, the UI suite's door: `XCTestConfigurationFilePath` is
        // set for the *host* XCTest process, not for the app it launches, so a UI test
        // driving the real app was resolving the real Application Support the same
        // way the unit-test hole did - 70 stray directories, one per UI test, found by
        // hand after the fix above. Read from the argument domain exactly the way
        // `RecentVaults`' `-recentVaults` override is (`RecentVaults.swift`).
        if let override = UserDefaults.standard.string(forKey: "stateBase") {
            let url = URL(filePath: override, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        if isRunningUnderTest {
            try FileManager.default.createDirectory(at: testProcessBase, withIntermediateDirectories: true)
            return testProcessBase
        }
        return try applicationSupportBase()
    }

    /// One directory per test process, not per call: state directories are already
    /// keyed by vault id underneath it, and re-resolving a fresh temporary directory
    /// on every `open(_:)` would leave a session unable to find state a previous
    /// `open` in the same test already wrote.
    private static let testProcessBase: URL = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-test-state-\(UUID().uuidString)", directoryHint: .isDirectory)

    /// Reads `settings.json` for the id without minting one and without opening a
    /// session. Nil for a vault that has never been opened, or one whose settings
    /// carry no id yet.
    static func resolve(root: URL, base: URL) -> VaultState? {
        let settingsURL = root
            .appending(path: VaultLayout.privateDirectory, directoryHint: .isDirectory)
            .appending(path: VaultLayout.settingsFile, directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(VaultSettings.self, from: data),
              let id = settings.vaultID
        else { return nil }
        return VaultState(id: id, base: base)
    }
}
