import Foundation
import Testing
@testable import Pergamenum

// ADR-0049 (Pratiche links to notes, tasks and boards), plan
// docs/plans/pratiche-note-task-workspace-links.md, Task 4 - R-01, R-02, R-03.
//
// `PraticaLinksWriterTests.swift` (Task 2) already pins the byte-preserving write door
// and the per-message key's own round trip. What this file owns is the layer above it:
// `PraticaCommandActions`' picker-facing functions - the three pratica-level "link an
// existing target" verbs (R-01), the message relation's replace-not-append rule (R-02),
// and the three "create, then link" verbs the picker's «Crea nuova…» row drives (R-03).

private let praticaWithDossier = """
---
pergamenum-dossier: 1
pergamenum-dossier-counterparts:
  - m.rossi@rossi-spa.it
---

Corpo della pratica, non toccato.
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

@MainActor
private func makeActions(root: URL) async -> PraticaCommandActions {
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(root)
    let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
    return PraticaCommandActions(pratiche: pratiche, vault: vaultController, navigation: Navigation())
}

// MARK: - R-01: the pratica's three general relations

@MainActor
@Suite struct PraticaLinkExistingTargetTests {
    @Test func linkingAnExistingNoteAddsItToTheNotesKey() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaWithDossier, to: "Rossi/pratica.md")
        let actions = await makeActions(root: vault.root)
        let request = PraticaLinkRequest(
            kind: .note, scope: .pratica(path: "Rossi"), contextTitle: "Rossi", contextTags: []
        )

        await actions.linkExistingNote(titled: "Offerta 2026", for: request)

        let text = try String(contentsOf: vault.root.appending(path: "Rossi/pratica.md"), encoding: .utf8)
        #expect(text.contains("pergamenum-dossier-links-notes:"))
        #expect(text.contains("\"[[Offerta 2026]]\""))
    }

    @Test func linkingAnExistingBoardAddsItToTheBoardsKey() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaWithDossier, to: "Rossi/pratica.md")
        let actions = await makeActions(root: vault.root)
        let request = PraticaLinkRequest(
            kind: .board, scope: .pratica(path: "Rossi"), contextTitle: "Rossi", contextTags: []
        )

        await actions.linkExistingBoard(at: "Workspace/Rossi.canvas", for: request)

        let links = PraticaLinks.parse(praticaFileAt: vault.root.appending(path: "Rossi/pratica.md"))
        #expect(links.boards == ["Rossi.canvas"])
    }

    @Test func linkingAnExistingTaskThatAlreadyCarriesAnIDNeverTouchesItsOwnFile() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaWithDossier, to: "Rossi/pratica.md")
        let actions = await makeActions(root: vault.root)
        let request = PraticaLinkRequest(
            kind: .task, scope: .pratica(path: "Rossi"), contextTitle: "Rossi", contextTags: []
        )
        let task = TaskParser.parse(line: "- [ ] Verifica disegno ^id(5)", sourcePath: "Altra.md", lineIndex: 0)!

        await actions.linkExistingTask(task, for: request)

        let links = PraticaLinks.parse(praticaFileAt: vault.root.appending(path: "Rossi/pratica.md"))
        #expect(links.tasks == [.init(noteTitle: "Altra", localID: 5)])
        #expect(!FileManager.default.fileExists(
            atPath: vault.root.appending(path: "Altra.md").path(percentEncoded: false)
        ))
    }

    @Test func linkingAnExistingTaskWithNoIDAllocatesOneAndRewritesItsLine() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaWithDossier, to: "Rossi/pratica.md")
        let taskNoteText = "- [ ] Verifica disegno\n"
        try vault.write(taskNoteText, to: "Tasks.md")
        let actions = await makeActions(root: vault.root)
        let request = PraticaLinkRequest(
            kind: .task, scope: .pratica(path: "Rossi"), contextTitle: "Rossi", contextTags: []
        )
        let task = TaskParser.tasks(in: taskNoteText, sourcePath: "Tasks.md")[0]
        #expect(task.localID == nil)

        await actions.linkExistingTask(task, for: request)

        let taskText = try String(contentsOf: vault.root.appending(path: "Tasks.md"), encoding: .utf8)
        #expect(taskText.contains("^id(1)"))
        let links = PraticaLinks.parse(praticaFileAt: vault.root.appending(path: "Rossi/pratica.md"))
        #expect(links.tasks == [.init(noteTitle: "Tasks", localID: 1)])
    }
}

// MARK: - R-02: the message's one relation replaces rather than appends

@MainActor
@Suite struct PraticaLinkMessageReplaceTests {
    @Test func linkingAMessageToASecondNoteReplacesTheFirstRatherThanAppending() async throws {
        let vault = try TemporaryVault()
        try vault.write(messageWithNoLink, to: "Rossi/email/msg.md")
        let actions = await makeActions(root: vault.root)
        let request = PraticaLinkRequest(
            kind: .note, scope: .message(notePath: "Rossi/email/msg.md"), contextTitle: "Richiesta offerta",
            contextTags: []
        )

        await actions.linkExistingNote(titled: "Offerta 2026", for: request)
        await actions.linkExistingNote(titled: "Contratto 2026", for: request)

        let text = try String(contentsOf: vault.root.appending(path: "Rossi/email/msg.md"), encoding: .utf8)
        #expect(text.contains("pergamenum-mail-note: \"[[Contratto 2026]]\""))
        #expect(!text.contains("Offerta 2026"))
        #expect(text.components(separatedBy: "pergamenum-mail-note:").count - 1 == 1)
    }
}

// MARK: - R-03: create the target first, link it second

@MainActor
@Suite struct PraticaLinkCreateAndLinkTests {
    @Test func creatingAndLinkingANoteCreatesItWithTheContextTagsThenLinksIt() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaWithDossier, to: "Rossi/pratica.md")
        let actions = await makeActions(root: vault.root)
        let request = PraticaLinkRequest(
            kind: .note, scope: .pratica(path: "Rossi"), contextTitle: "Rossi",
            contextTags: [Tag("topic-pratica")!]
        )

        await actions.createAndLinkNote(titled: "Preventivo 2026", for: request)

        let noteText = try String(contentsOf: vault.root.appending(path: "Preventivo 2026.md"), encoding: .utf8)
        #expect(noteText.contains("topic-pratica"))
        let links = PraticaLinks.parse(praticaFileAt: vault.root.appending(path: "Rossi/pratica.md"))
        #expect(links.notes == ["Preventivo 2026"])
    }

    @Test func creatingAndLinkingANoteWithABlankTitleCreatesNothingAndLinksNothing() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaWithDossier, to: "Rossi/pratica.md")
        let actions = await makeActions(root: vault.root)
        let request = PraticaLinkRequest(
            kind: .note, scope: .pratica(path: "Rossi"), contextTitle: "Rossi", contextTags: []
        )

        await actions.createAndLinkNote(titled: "   ", for: request)

        let links = PraticaLinks.parse(praticaFileAt: vault.root.appending(path: "Rossi/pratica.md"))
        #expect(links.notes.isEmpty)
    }

    @Test func creatingAndLinkingATaskCapturesItAllocatesAnIDThenLinksIt() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaWithDossier, to: "Rossi/pratica.md")
        let actions = await makeActions(root: vault.root)
        let request = PraticaLinkRequest(
            kind: .task, scope: .pratica(path: "Rossi"), contextTitle: "Rossi", contextTags: []
        )

        await actions.createAndLinkTask(texted: "Richiamare il cliente", for: request)

        let captureText = try String(
            contentsOf: vault.root.appending(path: "00 Inbox/Capture.md"), encoding: .utf8
        )
        #expect(captureText.contains("Richiamare il cliente"))
        #expect(captureText.contains("^id(1)"))
        let links = PraticaLinks.parse(praticaFileAt: vault.root.appending(path: "Rossi/pratica.md"))
        #expect(links.tasks == [.init(noteTitle: "Capture", localID: 1)])
    }

    @Test func creatingAndLinkingABoardCreatesTheFileThenLinksItsName() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaWithDossier, to: "Rossi/pratica.md")
        let actions = await makeActions(root: vault.root)
        let request = PraticaLinkRequest(
            kind: .board, scope: .pratica(path: "Rossi"), contextTitle: "Rossi", contextTags: []
        )

        await actions.createAndLinkBoard(named: "Preventivo", in: "", for: request)

        #expect(FileManager.default.fileExists(
            atPath: vault.root.appending(path: "Preventivo.canvas").path(percentEncoded: false)
        ))
        let links = PraticaLinks.parse(praticaFileAt: vault.root.appending(path: "Rossi/pratica.md"))
        #expect(links.boards == ["Preventivo.canvas"])
    }
}
