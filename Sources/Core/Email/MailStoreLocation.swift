import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 1 - R-19.
//
// Where the Mail store is read from. §D7 of the ADR: this mirrors
// `VaultState.processDefaultBase()` (`Sources/Vault/VaultState.swift`) exactly, on
// purpose - the same mechanism that keeps the unit and UI suites off the real vault
// state directory keeps them off `~/Library/Mail` too, even on a host whose terminal
// already has Full Disk Access (this Mac's does).
//
// Tester-declared boundary (ADR-0155): the fallback order below is fixed by the ADR,
// but the body is an intentionally wrong stub - a fixed path that is neither the real
// Mail store nor a temporary directory - so every test in
// `Tests/MailStoreReaderTests.swift` that exercises this stays red until the coder
// wires it up for real.
enum MailStoreLocation {
    /// The key `-mailStoreRoot <path>` is read under, matching `VaultState`'s own
    /// `-stateBase` and `RecentVaults`' `-recentVaults` launch-argument convention.
    static let overrideKey = "mailStoreRoot"

    /// Resolves, in order: the `-mailStoreRoot` launch argument (R-19), a per-process
    /// temporary fixture root under xctest, and only then `~/Library/Mail/V10`.
    ///
    /// Stub: always the same placeholder, ignoring both the override and
    /// `VaultState.isRunningUnderTest` - coder fills this in per ADR-0036 §D7.
    static func resolve() -> URL {
        URL(filePath: "/private/var/pergamenum-mailstore-location-unimplemented", directoryHint: .isDirectory)
    }
}
