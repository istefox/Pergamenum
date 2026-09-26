import Foundation
import Testing
@testable import Pergamenum

// ADR-0049 (Pratiche links to notes, tasks and boards), plan
// docs/plans/pratiche-note-task-workspace-links.md, Task 7 - R-01, R-02, R-03, R-10, §D12.
//
// `Sources/Connector/VaultPraticheLinks.swift` is what a shell or a model reaches
// instead of the app's own `PraticaCommandActions+Links.swift` - this file is the SPEC's
// connector seam: the same relations, read with resolution state and written with the
// same three guarantees (`isDryRun`, diff, journal) every other connector write carries.

private let praticaFolder = "01 Progetti/Rossi/Offerta"

private let minimalPraticaNote = """
---
pergamenum-dossier: 1
pergamenum-dossier-counterparts:
  - m.rossi@rossi-spa.it
---

Appunti pratica.
"""

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

private let messagePath = "\(praticaFolder)/email/msg.md"

@MainActor
private func openVaultWithOnePratica(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(minimalPraticaNote, to: "\(praticaFolder)/pratica.md")
    try vault.write(messageWithNoLink, to: messagePath)
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

@MainActor
@Suite(.serialized) struct VaultAPIPraticheLinksTests {
    // MARK: - Reading: resolution state (R-07, R-08)

    @Test func praticaLinksResolvesAnExistingNoteAsUniqueAndAMissingOneAsMissing() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)
        try vault.write("---\ndate: 2026-09-01\ntags:\n  - type-note\n---\n\nCorpo.", to: "Offerta 2026.md")
        await session.rescan()

        VaultAPI.arm(session, command: "pratica_link_note", dryRun: false)
        _ = try await VaultAPI.linkPraticaNote(session, pratica: praticaFolder, title: "Offerta 2026")
        _ = try await VaultAPI.linkPraticaNote(session, pratica: praticaFolder, title: "Non Esiste")

        let links = try VaultAPI.praticaLinks(session, praticaFolder)
        #expect(links.notes.count == 2)
        let unique = try #require(links.notes.first { $0.reference.contains("Offerta 2026") })
        #expect(unique.state == "unique")
        #expect(unique.path == "Offerta 2026.md")
        let missing = try #require(links.notes.first { $0.reference.contains("Non Esiste") })
        #expect(missing.state == "missing")
        #expect(missing.path == nil)
    }

    @Test func aMessageWithNoLinkReadsAsNilRatherThanBroken() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)

        #expect(try VaultAPI.praticaMessageLink(session, at: messagePath) == nil)
    }

    // MARK: - Writing, and the dry-run guarantee (R-10)

    @Test func linkingAPraticaNoteAsADryRunChangesNoByteButReturnsADiff() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)
        let notePath = vault.root.appending(path: "\(praticaFolder)/pratica.md")
        let before = try Data(contentsOf: notePath)

        VaultAPI.arm(session, command: "pratica_link_note", dryRun: true)
        let summary = try await VaultAPI.linkPraticaNote(session, pratica: praticaFolder, title: "Offerta 2026")

        #expect(!summary.applied)
        #expect(try #require(summary.diff).contains("pergamenum-dossier-links-notes"))
        #expect(try Data(contentsOf: notePath) == before)
    }

    @Test func linkingAndUnlinkingAPraticaBoardRoundTrips() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)

        VaultAPI.arm(session, command: "pratica_link_board", dryRun: false)
        let linked = try await VaultAPI.linkPraticaBoard(session, pratica: praticaFolder, board: "Rossi.canvas")
        #expect(linked.applied)
        let afterLink = try VaultAPI.praticaLinks(session, praticaFolder).boards
        #expect(afterLink.count == 1)
        // No `Rossi.canvas` board exists on disk yet: linking a bare name is allowed
        // (a link can exist before a board that fulfils it, R-03's other direction),
        // and shows up as missing rather than blocking the write.
        #expect(afterLink.first?.reference == "[[Rossi.canvas]]")
        #expect(afterLink.first?.state == "missing")

        let unlinked = try await VaultAPI.unlinkPraticaBoard(session, pratica: praticaFolder, board: "Rossi.canvas")
        #expect(unlinked.applied)
        #expect(try VaultAPI.praticaLinks(session, praticaFolder).boards.isEmpty)
    }

    @Test func linkingAPraticaTaskAllocatesAnIDWhenTheTaskHasNoneYet() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)
        try vault.write("- [ ] Verifica disegno\n", to: "Tasks.md")
        await session.rescan()

        VaultAPI.arm(session, command: "pratica_link_task", dryRun: false)
        _ = try await VaultAPI.linkPraticaTask(session, pratica: praticaFolder, task: "Verifica disegno")

        let taskText = try String(contentsOf: vault.root.appending(path: "Tasks.md"), encoding: .utf8)
        #expect(taskText.contains("^id(1)"))
        let links = try VaultAPI.praticaLinks(session, praticaFolder)
        #expect(links.tasks.count == 1)
        #expect(links.tasks.first?.state == "unique")
    }

    @Test func unlinkingATaskWithNoIDIsANoOpRatherThanAnError() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)
        try vault.write("- [ ] Verifica disegno\n", to: "Tasks.md")
        await session.rescan()

        VaultAPI.arm(session, command: "pratica_unlink_task", dryRun: false)
        let summary = try await VaultAPI.unlinkPraticaTask(session, pratica: praticaFolder, task: "Verifica disegno")
        #expect(!summary.applied)
    }

    // MARK: - R-02: the message's one relation replaces rather than appends

    @Test func linkingAMessageNoteTwiceReplacesRatherThanAppending() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)

        VaultAPI.arm(session, command: "message_link_note", dryRun: false)
        _ = try await VaultAPI.linkMessageNote(session, message: messagePath, title: "Offerta 2026")
        _ = try await VaultAPI.linkMessageNote(session, message: messagePath, title: "Contratto 2026")

        let text = try String(contentsOf: vault.root.appending(path: messagePath), encoding: .utf8)
        #expect(text.contains("pergamenum-mail-note: \"[[Contratto 2026]]\""))
        #expect(!text.contains("Offerta 2026"))
        #expect(text.components(separatedBy: "pergamenum-mail-note:").count - 1 == 1)

        let link = try VaultAPI.praticaMessageLink(session, at: messagePath)
        #expect(link?.reference == "[[Contratto 2026]]")
    }

    @Test func unlinkingAMessageNoteRemovesTheKeyAndReadsAsNilAgain() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)

        VaultAPI.arm(session, command: "message_link_note", dryRun: false)
        _ = try await VaultAPI.linkMessageNote(session, message: messagePath, title: "Offerta 2026")
        _ = try await VaultAPI.unlinkMessageNote(session, message: messagePath)

        let text = try String(contentsOf: vault.root.appending(path: messagePath), encoding: .utf8)
        #expect(!text.contains("pergamenum-mail-note"))
        #expect(try VaultAPI.praticaMessageLink(session, at: messagePath) == nil)
    }

    // MARK: - R-03: create the target first, link it second

    @Test func creatingAndLinkingAPraticaNoteCreatesItWithContextTagsThenLinksIt() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)

        VaultAPI.arm(session, command: "pratica_create_note", dryRun: false)
        _ = try await VaultAPI.createAndLinkPraticaNote(
            session, pratica: praticaFolder, title: "Preventivo 2026", folder: nil
        )

        let noteText = try String(contentsOf: vault.root.appending(path: "Preventivo 2026.md"), encoding: .utf8)
        #expect(noteText.contains("topic-pratica"))
        let links = try VaultAPI.praticaLinks(session, praticaFolder)
        #expect(links.notes.contains { $0.reference.contains("Preventivo 2026") })
    }

    @Test func creatingAndLinkingAPraticaBoardCreatesTheFileThenLinksItsName() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)

        VaultAPI.arm(session, command: "pratica_create_board", dryRun: false)
        _ = try await VaultAPI.createAndLinkPraticaBoard(
            session, pratica: praticaFolder, name: "Preventivo", folder: nil
        )

        #expect(FileManager.default.fileExists(
            atPath: vault.root.appending(path: "Preventivo.canvas").path(percentEncoded: false)
        ))
        let links = try VaultAPI.praticaLinks(session, praticaFolder)
        let board = try #require(links.boards.first)
        #expect(board.state == "unique")
        #expect(board.path == "Preventivo.canvas")
    }

    @Test func creatingAndLinkingAMessageNoteCreatesItThenLinksIt() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)

        VaultAPI.arm(session, command: "message_create_note", dryRun: false)
        _ = try await VaultAPI.createAndLinkMessageNote(session, message: messagePath, title: "Preventivo 2026")

        #expect(FileManager.default.fileExists(
            atPath: vault.root.appending(path: "Preventivo 2026.md").path(percentEncoded: false)
        ))
        let link = try VaultAPI.praticaMessageLink(session, at: messagePath)
        #expect(link?.state == "unique")
    }

    // MARK: - ADR-0063 §D4/§D6: the board goes through the session's door, and every
    // «create and link» summary names the file it creates

    private func bytes(_ vault: borrowing TemporaryVault, _ relativePath: String) throws -> Data {
        try Data(contentsOf: vault.root.appending(path: relativePath))
    }

    private func journalIDs(_ vault: borrowing TemporaryVault) throws -> [String] {
        try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: nil).map(\.id)
    }

    @Test func aBoardRehearsalLeavesNoCanvasAndNoJournalEntry() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)
        let praticaBefore = try bytes(vault, "\(praticaFolder)/pratica.md")
        let journalBefore = try journalIDs(vault)

        // The MCP default: `dryRun` true. Before ADR-0063 the store wrote the board anyway.
        VaultAPI.arm(session, command: "pratica_create_board", dryRun: true)
        let summary = try await VaultAPI.createAndLinkPraticaBoard(
            session, pratica: praticaFolder, name: "Preventivo", folder: nil
        )

        #expect(!summary.applied)
        #expect(summary.note?.contains("Preventivo.canvas") == true)
        #expect(!FileManager.default.fileExists(
            atPath: vault.root.appending(path: "Preventivo.canvas").path(percentEncoded: false)
        ))
        #expect(try bytes(vault, "\(praticaFolder)/pratica.md") == praticaBefore)
        #expect(try journalIDs(vault) == journalBefore)
    }

    @Test func aRealBoardCreationIsJournalledAndItsUndoIsDeclined() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)

        VaultAPI.arm(session, command: "pratica_create_board", dryRun: false)
        _ = try await VaultAPI.createAndLinkPraticaBoard(
            session, pratica: praticaFolder, name: "Preventivo", folder: nil
        )

        let canvas = vault.root.appending(path: "Preventivo.canvas").path(percentEncoded: false)
        #expect(FileManager.default.fileExists(atPath: canvas))
        #expect(try VaultAPI.praticaLinks(session, praticaFolder).boards.first?.path == "Preventivo.canvas")

        let rows = try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: nil)
            .filter { $0.path == "Preventivo.canvas" }
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.created)
        #expect(row.command == "pratica_create_board")

        // The journal never deletes: undoing a creation is declined, as for a note.
        VaultAPI.arm(session, command: "undo_write", dryRun: false)
        do {
            _ = try await VaultAPI.undo(session, id: row.id)
            Issue.record("l'undo di una creazione è stato applicato")
        } catch let error as ConnectorError {
            #expect(error.description.contains("ha creato"))
        }
        #expect(FileManager.default.fileExists(atPath: canvas))
    }

    @Test func aTakenBoardNameIsRefusedBeforeAnyWrite() async throws {
        let vault = try TemporaryVault()
        let session = try await openVaultWithOnePratica(vault)
        try vault.write("{\"nodes\":[]}", to: "Preventivo.canvas")
        let praticaBefore = try bytes(vault, "\(praticaFolder)/pratica.md")

        for dryRun in [true, false] {
            VaultAPI.arm(session, command: "pratica_create_board", dryRun: dryRun)
            await #expect(throws: (any Error).self) {
                _ = try await VaultAPI.createAndLinkPraticaBoard(
                    session, pratica: praticaFolder, name: "Preventivo", folder: nil
                )
            }
        }

        #expect(try bytes(vault, "\(praticaFolder)/pratica.md") == praticaBefore)
        #expect(try bytes(vault, "Preventivo.canvas") == Data("{\"nodes\":[]}".utf8))
    }

    @Test func eachCreateAndLinkSummaryNamesTheCreatedFile() async throws {
        typealias Verb = (command: String, created: String, run: (VaultSession) async throws -> VaultAPI.WriteSummary)
        let verbs: [Verb] = [
            ("pratica_create_note", "Preventivo 2026.md", { session in
                try await VaultAPI.createAndLinkPraticaNote(
                    session, pratica: praticaFolder, title: "Preventivo 2026", folder: nil
                )
            }),
            ("pratica_create_board", "Preventivo.canvas", { session in
                try await VaultAPI.createAndLinkPraticaBoard(
                    session, pratica: praticaFolder, name: "Preventivo", folder: nil
                )
            }),
            ("message_create_note", "Preventivo 2026.md", { session in
                try await VaultAPI.createAndLinkMessageNote(session, message: messagePath, title: "Preventivo 2026")
            }),
        ]

        for verb in verbs {
            let vault = try TemporaryVault()
            let session = try await openVaultWithOnePratica(vault)
            for dryRun in [true, false] {
                VaultAPI.arm(session, command: verb.command, dryRun: dryRun)
                let summary = try await verb.run(session)
                #expect(
                    summary.note?.contains(verb.created) == true,
                    "\(verb.command), dryRun \(dryRun): il riassunto non nomina «\(verb.created)»"
                )
                // No new JSON key: the file is named in the existing `note` field.
                let encoded = try JSONEncoder().encode(summary)
                let keys = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any]).keys
                #expect(Set(keys).isSubset(of: ["path", "applied", "diff", "note"]))
            }
        }
    }
}
