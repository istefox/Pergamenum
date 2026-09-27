import Foundation
import Testing
@testable import Pergamenum

private typealias VaultTag = Pergamenum.Tag

// ADR-0066 (one door onto the editor after a landed change), plan
// docs/plans/pg-257-pratiche-sync-integrity-and-post-write-door.md, Task 1 - R-01, R-02,
// R-03, R-05, R-06.
//
// **Tester-declared red suite.** `VaultSession.announce(_:)` and `VaultController.landed(_:)`
// are both intentional no-op stubs today (see their doc comments), so most of the tests
// below fail for that exact reason: nothing calls `landed(_:)` yet, and no door announces a
// change through `landedChangeSubscriber`. Task 2 replaces both stubs' bodies and wires
// `write`, `moveFile`, `trashFile` and the three app-only folder doors to call `announce(_:)`,
// and `VaultController.open(_:)`/`close()` to install/clear the subscriber - only then do the
// reds below go green, with no change to this file.
//
// A handful of assertions are marked "guard": they hold today, through the *existing*
// `syncOpenNote(with:)`/`syncOpenNote(with:savedBy:)` call sites this chain has not touched
// yet, and must keep holding once Task 2 deletes those call sites in favour of the door.

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-09-26\ntags:\n  - type-note\n---\n\n\(body)\n"
}

private let linkableNote = """
---
date: 2026-08-11
tags:
  - type-note
  - topic-x
---

Corpo della nota.
"""

@MainActor
private func controller(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    try vault.write(note("A."), to: "A.md")
    try vault.write(note("B."), to: "B.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    return controller
}

/// A.md in both columns, with the focus back on the first: the second column's copy is the
/// one a focused-only catch-up cannot see. Mirrors
/// `Tests/VaultControllerWriteCatchUpTests.swift`'s own helper of the same shape.
@MainActor
private func controllerWithANoteInBothColumns(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    let controller = try await controller(vault)
    controller.openNote(at: "A.md")
    controller.splitEditor()
    controller.focusColumn(0)
    try #require(controller.focusedColumnIndex == 0)
    try #require(controller.columns[1].tabs.contains { $0.note.relativePath == "A.md" })
    return controller
}

private func tab(showing path: String, in column: EditorColumn) throws -> NoteTab {
    try #require(column.tabs.first { $0.note.relativePath == path })
}

// MARK: - A session write, with no explicit controller call (R-01)

@MainActor
@Test func aSessionWriteReachesACleanTabInTheOtherColumn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controllerWithANoteInBothColumns(vault)
    defer { controller.close() }
    let session = try #require(controller.session)
    let written = note("A, scritta dalla sessione.")

    _ = try await session.write(written, to: "A.md")

    let background = try tab(showing: "A.md", in: controller.columns[1])
    #expect(background.note.text == written)
    #expect(background.note.savedText == written)
    #expect(background.note.externalChangePending == nil)
}

@MainActor
@Test func aSessionWriteReachesACleanBackgroundTabInTheSameColumn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    defer { controller.close() }
    controller.openNote(at: "A.md")
    let backgroundID = try #require(controller.focusedTab?.id)
    controller.openNoteInNewTab(at: "B.md")
    try #require(controller.focusedTab?.note.relativePath == "B.md")
    let session = try #require(controller.session)
    let written = note("A, scritta dalla sessione.")

    _ = try await session.write(written, to: "A.md")

    let background = try #require(controller.tabs.first { $0.id == backgroundID })
    #expect(background.note.text == written)
    #expect(background.note.savedText == written)
}

@MainActor
@Test func aSessionWriteRaisesThePromptOnADirtyTabAndLeavesItsTextAlone() async throws {
    let vault = try TemporaryVault()
    let controller = try await controllerWithANoteInBothColumns(vault)
    defer { controller.close() }
    controller.updateOpenNoteText(note("A, non salvato."))
    controller.focusColumn(1)
    try #require(controller.focusedColumnIndex == 1)
    let session = try #require(controller.session)
    let written = note("A, scritta dalla sessione.")

    _ = try await session.write(written, to: "A.md")

    let dirty = try tab(showing: "A.md", in: controller.columns[0])
    #expect(dirty.note.externalChangePending == .text(written))
    #expect(dirty.note.text == note("A, non salvato."))
}

// MARK: - The writer's own save (R-02)

/// Guard: today's `saveOpenNote()` already routes through `syncOpenNote(with:savedBy:)`, so
/// the writer gets no prompt. This must still hold once Task 2 moves the same behaviour
/// behind `origin:`/`landed(_:)`.
@MainActor
@Test func savingGivesTheWriterNoPromptThroughARealSave() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    defer { controller.close() }
    controller.openNote(at: "A.md")
    controller.updateOpenNoteText(note("A, salvato."))

    await controller.saveOpenNote()

    #expect(controller.openNote?.hasUnsavedChanges == false)
    #expect(controller.openNote?.externalChangePending == nil)
}

/// ADR-0058 test 12's shape, driven through the new door instead of `syncOpenNote(with:
/// savedBy:)`: typing after the write returned must not raise a prompt on the writer, and
/// the write's own text must be adopted as `savedText` - which only a real `landed(_:)` can
/// do, since the stub touches nothing.
@MainActor
@Test func landedWrittenAfterTypingKeepsTheTypedTextUnsavedWithNoPrompt() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    defer { controller.close() }
    controller.openNote(at: "A.md")
    let writerID = try #require(controller.focusedTab?.id)
    let written = note("A, salvato.")
    controller.updateOpenNoteText(written)
    // Typed during the save's suspension, after `written` was handed to the write.
    let newer = note("A, salvato e poi ancora modificato.")
    controller.updateOpenNoteText(newer)

    controller.landed(.written(VaultSession.WriteResult(path: "A.md", text: written), origin: writerID))

    let writer = try #require(controller.tabs.first { $0.id == writerID })
    #expect(writer.note.text == newer, "il testo digitato dopo la scrittura resta")
    #expect(writer.note.savedText == written, "la porta deve adottare il testo scritto come base salvata")
    #expect(writer.note.hasUnsavedChanges)
    #expect(writer.note.externalChangePending == nil)
}

// MARK: - `moveFile`/`trashFile`, with no manual follow-up (R-03)

@MainActor
@Test func sessionMoveFileRepointsACleanTabInBothColumnsAndKeepsADirtyTabsBuffer() async throws {
    let vault = try TemporaryVault()
    let controller = try await controllerWithANoteInBothColumns(vault)
    defer { controller.close() }
    controller.focusColumn(1)
    controller.updateOpenNoteText(note("A, non salvato nella seconda colonna."))
    controller.focusColumn(0)
    let session = try #require(controller.session)

    try await session.moveFile(from: "A.md", to: "A-spostata.md")

    let cleanColumnPath = controller.columns[0].tabs.first?.note.relativePath
    #expect(cleanColumnPath == "A-spostata.md", "senza la porta la scheda pulita resta su \"A.md\"")
    let dirtyColumnPath = controller.columns[1].tabs.first?.note.relativePath
    #expect(dirtyColumnPath == "A-spostata.md", "senza la porta la scheda sporca resta su \"A.md\"")
    #expect(controller.columns[1].tabs.first?.note.text == note("A, non salvato nella seconda colonna."))
}

@MainActor
@Test func sessionTrashFileClosesACleanTabAndAsksADirtyOneWithNoFollowUpCall() async throws {
    let vault = try TemporaryVault()
    let controller = try await controllerWithANoteInBothColumns(vault)
    defer { controller.close() }
    controller.focusColumn(1)
    controller.updateOpenNoteText(note("A, non salvato."))
    controller.focusColumn(0)
    let session = try #require(controller.session)

    try await session.trashFile(at: "A.md")

    #expect(!controller.columns[0].tabs.contains { $0.note.relativePath == "A.md" })
    let dirty = try tab(showing: "A.md", in: controller.columns[1])
    #expect(dirty.note.externalChangePending == .deleted)

    // A following external reconcile for the same, now-gone path closes nothing further:
    // the door already dealt with every tab that showed it.
    let changes = await session.reconcile(["A.md"])
    #expect(changes.isEmpty || changes.allSatisfy { $0.content == .deleted })
}

// MARK: - A bare session with a recording subscriber (R-05)

@MainActor
private func bareSession(_ vault: borrowing TemporaryVault) async -> VaultSession {
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

@MainActor
@Test func aDryRunWriteMoveAndTrashAnnounceNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A.md")
    try vault.write(note(), to: "B.md")
    let session = await bareSession(vault)
    var recorded: [VaultSession.LandedChange] = []
    session.landedChangeSubscriber = { recorded.append($0) }
    session.isDryRun = true

    _ = try await session.write(note("Modificata."), to: "A.md")
    try await session.moveFile(from: "A.md", to: "A2.md")
    try await session.trashFile(at: "B.md")

    #expect(recorded.isEmpty)
}

@MainActor
@Test func aRefusedWriteAnnouncesNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A.md")
    let session = await bareSession(vault)
    var recorded: [VaultSession.LandedChange] = []
    session.landedChangeSubscriber = { recorded.append($0) }

    await #expect(throws: (any Error).self) {
        try await session.write(note("Scarto."), to: "A.md", expecting: "hash-che-non-combacia")
    }

    #expect(recorded.isEmpty)
}

@MainActor
@Test func landedGenerationAdvancesOnWriteBothEndsOfAMoveAndATrashButNotOnARehearsal() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A.md")
    try vault.write(note(), to: "B.md")
    let session = await bareSession(vault)

    _ = try await session.write(note("Scritta."), to: "A.md")
    #expect(session.landedGeneration(at: "A.md") == 1, "una scrittura reale deve avanzare la generazione")

    try await session.moveFile(from: "A.md", to: "A2.md")
    #expect(session.landedGeneration(at: "A.md") >= 2, "il lato di partenza dello spostamento avanza")
    #expect(session.landedGeneration(at: "A2.md") >= 1, "il lato di arrivo dello spostamento avanza")

    try await session.trashFile(at: "B.md")
    #expect(session.landedGeneration(at: "B.md") >= 1, "l'eliminazione avanza la generazione")

    let before = session.landedGeneration(at: "A2.md")
    session.isDryRun = true
    _ = try await session.write(note("Prova a vuoto."), to: "A2.md")
    #expect(session.landedGeneration(at: "A2.md") == before, "una prova a vuoto non avanza nulla")
}

// MARK: - Cross-vault isolation (ADR-0066 §D4)

/// Guard: with no subscriber wired to anything yet, a write on the first vault's session can
/// never reach the second vault's tabs today, and must still never reach them once the door
/// is wired - `VaultController.open(_:)` clears the outgoing session's subscriber first.
@MainActor
@Test func aWriteOnTheFirstSessionAfterOpeningASecondVaultReachesNoTabOfTheSecond() async throws {
    let first = try TemporaryVault()
    try first.write(note("A."), to: "A.md")
    let second = try TemporaryVault()
    try second.write(note("A."), to: "A.md")

    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(first.root)
    let firstSession = try #require(controller.session)
    controller.openNote(at: "A.md")

    await controller.open(second.root)
    defer { controller.close() }
    controller.openNote(at: "A.md")
    let secondTabText = controller.openNote?.text

    _ = try await firstSession.write(note("Scritta sulla prima sessione."), to: "A.md")

    #expect(controller.openNote?.text == secondTabText)
}

// MARK: - One test per ADR-0058 §D7 writer family, plus a Pratiche link write (R-06)

@MainActor
@Test func renameNotesLinkRewriteCatchesUpTheLinkingNoteOpenInATab() async throws {
    let vault = try TemporaryVault()
    try vault.write(linkableNote, to: "Origine.md")
    try vault.write(linkableNote, to: "03 Risorse/Destinazione.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    defer { controller.close() }
    let session = try #require(controller.session)
    _ = try await session.addStructuralLink(
        from: "Origine.md", to: "Destinazione",
        reason: "usa i dati", reverseReason: "fornisce i dati"
    )
    controller.openNote(at: "Origine.md")
    try #require(!controller.openNote!.hasUnsavedChanges)

    _ = try await session.renameNote(at: "03 Risorse/Destinazione.md", to: "Destinazione rinominata")

    let onDisk = try session.read("Origine.md").text
    try #require(onDisk.contains("[[Destinazione rinominata]]"))
    #expect(controller.openNote?.text == onDisk, "la nota che linkava deve essere allineata senza chiamate esplicite")
}

@MainActor
@Test func renameTagCatchesUpAnOpenTabOfARewrittenNote() async throws {
    let vault = try TemporaryVault()
    try vault.write(
        "---\ndate: 2026-08-19\ntags:\n  - type-note\n  - topic-gomma\n---\n\nCorpo.\n", to: "Uno.md"
    )
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    defer { controller.close() }
    controller.openNote(at: "Uno.md")
    try #require(!controller.openNote!.hasUnsavedChanges)
    let session = try #require(controller.session)

    _ = await session.renameTag(try #require(VaultTag("topic-gomma")), to: try #require(VaultTag("topic-fune")))

    let onDisk = try session.read("Uno.md").text
    #expect(controller.openNote?.text == onDisk)
    #expect(controller.openNote?.text.contains("topic-fune") == true)
}

@MainActor
@Test func undoJournalledWritesCatchesUpAnOpenTabOfTheRestoredNote() async throws {
    let vault = try TemporaryVault()
    try vault.write(
        "---\ndate: 2026-08-19\ntags:\n  - type-note\n  - topic-gomma\n---\n\nCorpo.\n", to: "Uno.md"
    )
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    defer { controller.close() }
    let session = try #require(controller.session)
    let outcome = await session.renameTag(try #require(VaultTag("topic-gomma")), to: try #require(VaultTag("topic-fune")))
    controller.openNote(at: "Uno.md")
    try #require(!controller.openNote!.hasUnsavedChanges)
    session.journal = session.journalOnDisk

    _ = await session.undoJournalledWrites(outcome.journalIDs)

    let onDisk = try session.read("Uno.md").text
    #expect(controller.openNote?.text == onDisk)
    #expect(controller.openNote?.text.contains("topic-gomma") == true)
}

@MainActor
@Test func moveOnBoardCatchesUpAnOpenTabOfTheDroppedNote() async throws {
    let vault = try TemporaryVault()
    try vault.write(
        "---\ndate: 2026-08-19\ntags:\n  - type-note\n  - project-presse\n---\n\nCorpo.\n", to: "Carta.md"
    )
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    defer { controller.close() }
    controller.openNote(at: "Carta.md")
    try #require(!controller.openNote!.hasUnsavedChanges)
    let session = try #require(controller.session)

    let outcome = await session.moveOnBoard(
        "Carta.md", from: try #require(VaultTag("project-presse")), to: try #require(VaultTag("project-forni"))
    )

    try #require(outcome.didWrite)
    let onDisk = try session.read("Carta.md").text
    #expect(controller.openNote?.text == onDisk)
    #expect(controller.openNote?.text.contains("project-forni") == true)
}

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

/// The Pratiche link write (`PraticaCommandActions.linkNote(_:toMessageAt:)`), which writes
/// straight through `session.write` with no catch-up of its own.
@MainActor
@Test func praticaLinkNoteWriteCatchesUpAnOpenTabOfTheMessage() async throws {
    let vault = try TemporaryVault()
    try vault.write(messageWithNoLink, to: "Rossi/2026-06-10 Richiesta offerta.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    defer { controller.close() }
    controller.openNote(at: "Rossi/2026-06-10 Richiesta offerta.md")
    try #require(!controller.openNote!.hasUnsavedChanges)
    let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
    let actions = PraticaCommandActions(pratiche: pratiche, vault: controller, navigation: Navigation())

    await actions.linkNote(
        "[[Offerta 2026]]", toMessageAt: "Rossi/2026-06-10 Richiesta offerta.md"
    )

    let onDisk = try controller.session!.read("Rossi/2026-06-10 Richiesta offerta.md").text
    #expect(controller.openNote?.text == onDisk)
    #expect(controller.openNote?.text.contains("pergamenum-mail-note:") == true)
}

/// The composer's diary mirror (`PraticaEntryComposer`'s private `mirror`, reached only
/// through `insert(_:at:)`), which writes the daily note with no catch-up of its own.
@MainActor
@Test func praticaEntryComposersDiaryMirrorCatchesUpAnOpenTabOfTheDailyNote() async throws {
    let vault = try TemporaryVault()
    try vault.write(
        "---\npergamenum-dossier: 1\n---\n\nCorpo della pratica.\n", to: "Rossi/pratica.md"
    )
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    defer { controller.close() }
    let session = try #require(controller.session)
    let timestamp = try #require(ISO8601DateFormatter().date(from: "2026-09-26T10:00:00Z"))
    let dailyPath = try await session.dailyNote(for: CalendarDate(timestamp))
    controller.openNote(at: dailyPath)
    // Made stable (not left as the column's preview tab): `insert`'s own hand-off opens
    // `pratica.md` through `openChosenNote`, which - with no stable tab requested - lands
    // in the same single preview tab the daily note above just claimed, reusing it rather
    // than adding a second one. A stable daily tab survives that hand-off untouched, which
    // is what this test needs to observe.
    let dailyTabID = try #require(controller.tabs.first { $0.note.relativePath == dailyPath }?.id)
    controller.makeStable(dailyTabID)
    try #require(!controller.openNote!.hasUnsavedChanges)
    let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
    try #require(controller.settings.pratiche.mirrorsToDailyNote)
    let composer = PraticaEntryComposer(pratiche: pratiche, vault: controller, navigation: Navigation())
    pratiche.select("Rossi", in: controller)

    await composer.insert(.note, at: timestamp)

    let onDisk = try session.read(dailyPath).text
    let dailyTab = try #require(controller.columns.flatMap(\.tabs).first { $0.id == dailyTabID })
    #expect(dailyTab.note.text == onDisk, "il diario aperto deve allinearsi senza chiamate esplicite")
}

/// The Plaud re-import write (`RecordingsController.importAccepted`'s phase 1), driven
/// directly rather than through the live loopback service - `FakePlaudService` stands in
/// for it, per the plan's own instruction for a writer reachable only via its live service.
@MainActor
@Test func plaudReimportWriteCatchesUpAnOpenTabOfTheRecordingNote() async throws {
    let vault = try TemporaryVault()
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    defer { controller.close() }
    let fake = FakePlaudService()
    let suiteName = "VaultControllerLandedChangeTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let sut = RecordingsController(service: fake, vault: controller, defaults: defaults, isTestHost: false)
    func proposal(_ transcript: String) -> PlaudProposal {
        PlaudProposal(
            recording: PlaudProposalRecording(
                id: "rec-1", name: "Riunione", recordedAt: "2026-09-04T11:48:07", durationMs: 60_000
            ),
            recordingKind: .meeting,
            themes: [],
            transcript: PlaudTranscript(language: "it", text: transcript, speakers: ["Speaker 1"]),
            warnings: [],
            generatedAt: "2026-09-05T07:55:24.906Z"
        )
    }

    // First import creates the note; a tab opened on it afterwards is what a second
    // import - the re-import this test names, with different transcript text so the
    // second write actually changes the bytes - has to catch up.
    await sut.importAccepted(
        recordingID: "rec-1", proposal: proposal("Speaker 1: prova."), acceptedTaskIDs: [], speakerRenames: [:]
    )
    let notePath = try #require(
        sut.ledger.recordings["rec-1"]?.notePath, "il primo import deve aver registrato il percorso della nota"
    )
    controller.openNote(at: notePath)
    try #require(!controller.openNote!.hasUnsavedChanges)

    await sut.importAccepted(
        recordingID: "rec-1", proposal: proposal("Speaker 1: prova rivista dopo il ri-processamento."),
        acceptedTaskIDs: [], speakerRenames: [:]
    )

    let onDisk = try controller.session!.read(notePath).text
    #expect(controller.openNote?.text == onDisk, "il ri-import deve allineare la nota aperta senza chiamate esplicite")
}
