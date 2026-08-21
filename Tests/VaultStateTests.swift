import Foundation
import Testing
@testable import Pergamenum

/// `VaultState` itself and the identity `VaultSession.init` resolves it from
/// (ADR-0017 §D2). `VaultStateMigrationTests` covers what `migrateIfNeeded` does to
/// the vault; this file covers the resolver and the id.
///
/// None of these tests call `VaultState.applicationSupportBase()`: that function
/// resolves the *real* `~/Library/Application Support/it.stefer.pergamenum/`, and
/// `.claude/test-cmd` runs this suite at the end of every turn - the same reasoning
/// that keeps `RecentVaults.volatile()` off the real `UserDefaults` domain. Every
/// test here builds a `VaultState` (or a `VaultSession`) against `TemporaryVault`'s
/// `stateBase` instead, which is exactly the seam ADR-0017 adds for this reason.
/// `applicationSupportBase()`'s own directory-creation and `isExcludedFromBackup`
/// behaviour is verified by hand against a real vault, per the ADR's own
/// verification section.
@Test func initLaysOutTheFourStoresAndTheDescriptorUnderTheGivenBase() throws {
    let base = URL(filePath: "/tmp/pergamenum-base", directoryHint: .isDirectory)
    let state = VaultState(id: "abc-123", base: base)

    #expect(state.directory == base.appending(path: "abc-123", directoryHint: .isDirectory))
    #expect(state.cacheFile == state.directory.appending(path: "cache.db"))
    #expect(state.thumbnails == state.directory.appending(path: "thumbnails", directoryHint: .isDirectory))
    #expect(state.history == state.directory.appending(path: "history", directoryHint: .isDirectory))
    #expect(state.journal == state.directory.appending(path: "ai-journal", directoryHint: .isDirectory))
    #expect(state.descriptor == state.directory.appending(path: "vault.json"))
}

@Test func resolveReturnsNilForAVaultThatHasNeverBeenOpened() throws {
    let vault = try TemporaryVault()
    #expect(VaultState.resolve(root: vault.root, base: vault.stateBase) == nil)
    // Never writes: a vault nobody has opened must not gain a `.pergamenum/` just
    // because something asked whether it had an id.
    #expect(!FileManager.default.fileExists(
        atPath: vault.root.appending(path: ".pergamenum").path(percentEncoded: false)
    ))
}

@MainActor
@Test func resolveFindsTheIDOfAVaultAlreadyOpened() throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    let id = try #require(session.settings.vaultID)

    let resolved = try #require(VaultState.resolve(root: vault.root, base: vault.stateBase))
    #expect(resolved.directory == VaultState(id: id, base: vault.stateBase).directory)
}

@MainActor
@Test func theVaultIDIsMintedOnceAndReusedOnASecondOpen() throws {
    let vault = try TemporaryVault()
    let first = VaultSession(root: vault.root, stateBase: vault.stateBase)
    let secondID = try #require(first.settings.vaultID)

    let second = VaultSession(root: vault.root, stateBase: vault.stateBase)
    #expect(second.settings.vaultID == secondID)
    #expect(second.state.directory == first.state.directory)
}

@MainActor
@Test func aReadOnlyVaultFallsBackToADeterministicIDStableAcrossTwoOpens() throws {
    let vault = try TemporaryVault()
    let privateDirectory = vault.root.appending(path: ".pergamenum", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: privateDirectory, withIntermediateDirectories: true)
    // Read and traverse, no write: `settings.json` cannot be created here, which is
    // the condition `resolveIdentity`'s fallback exists for.
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o555], ofItemAtPath: privateDirectory.path(percentEncoded: false)
    )
    defer {
        // Restored before `TemporaryVault.deinit` tries to remove the tree - a 555
        // directory refuses the deletion of anything written into it.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: privateDirectory.path(percentEncoded: false)
        )
    }

    let first = VaultSession(root: vault.root, stateBase: vault.stateBase)
    let second = VaultSession(root: vault.root, stateBase: vault.stateBase)

    #expect(first.state.directory == second.state.directory)
    // Each open reports the write failure once - not zero (silently keeping a fresh
    // in-memory id would be the loss this fallback exists to prevent) and not more
    // than once (a `bundledVocabulary`-less session also reports its own unrelated
    // "nessun vocabolario" problem, which this filters out).
    let idProblem = "impossibile scrivere l'identificativo del vault"
    #expect(first.problems.filter { $0.contains(idProblem) }.count == 1)
    #expect(second.problems.filter { $0.contains(idProblem) }.count == 1)
}
