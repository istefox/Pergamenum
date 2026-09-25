import Foundation
import Testing
@testable import Pergamenum

/// PG-131 / #231: three cleanup affordances existed with zero callers - `VaultController
/// .clearCache()` never touched the thumbnail cache, `VaultSession.clearProblems()` was
/// unreachable from the facade, and `OpenTabsStore.forget(_:)` was never invoked when a vault
/// left the recents list. These pin the wiring, not the stores themselves (see
/// `ThumbnailStoreTests`/`OpenTabsStoreTests`/`RecentVaultsTests` for those).

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-09-25\ntags:\n  - type-note\n---\n\n\(body)\n"
}

@MainActor
private func controller(
    _ vault: borrowing TemporaryVault,
    recents: RecentVaults = .volatile(),
    openTabs: OpenTabsStore = .volatile()
) async throws -> VaultController {
    try vault.write(note(), to: "Nota.md")
    let controller = VaultController(recents: recents, openTabs: openTabs)
    await controller.open(vault.root)
    return controller
}

@MainActor
@Test func clearCacheAlsoDropsEveryRenderedThumbnailOnDisk() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    #expect(controller.thumbnails != nil)
    // `VaultController.open` resolves its own state base via `VaultState
    // .processDefaultBase()` (shared per test process, not `TemporaryVault.stateBase`,
    // which only `VaultSessionTests` injects directly) - reading the same call back is
    // what finds the real directory `ThumbnailStore` writes into.
    let base = try VaultState.processDefaultBase()
    let state = try #require(VaultState.resolve(root: vault.root, base: base))
    let renderedDirectory = state.thumbnails
    // Stands in for a rendered PNG - `clearCache` deletes the whole directory without
    // reading it, so a real render is not needed to prove the deletion.
    try FileManager.default.createDirectory(at: renderedDirectory, withIntermediateDirectories: true)
    try Data("fake png bytes".utf8)
        .write(to: renderedDirectory.appending(path: "abc@320.png", directoryHint: .notDirectory))

    await controller.clearCache()

    #expect(!FileManager.default.fileExists(atPath: renderedDirectory.path(percentEncoded: false)))
}

@MainActor
@Test func clearProblemsEmptiesTheListTheFacadeExposes() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.recordProblem("qualcosa non ha funzionato")
    #expect(!controller.problems.isEmpty)

    controller.clearProblems()

    #expect(controller.problems.isEmpty)
}

@MainActor
@Test func openingAVaultBeyondTheRecentsCapForgetsTheEvictedVaultsTabSession() async throws {
    let (defaults, defaultsName) = makeUserDefaults()
    defer { defaults.removePersistentDomain(forName: defaultsName) }
    let recents = RecentVaults(defaults: defaults, isOverridden: false)
    let openTabs = OpenTabsStore(defaults: defaults)

    // Plain directories, not `TemporaryVault`: nine noncopyable vaults cannot live in one
    // array, and the wiring under test only needs a path that exists, not a real session.
    var directories: [URL] = []
    for _ in 0..<(RecentVaults.maximum + 1) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-recents-cap-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directories.append(directory)
    }
    defer { for directory in directories { try? FileManager.default.removeItem(at: directory) } }

    let controller = VaultController(recents: recents, openTabs: openTabs)
    let oldest = directories[0]
    for directory in directories.dropLast() {
        await controller.open(directory)
    }
    var session = OpenTabsStore.Session()
    session.columns = [.init(entries: [.init(path: "Nota.md", isPreview: false)], activePath: "Nota.md")]
    openTabs.remember(session, for: oldest)

    await controller.open(directories.last!)

    #expect(openTabs.session(for: oldest) == OpenTabsStore.Session())
}

private func makeUserDefaults() -> (UserDefaults, String) {
    let name = "pergamenum.tests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
}
