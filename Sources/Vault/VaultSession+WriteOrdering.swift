import Foundation

// ADR-0041 (vault layer consistency and security), plan
// docs/superpowers/plans/2026-09-12-vault-layer-consistency-and-security-cha.md, Task 8 -
// R-07: ordering is a per-path sequence number the actor stamps, not an assumption about
// continuation scheduling (§D11).
//
// ADR-0043 §D1 moved the real, guarded index door to `apply(_ mutations:)`
// (`VaultSession.swift`, the file `index`'s setter is `private` to). What is left here is
// the outcome-shaped convenience `apply(_:at:)` ADR-0041 §D11 introduced, kept only because
// `Tests/VaultWriteOrderingTests.swift`'s batch-1 `theOlderOutcomeIsDroppedWhenSequencesArriveInverted`
// (test-authoring scope forbids touching it in this task) still calls it directly to force
// an inversion without a real actor write.
//
// **Still in `sharedSources` (ADR-0007 §D2), alongside `VaultDisk.swift`.** This file
// keeps real code for that reason: an empty file left in `sharedSources` for a chain of
// tasks would be a stranger thing to explain than the one convenience below.
extension VaultSession {
    /// Back-compat wrapper over `apply(_ mutations:)`: applies one outcome's mutation and
    /// answers whether it was newer than what this path already had.
    @discardableResult
    func apply(_ outcome: VaultDisk.DiskWriteOutcome, at relativePath: String) -> Bool {
        apply([outcome.mutation]) == 1
    }
}
