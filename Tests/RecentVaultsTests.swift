import Foundation
import Testing
@testable import Pergamenum

// MARK: - Recent vaults

/// A throwaway suite, so these two never touch the real preferences.
private func makeDefaults() -> (UserDefaults, String) {
    let name = "pergamenum.tests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
}

/// A directory to stand in for a vault. It only has to exist: `remember` stores a
/// path, and these tests read the stored value back rather than opening anything.
private func makeVaultDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-recents-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// `-recentVaults` outranks anything written underneath it, so the app spent the whole
/// session reading the override while quietly overwriting the user's real list with
/// vaults the tests deleted a moment later.
@Test func aVaultListHandedInOnTheCommandLineIsNeverPersisted() throws {
    let vault = try makeVaultDirectory()
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }

    RecentVaults(defaults: defaults, isOverridden: true).remember(vault)

    // Nothing was written underneath the override, so the next ordinary launch finds
    // the list exactly as the user left it.
    #expect(defaults.stringArray(forKey: RecentVaults.key) == nil)
}

@Test func aVaultOpenedNormallyIsStillRemembered() throws {
    // The positive control: the guard above must not turn `remember` into a no-op for
    // the ordinary case, which is the whole feature.
    let vault = try makeVaultDirectory()
    let (defaults, name) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: name) }

    RecentVaults(defaults: defaults, isOverridden: false).remember(vault)

    let expected = vault.resolvingSymlinksInPath().standardizedFileURL
        .path(percentEncoded: false)
    #expect(defaults.stringArray(forKey: RecentVaults.key) == [expected])
}
