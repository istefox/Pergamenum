import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 1 - R-19.
//
// Where the Mail store is read from. §D7 of the ADR: this mirrors
// `VaultState.processDefaultBase()` (`Sources/Vault/VaultState.swift`) exactly, on
// purpose - the same mechanism that keeps the unit and UI suites off the real vault
// state directory keeps them off `~/Library/Mail` too, even on a host whose terminal
// already has Full Disk Access (this Mac's does).
enum MailStoreLocation {
    /// The key `-mailStoreRoot <path>` is read under, matching `VaultState`'s own
    /// `-stateBase` and `RecentVaults`' `-recentVaults` launch-argument convention.
    static let overrideKey = "mailStoreRoot"

    /// Resolves, in order: the `-mailStoreRoot` launch argument (R-19), a per-process
    /// temporary fixture root under xctest, and only then `~/Library/Mail/V10`.
    static func resolve() -> URL {
        // `XCTestConfigurationFilePath` is set for the *host* XCTest process and not
        // for the app a UI test launches, so the launch argument is the only thing
        // that reaches the app itself.
        if let override = overridePath() {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        if VaultState.isRunningUnderTest {
            // Never `~/Library/Mail`: a unit test that reached the real store would
            // be a test about somebody's correspondence, the rule `-disableCalendar`
            // already exists for.
            try? FileManager.default.createDirectory(at: testProcessRoot, withIntermediateDirectories: true)
            return testProcessRoot
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mail/V10", directoryHint: .isDirectory)
    }

    /// The `-mailStoreRoot` launch argument, read from the argument domain alone (PG-250).
    /// `string(forKey:)` would fall through to the app's persistent domain, which every
    /// process with the bundle id shares: a stray `defaults write`, or another test run
    /// writing there, would redirect this process's Mail read. R-19 names a launch
    /// argument and nothing else, so nothing else is read.
    static func overridePath(in defaults: UserDefaults = .standard) -> String? {
        defaults.volatileDomain(forName: UserDefaults.argumentDomain)[overrideKey] as? String
    }

    /// One directory per test process, not per call - `VaultState.testProcessBase`'s
    /// own reason: a second `resolve()` handing back a fresh temporary directory
    /// would lose whatever the first one's fixture wrote there.
    private static let testProcessRoot: URL = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-test-mailstore-\(UUID().uuidString)", directoryHint: .isDirectory)
}
