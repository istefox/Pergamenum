import Foundation

/// Under `Sources/Vault`, not `Sources/Core`, because it reaches `NoteStore` (ADR-0046 §D1) - and
/// therefore named by hand in `Project.swift`'s `sharedSources`, beside `NoteStore+ReadSurface.swift`,
/// so `perg` and `pergamenum-mcp` see it too.
extension VaultFileChange {
    /// The hash `after` was derived from, in the same expression `VaultDisk.write`'s own
    /// `hashBefore` uses (`VaultDisk.swift:208-209`): `store.text` → `Data(text.utf8)` →
    /// `NoteStore.hash`. Kept as one expression rather than spelled at every `expecting:` call
    /// site, so the two sides of the comparison cannot drift apart. Since ADR-0064 §D4.2
    /// `NoteStore.hash` skips one leading BOM, so this text hash (the decoded text never carries
    /// one) equals the hash of a BOM file's raw bytes, and a BOM note is not refused by its own
    /// precondition.
    var expectedHash: String { NoteStore.hash(Data(before.utf8)) }
}
