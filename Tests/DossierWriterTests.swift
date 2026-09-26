import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 §D22.4 (PG-117), plan
// docs/superpowers/plans/2026-09-10-pratiche-pg105-pg108.md, Task 4.
//
// This test is written against the contract - call `update`, then read the file back.

private let praticaNoteWithForeignKey = """
---
pergamenum-dossier: 1
obsidian-icon: 📁
pergamenum-dossier-excluded:
  - "<already-excluded@rossi-spa.it>"
---

Corpo della pratica, non toccato.
"""

@MainActor
@Test func dossierWriterUpdatePreservesAForeignKeyItDoesNotOwnByteForByte() async throws {
    let vault = try TemporaryVault()
    try vault.write(praticaNoteWithForeignKey, to: "Rossi/pratica.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)

    let failure = await DossierWriter.update(at: "Rossi", session: session) { dossier in
        dossier.excluded.append("<new@rossi-spa.it>")
    }
    #expect(failure == nil)

    let (_, text) = try session.read("Rossi/pratica.md")
    // §D12/C4: a key this app does not own survives untouched, in its original
    // position - this is `Dossier.merging`'s own already-tested guarantee, exercised
    // here through the higher-level read-modify-write `DossierWriter` wraps.
    #expect(text.contains("obsidian-icon: 📁"))
    // The actual change asked for.
    #expect(text.contains("<new@rossi-spa.it>"))
    #expect(text.contains("<already-excluded@rossi-spa.it>"))
}
