import Foundation

// ADR-0041 (vault layer consistency and security), plan
// docs/superpowers/plans/2026-09-12-vault-layer-consistency-and-security-cha.md, Task 8 -
// R-07: ordering is a per-path sequence number the actor stamps, not an assumption about
// continuation scheduling (§D11).
//
// **Deliberately not in `sharedSources` (ADR-0007 §D2/§D3), unlike `VaultSession.swift`
// itself.** `apply(_:at:)` below is test-only scaffolding - nothing in `Sources/CLI` or
// `Sources/MCPServer` calls it, and it is the one place in this tester dispatch that has to
// reference `VaultDisk.DiskWriteOutcome`. Keeping it in its own file, off the shared-source
// list, means `perg` and `pergamenum-mcp` keep building without also needing
// `Sources/Vault/VaultDisk.swift` added to `sharedSources` - that addition is the coder's
// own mechanical step 5, done once real production code (not just a test seam) needs the
// actor from those two targets.
extension VaultSession {
    /// Test-only seam (ADR-0041 §D11, Task 8): applies a `VaultDisk.DiskWriteOutcome` to
    /// the index the same way the coder's real `write(_:to:)` will, once it exists.
    /// `VaultWriteOrderingTests` uses this to force two outcomes to arrive in the wrong
    /// order deterministically - awaiting two real writes only ever observes them in
    /// program order, never inverted, so the inversion itself has to be manufactured
    /// through a seam rather than through timing.
    ///
    /// **STUB (ADR-0041 Task 8).** This body has no guard at all: it always records
    /// `outcome.sequence` into `appliedSequence` and always applies `outcome.record` to
    /// the index, and always returns `true`. That is deliberately wrong once a second,
    /// older-sequenced outcome is applied after a newer one - which is exactly what keeps
    /// `VaultWriteOrderingTests`' inversion test red. The coder's job is to make this
    /// consult `appliedSequence[relativePath]` first and drop (return `false`, applying
    /// nothing) an outcome whose sequence is not strictly greater than what is already
    /// recorded there.
    @discardableResult
    func apply(_ outcome: VaultDisk.DiskWriteOutcome, at relativePath: String) -> Bool {
        appliedSequence[relativePath] = outcome.sequence
        updateIndex(outcome.record, at: relativePath)
        return true
    }
}
