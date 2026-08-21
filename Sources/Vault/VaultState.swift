import Foundation

/// Where a vault's derived, per-machine state lives, beside the vault rather than
/// inside it (ADR-0017).
///
/// Foundation only, on purpose: this file is named explicitly in `sharedSources`
/// (`Project.swift`), so `perg` and `pergamenum-mcp` compile it too, and an `import
/// AppKit` or `import SwiftUI` here breaks both connector builds, naming the compiler
/// rather than the cause (CLAUDE.md).
struct VaultState: Sendable {
    static let vaultsDirectoryName = "vaults"
    static let cacheFileName = "cache.db"
    static let thumbnailsDirectoryName = "thumbnails"
    /// Not read from this slice - `history/` stays at its vault-relative location
    /// until slice 2 moves it (ADR-0017 D3) - but named here already so the names of
    /// what is beside the vault live in one place rather than as bare literals inside
    /// their own stores.
    static let historyDirectoryName = "history"
    static let journalDirectoryName = "ai-journal"
    static let descriptorFileName = "vault.json"

    /// The names `vault.json`'s `migrated` array uses for each derived store, one
    /// entry per store, appended only once that store's migration step has succeeded
    /// or had nothing to do. `"history"` and `"ai-journal"` join this in slice 2.
    static let cacheStoreName = "cache"
    static let thumbnailsStoreName = "thumbnails"

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

    // MARK: Migration

    /// What `vault.json` records: the root this state directory was last opened
    /// against, and which derived stores have already been moved out of the vault.
    ///
    /// Decoded key by key like `VaultSettings`, for the same reason: this file grows
    /// in slice 2 (`"history"` and `"ai-journal"` join `migrated`), and a decoder that
    /// rejected an older `vault.json` wholesale would make one unrecognised key cost
    /// the whole record instead of nothing.
    struct Descriptor: Codable, Equatable, Sendable {
        /// The vault root last opened against this state directory, as a path.
        /// Unread this slice - the duplicated-vault report it exists for is slice 2 -
        /// but recorded now so the file does not need a schema migration of its own
        /// when that lands.
        var root: String?
        /// One name per store already migrated out of the vault: `"cache"`,
        /// `"thumbnails"`, and later `"history"`, `"ai-journal"`. A store's migration
        /// step runs whenever its name is absent here, appended only on success - which
        /// is what lets a vault this slice already touched pick up slice 2's move on
        /// its next open instead of being skipped forever, and lets a failed step
        /// retry rather than being silently abandoned.
        var migrated: [String]

        static let empty = Descriptor(root: nil, migrated: [])

        init(root: String?, migrated: [String]) {
            self.root = root
            self.migrated = migrated
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            root = try container.decodeIfPresent(String.self, forKey: .root)
            migrated = try container.decodeIfPresent([String].self, forKey: .migrated) ?? []
        }
    }

    /// Ensures this vault's state directory exists and runs each derived store's
    /// migration step exactly once, tracked in `vault.json`'s `migrated` array rather
    /// than by whether the directory itself is new.
    ///
    /// Keying on the directory's own existence would be consumed the moment this
    /// slice ships: by the time slice 2 runs, the directory this slice created is
    /// already there, so `history/` and `ai-journal/` would never be picked up on any
    /// vault opened before that point - silently, forever, which is exactly the loss
    /// ADR-0017 D3's move-not-delete rule exists to prevent. Tracking per store
    /// instead means a vault this slice has already touched still runs slice 2's step
    /// the first time it sees it.
    ///
    /// This slice only ever writes `"cache"` and `"thumbnails"` to `migrated`, both by
    /// deletion: neither store is anything but a rebuildable cache, so removing the
    /// old copy loses nothing (ADR-0017 D3).
    func migrateIfNeeded(from privateDirectory: URL, root: URL) -> [String] {
        var problems: [String] = []
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            problems.append("\(directory.lastPathComponent): \(error.localizedDescription)")
            return problems
        }

        var record = Self.readDescriptor(at: descriptor) ?? .empty
        var done = Set(record.migrated)

        if !done.contains(Self.cacheStoreName) {
            problems.append(contentsOf: Self.removeDerivedFile(
                named: Self.cacheFileName, sidecars: ["-journal", "-wal", "-shm"], in: privateDirectory
            ))
            done.insert(Self.cacheStoreName)
        }
        if !done.contains(Self.thumbnailsStoreName) {
            problems.append(contentsOf: Self.removeDerivedDirectory(
                named: Self.thumbnailsDirectoryName, in: privateDirectory
            ))
            done.insert(Self.thumbnailsStoreName)
        }

        record.migrated = done.sorted()
        record.root = root.path(percentEncoded: false)
        Self.writeDescriptor(record, to: descriptor, reporting: &problems)

        return problems
    }

    private static func removeDerivedFile(
        named name: String, sidecars: [String], in privateDirectory: URL
    ) -> [String] {
        var problems: [String] = []
        removeIfPresent(privateDirectory.appending(path: name, directoryHint: .notDirectory), reporting: &problems)
        for suffix in sidecars {
            removeIfPresent(
                privateDirectory.appending(path: name + suffix, directoryHint: .notDirectory),
                reporting: &problems
            )
        }
        problems.append(contentsOf: conflictCopies(of: name, in: privateDirectory))
        return problems
    }

    private static func removeDerivedDirectory(named name: String, in privateDirectory: URL) -> [String] {
        var problems: [String] = []
        removeIfPresent(privateDirectory.appending(path: name, directoryHint: .isDirectory), reporting: &problems)
        problems.append(contentsOf: conflictCopies(of: name, in: privateDirectory))
        return problems
    }

    private static func removeIfPresent(_ url: URL, reporting problems: inout [String]) {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            problems.append("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Names in `privateDirectory` that look like an iCloud conflict copy of
    /// `baseName` - `"cache 2.db"` beside `"cache.db"`, `"thumbnails 2"` beside
    /// `"thumbnails"`. Named rather than deleted: an upgrade that removes a file it
    /// did not itself write is not a thing this app does (ADR-0017 D3).
    private static func conflictCopies(of baseName: String, in directory: URL) -> [String] {
        let stem = (baseName as NSString).deletingPathExtension
        let ext = (baseName as NSString).pathExtension
        guard let entries = try? FileManager.default.contentsOfDirectory(
            atPath: directory.path(percentEncoded: false)
        ) else { return [] }

        return entries
            .filter { entry in
                guard entry != baseName else { return false }
                let entryStem = (entry as NSString).deletingPathExtension
                return (entry as NSString).pathExtension == ext && entryStem.hasPrefix("\(stem) ")
            }
            .sorted()
            .map { "\($0): conflict copy left in \(VaultLayout.privateDirectory)/, not removed" }
    }

    private static func readDescriptor(at url: URL) -> Descriptor? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Descriptor.self, from: data)
    }

    private static func writeDescriptor(_ record: Descriptor, to url: URL, reporting problems: inout [String]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(record).write(to: url, options: .atomic)
        } catch {
            problems.append("\(Self.descriptorFileName): \(error.localizedDescription)")
        }
    }
}
