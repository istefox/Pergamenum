import Foundation

// ADR-0041 (vault layer consistency and security), plan
// docs/superpowers/plans/2026-09-12-vault-layer-consistency-and-security-cha.md, Task 8 -
// R-07: ordering is a per-path sequence number the actor stamps, not an assumption about
// continuation scheduling (§D11).
//
// **In `sharedSources` (ADR-0007 §D2), alongside `VaultDisk.swift`.** `apply(_:at:)`
// below is called from `VaultSession.write`'s real async implementation
// (`VaultSession.swift`, itself already shared) - not only from tests - so `perg` and
// `pergamenum-mcp` fail to link without this file too, the same failure CLAUDE.md's "a
// file outside those globs that a tool needs must be added by hand" predicts.
extension VaultSession {
    /// Applies a `VaultDisk.DiskWriteOutcome` to the index, guarded by §D11's per-path
    /// sequence: an outcome whose sequence is not strictly greater than the one already
    /// applied for that path is dropped - nothing is written to the index and `false` is
    /// returned - rather than letting an out-of-order continuation move the index
    /// backwards. `VaultWriteOrderingTests` also calls this directly to force an inversion
    /// deterministically, independent of any real write.
    @discardableResult
    func apply(_ outcome: VaultDisk.DiskWriteOutcome, at relativePath: String) -> Bool {
        guard outcome.sequence > appliedSequence[relativePath, default: 0] else { return false }
        appliedSequence[relativePath] = outcome.sequence
        updateIndex(outcome.record, at: relativePath)
        return true
    }
}
