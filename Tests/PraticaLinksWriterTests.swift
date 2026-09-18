import Foundation
import Testing
@testable import Pergamenum

// ADR-0049 (Pratiche links to notes, tasks and boards), plan
// docs/plans/pratiche-note-task-workspace-links.md, Task 2 - R-01, R-02, R-07, §D6, §D11.

private let praticaNoteWithDossier = """
---
pergamenum-dossier: 1
pergamenum-dossier-counterparts:
  - m.rossi@rossi-spa.it
obsidian-icon: 📁
---

Corpo della pratica, non toccato.
"""

private let praticaNoteWithDossierAndLinks = """
---
pergamenum-dossier: 1
pergamenum-dossier-counterparts:
  - m.rossi@rossi-spa.it
pergamenum-dossier-links-notes:
  - "[[Offerta 2026]]"
---

Corpo della pratica, non toccato.
"""

@MainActor
@Suite struct PraticaLinksWriterTests {
    // MARK: - §D1: the two codecs preserve each other, with no coordination between them

    @Test func linkingANoteLeavesEveryDossierKeyByteIdentical() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaNoteWithDossier, to: "Rossi/pratica.md")
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)

        let failure = await PraticaLinksWriter.update(at: "Rossi", session: session) { links in
            links.notes.append("Offerta 2026")
        }
        #expect(failure == nil)

        let (_, text) = try session.read("Rossi/pratica.md")
        #expect(text.contains("pergamenum-dossier-counterparts:"))
        #expect(text.contains("m.rossi@rossi-spa.it"))
        #expect(text.contains("obsidian-icon: 📁"))
        #expect(text.contains("pergamenum-dossier-links-notes:"))
        #expect(text.contains("\"[[Offerta 2026]]\""))
    }

    @Test func writingADossierKeyLeavesLinksKeysByteIdentical() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaNoteWithDossierAndLinks, to: "Rossi/pratica.md")
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)

        let failure = await DossierWriter.update(at: "Rossi", session: session) { dossier in
            dossier.counterparts.append("acquisti@rossi-spa.it")
        }
        #expect(failure == nil)

        let (_, text) = try session.read("Rossi/pratica.md")
        #expect(text.contains("pergamenum-dossier-links-notes:"))
        #expect(text.contains("\"[[Offerta 2026]]\""))
        #expect(text.contains("acquisti@rossi-spa.it"))
    }

    @Test func unlinkingRemovesTheKeyRatherThanWritingAnEmptyValue() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaNoteWithDossierAndLinks, to: "Rossi/pratica.md")
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)

        let failure = await PraticaLinksWriter.update(at: "Rossi", session: session) { links in
            links.notes.removeAll()
        }
        #expect(failure == nil)

        let (_, text) = try session.read("Rossi/pratica.md")
        #expect(!text.contains("pergamenum-dossier-links-notes"))
    }

    @Test func writingNothingDifferentWritesNoBytes() async throws {
        let vault = try TemporaryVault()
        let url = try vault.write(praticaNoteWithDossierAndLinks, to: "Rossi/pratica.md")
        let before = try Data(contentsOf: url)
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)

        let failure = await PraticaLinksWriter.update(at: "Rossi", session: session) { _ in }
        #expect(failure == nil)
        #expect(try Data(contentsOf: url) == before)
    }

    // MARK: - §D11: a stale `expecting:` hash refuses rather than silently dropping the loser

    @Test func aStaleExpectingHashRefusesAndWritesNothing() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaNoteWithDossier, to: "Rossi/pratica.md")
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)

        let failure = await PraticaLinksWriter.update(at: "Rossi", session: session) { links in
            // Simulates a concurrent write (a running sync's own dossier write, say)
            // landing between `update`'s internal read and the write it is about to
            // make: the hash it captured a moment ago is now stale.
            try? vault.write(praticaNoteWithDossier + "\n", to: "Rossi/pratica.md")
            links.notes.append("Offerta 2026")
        }
        #expect(failure != nil)
        #expect(failure?.contains("non è stato aggiornato") == true)

        let (_, text) = try session.read("Rossi/pratica.md")
        #expect(!text.contains("pergamenum-dossier-links-notes"))
    }
}

// MARK: - R-02, §D6: the per-message write door

private let messageWithNoLink = """
---
date: 2026-06-10
tags:
  - type-note
  - type-email
pergamenum-mail: 1
pergamenum-mail-message-id: "<abc@rossi-spa.it>"
pergamenum-mail-direction: received
pergamenum-mail-date: 2026-06-10T14:06:00+02:00
pergamenum-mail-from: "Mario Rossi <m.rossi@rossi-spa.it>"
pergamenum-mail-subject: "Richiesta offerta"
pergamenum-mail-body: complete
---

Buongiorno,
"""

@MainActor
@Suite struct PraticaCommandActionsLinkNoteTests {
    @Test func linkingANoteWritesTheKeyAndLeavesEveryOtherByteIdentical() async throws {
        let vault = try TemporaryVault()
        try vault.write(messageWithNoLink, to: "Rossi/email/msg.md")
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let actions = PraticaCommandActions(pratiche: pratiche, vault: vaultController, navigation: Navigation())

        await actions.linkNote("[[Offerta 2026]]", toMessageAt: "Rossi/email/msg.md")

        let text = try String(contentsOf: vault.root.appending(path: "Rossi/email/msg.md"), encoding: .utf8)
        #expect(text.contains("pergamenum-mail-note: \"[[Offerta 2026]]\""))
        #expect(text.contains("pergamenum-mail-subject: \"Richiesta offerta\""))
        #expect(text.contains("Buongiorno,"))

        vaultController.close()
    }

    @Test func unlinkingRemovesTheKey() async throws {
        let linked = messageWithNoLink.replacingOccurrences(
            of: "pergamenum-mail-body: complete",
            with: "pergamenum-mail-note: \"[[Offerta 2026]]\"\npergamenum-mail-body: complete"
        )
        let vault = try TemporaryVault()
        try vault.write(linked, to: "Rossi/email/msg.md")
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let actions = PraticaCommandActions(pratiche: pratiche, vault: vaultController, navigation: Navigation())

        await actions.linkNote(nil, toMessageAt: "Rossi/email/msg.md")

        let text = try String(contentsOf: vault.root.appending(path: "Rossi/email/msg.md"), encoding: .utf8)
        #expect(!text.contains("pergamenum-mail-note"))

        vaultController.close()
    }
}
