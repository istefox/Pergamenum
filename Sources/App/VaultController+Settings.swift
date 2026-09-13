import Foundation

/// The vault's settings and the two maintenance operations beside them (SPEC §12).
///
/// Split out of `VaultController.swift` when the split view took that file past SwiftLint's
/// 400 lines. Nothing here touches the tabs, which is why this is the part that left.
extension VaultController {
    // Settings, vocabulary and the cache all live on the session now (ADR-0007 §D3).
    // What stays here is the door the menus and the settings window already knock on.

    /// Applies a settings change and writes `settings.json` back.
    func updateSettings(_ change: (inout VaultSettings) -> Void) {
        session?.updateSettings(change)
    }

    /// Re-imports the closed vocabularies from the harness-system checkout and writes
    /// the replica back into the vault.
    func importConventions(from repository: URL) {
        session?.importConventions(from: repository)
    }
}
