import Foundation
import Testing
@testable import Pergamenum

// PG-368 (ADR-0063 §D9, PG-360 note): the index/ledger/selection-derived vault joins of the
// Pratiche readers go through `VaultBoundary`. A path that leaves the vault (`..`) reads as an
// empty timeline, no links, no dossier; a vault opened through a symlinked root still reads
// correctly (PG-360 precedent).
//
// `VaultBoundary` is lexical: it refuses `..` and absolute paths, and it does NOT follow a
// symlink that sits inside the vault, so an in-vault symlink to an outside folder is read
// through. So the adversarial inputs here
// are traversal paths, not symlinks; that is the boundary's decided policy, not a gap of
// this change.
//
// Not covered, because nothing observable can reach them:
// - `VaultAPI.praticaNotes` (private) and `praticaLinks`' refusal branch: their paths come
//   from the scanner's `relativePath`, which can never contain `..`, so the refusal is
//   defense in depth. Only the positive controls (listing/links under a symlinked root) run.
// - `TasksView.taskPraticaLookup()` is a SwiftUI view method needing a live `TasksView`;
//   it applies the same `VaultBoundary` + `PraticaLinks.parse` pair that `reloadTimeline`'s
//   links read is tested through here.

private let folder = "Rossi/Offerta"

private let praticaWithLinks = """
---
pergamenum-dossier: 1
pergamenum-dossier-counterparts:
  - m.rossi@rossi-spa.it
pergamenum-dossier-links-notes:
  - "[[Offerta 2026]]"
---

Appunti pratica.
"""

private func symlink(_ link: URL, to target: URL) throws {
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
}

/// A vault one level inside a container that also holds a real pratica (`Offerta`) beside it,
/// so `../Offerta` names a folder that exists, is readable and is not in the vault.
private struct NestedVault: ~Copyable {
    let container: TemporaryVault
    let outer: URL
    let vault: URL

    init() throws {
        let container = try TemporaryVault()
        let note = praticaWithLinks + "\n\n## 2026-06-10 14:06 Nota · Mario Rossi\nUna voce.\n"
        try container.write(note, to: "Offerta/pratica.md")
        let vault = container.root.appending(path: "vault", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        outer = container.root
        self.vault = vault
        self.container = container
    }
}

private func scratchLink() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-link-\(UUID().uuidString)", directoryHint: .notDirectory)
}

@MainActor
@Suite(.serialized) struct PraticaBoundaryJoinTests {
    // MARK: - VaultAPI.pratiche / pratica / praticaLinks (Sources/Connector)

    @Test func connectorReadsPraticheAndLinksUnderASymlinkedRoot() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaWithLinks, to: "\(folder)/pratica.md")
        let link = scratchLink()
        try symlink(link, to: vault.root)
        defer { try? FileManager.default.removeItem(at: link) }

        let session = VaultSession(root: link, stateBase: vault.stateBase)
        await session.rescan()

        #expect(VaultAPI.pratiche(session).map(\.path) == [folder])
        #expect(try VaultAPI.pratica(session, folder).path == folder)
        let links = try VaultAPI.praticaLinks(session, folder)
        #expect(links.notes.map(\.reference) == ["[[Offerta 2026]]"])
    }

    // MARK: - readTimeline / dossier(at:) (PraticheController+TimelineRead)

    @Test func readTimelineAndDossierRefuseAPathThatLeavesTheVault() throws {
        let nested = try NestedVault()
        // Control: the same folder, named from inside its own vault, is a real pratica.
        #expect(PraticheController.dossier(at: "Offerta", vaultRoot: nested.outer) != nil)
        #expect(PraticheController.readTimeline(praticaPath: "Offerta", vaultRoot: nested.outer).entries.count == 1)

        let read = PraticheController.readTimeline(praticaPath: "../Offerta", vaultRoot: nested.vault)
        #expect(read.entries.isEmpty)
        #expect(read.details.isEmpty)
        #expect(read.praticaNoteHash == nil)
        #expect(PraticheController.dossier(at: "../Offerta", vaultRoot: nested.vault) == nil)
    }

    @Test func readTimelineAndDossierReadANormalPraticaAndOneUnderASymlinkedRoot() throws {
        let vault = try TemporaryVault()
        try vault.write(praticaWithLinks + "\n\n## 2026-06-10 14:06 Nota · Mario Rossi\nUna voce.\n", to: "\(folder)/pratica.md")
        let link = scratchLink()
        try symlink(link, to: vault.root)
        defer { try? FileManager.default.removeItem(at: link) }

        for root in [vault.root, link] {
            #expect(PraticheController.dossier(at: folder, vaultRoot: root) != nil)
            let read = PraticheController.readTimeline(praticaPath: folder, vaultRoot: root)
            #expect(read.entries.count == 1)
            #expect(read.praticaNoteHash != nil)
        }
    }

    // MARK: - reloadTimeline's links (PraticheController+Ledger)

    @Test func reloadTimelineReadsNothingFromASelectionThatLeavesTheVault() async throws {
        let nested = try NestedVault()
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(nested.vault)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })

        pratiche.selection = "../Offerta"
        pratiche.reloadTimeline(from: controller)

        #expect(pratiche.links == .empty)
        #expect(pratiche.timeline.isEmpty)
        #expect(pratiche.timelineOrigin == nil)
        controller.close()
    }

    @Test func reloadTimelineReadsLinksFromANormalPraticaAndUnderASymlinkedRoot() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaWithLinks, to: "\(folder)/pratica.md")
        let link = scratchLink()
        try symlink(link, to: vault.root)
        defer { try? FileManager.default.removeItem(at: link) }

        for root in [vault.root, link] {
            let controller = VaultController(recents: .volatile(), openTabs: .volatile())
            await controller.open(root)
            let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
            pratiche.selection = folder
            pratiche.reloadTimeline(from: controller)
            #expect(pratiche.links.notes == ["Offerta 2026"], "root: \(root.path)")
            controller.close()
        }
    }
}
