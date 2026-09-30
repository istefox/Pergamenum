import Foundation
import Testing
@testable import Pergamenum

// ADR-0071 (Contenitore) §D11, plan docs/plans/contenitore.md, Task 7 - R-16; ADR-0073 (a holder
// of unsaved state reviews itself in `QuitCoordinator`), ADR-0067 §D6 and ADR-0068 §D16 (the
// inspector reloads on the landed generation). The inspector's edit lives on the controller,
// so what the view used to lose - a description in `@State`, a hash captured before an `await`,
// a baseline that never followed «Classifica…» - is checkable without a window.

private let folder = "Contenitore/Fatture/2026"
private let scheda = "\(folder)/20260314 Fattura.md"
private let other = "\(folder)/20260315 Bolletta.md"
private let topic = Tag(namespace: .topic, value: "fatture")

@MainActor
private func harness(_ vault: borrowing TemporaryVault) async throws -> ContenitoreHarness {
    try ContenitoreFixture.seed(stem: "20260314 Fattura", in: folder, vault: vault)
    try ContenitoreFixture.seed(stem: "20260315 Bolletta", in: folder, date: "2026-03-15", vault: vault)
    return try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
}

@MainActor
private func parsed(_ path: String, in vault: borrowing TemporaryVault) throws -> NoteDocument {
    NoteDocument.parse(try ContenitoreFixture.text(path, in: vault.root))
}

// MARK: - The baseline follows the disk

@MainActor
@Test func editingTheColourAfterClassificaSucceedsOnTheClassifiedTags() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    let session = try #require(harness.vault.session)
    let contenitore = harness.contenitore
    contenitore.openEditor(for: scheda)
    let editor = try #require(contenitore.editor)
    let keyBefore = contenitore.inspectorKey(for: scheda)
    #expect(editor.draft.tags.contains(ContenitoreFixture.inbox))

    // «Classifica…» writes through its own model, as `ClassificaSheet` does.
    var sheet = try #require(ContenitoreInspectorModel(session: session, schedaPath: scheda))
    #expect(await sheet.classify(topics: [topic], type: nil) == .saved)
    #expect(contenitore.inspectorKey(for: scheda) != keyBefore, "the inspector's task id moves with the write")

    contenitore.openEditor(for: scheda) // what `.task(id:)` runs on the new key
    #expect(editor.draft.tags.contains(topic))
    #expect(!editor.draft.tags.contains(ContenitoreFixture.inbox))

    let problems = session.problems.count
    editor.draft.colour = .verde
    await editor.settle()

    #expect(editor.problem == nil, "no spurious conflict")
    #expect(session.problems.count == problems, "and no spurious recorded problem")
    let document = try parsed(scheda, in: vault)
    #expect(document.frontmatter.tags.contains(topic))
    #expect(!document.frontmatter.tags.contains(ContenitoreFixture.inbox))
    #expect(ContenitoreScheda.facts(in: document.frontmatter.foreignKeys)?.colour == .verde)
}

@MainActor
@Test func aChangeLandingUnderAnEditKeepsTheEditedFieldAndTakesTheRest() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    let session = try #require(harness.vault.session)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)
    editor.draft.description = "Sto scrivendo"

    var sheet = try #require(ContenitoreInspectorModel(session: session, schedaPath: scheda))
    #expect(await sheet.classify(topics: [topic], type: nil) == .saved)
    harness.contenitore.openEditor(for: scheda)

    #expect(editor.draft.description == "Sto scrivendo", "the unsaved edit is safe")
    #expect(editor.draft.tags.contains(topic), "the field nobody edited follows the file")
    #expect(!editor.isSettled)

    await editor.settle()

    #expect(editor.problem == nil)
    let document = try parsed(scheda, in: vault)
    #expect(document.body == "\nSto scrivendo\n")
    #expect(document.frontmatter.tags.contains(topic))
}

@MainActor
@Test func anExternalEditIsAdoptedByAnEditorWithNothingUnsaved() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)
    let external = try ContenitoreFixture.schedaText(
        fileName: "20260314 Fattura.pdf", tags: ContenitoreFixture.classified, colour: .giallo
    )
    try vault.write(external, to: scheda)

    harness.contenitore.openEditor(for: scheda)

    #expect(editor.draft.colour == .giallo)
    #expect(editor.draft.tags == ContenitoreFixture.classified)
    #expect(editor.baselineText == external)
    #expect(editor.isSettled)
}

// MARK: - Serial saves

@MainActor
@Test func twoQuickSavesRunOneAfterTheOtherAndNeitherIsRefused() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    let session = try #require(harness.vault.session)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)
    let problems = session.problems.count

    editor.draft.colour = .rosso
    editor.requestSave()
    await Task.yield() // the first save is on its way to the disk
    editor.draft.description = "Seconda modifica"
    editor.requestSave()
    await editor.settle()

    #expect(editor.problem == nil)
    #expect(session.problems.count == problems, "the second save started from the hash the first left")
    let document = try parsed(scheda, in: vault)
    #expect(document.body == "\nSeconda modifica\n")
    #expect(ContenitoreScheda.facts(in: document.frontmatter.foreignKeys)?.colour == .rosso)
    #expect(editor.isSettled)
}

// MARK: - A description survives what used to lose it (ADR-0073)

@MainActor
@Test func settleWritesTheDescriptionAndSaysNothingIsOwedAfterwards() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)
    #expect(!harness.contenitore.hasUnsettledEdits)

    editor.draft.description = "Bolletta di marzo"
    #expect(harness.contenitore.hasUnsettledEdits)

    await harness.contenitore.settleEditing()

    #expect(!harness.contenitore.hasUnsettledEdits)
    #expect(try parsed(scheda, in: vault).body == "\nBolletta di marzo\n")
}

@MainActor
@Test func aDateTypedAndNotCommittedIsCommittedBySettle() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)

    editor.dateText = "2026-04-02"
    #expect(harness.contenitore.hasUnsettledEdits)
    await harness.contenitore.settleEditing()

    #expect(try parsed(scheda, in: vault).frontmatter.date == CalendarDate(iso: "2026-04-02"))
}

@MainActor
@Test func clickingAnotherRowHandsTheEditToTheBackgroundAndTheQuitCanWaitForIt() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    let contenitore = harness.contenitore
    contenitore.selection = scheda
    contenitore.openEditor(for: scheda)
    let editor = try #require(contenitore.editor)
    editor.draft.description = "Non ancora scritta"

    contenitore.selection = other

    #expect(contenitore.editor == nil, "the inspector has let go of it")
    #expect(contenitore.hasUnsettledEdits, "but it is still owed, and the quit asks about it")
    await contenitore.settleEditing()
    #expect(!contenitore.hasUnsettledEdits)
    #expect(try parsed(scheda, in: vault).body == "\nNon ancora scritta\n")
}

@MainActor
@Test func aRenameSettlesTheDescriptionBeforeThePairMoves() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)
    editor.draft.description = "Scritta prima del cambio nome"

    #expect(await harness.actions.rename(scheda, to: "20260314 Rinominata"))

    let renamed = "\(folder)/20260314 Rinominata.md"
    #expect(try parsed(renamed, in: vault).body == "\nScritta prima del cambio nome\n")
}

// MARK: - A write that fails keeps the draft owed

@MainActor
@Test func aWriteThatFailsKeepsTheDraftOwedAndTheNextSettleRetriesIt() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)
    editor.draft.description = "Non deve andare persa"
    let directory = vault.root.appending(path: folder, directoryHint: .isDirectory).path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory) }

    await editor.settle()

    #expect(editor.problem?.hasPrefix("Modifica non salvata") == true)
    #expect(editor.draft.description == "Non deve andare persa", "the typed text is not wiped")
    #expect(!editor.isSettled, "and it is still owed, so the quit does not go without it")
    #expect(harness.contenitore.hasUnsettledEdits)

    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory)
    await editor.settle()

    #expect(editor.problem == nil)
    #expect(editor.isSettled)
    #expect(try parsed(scheda, in: vault).body == "\nNon deve andare persa\n")
}

@MainActor
@Test func anEditorWhoseSaveFailedComesBackWhenItsSchedaIsSelectedAgain() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    let contenitore = harness.contenitore
    contenitore.selection = scheda
    contenitore.openEditor(for: scheda)
    let editor = try #require(contenitore.editor)
    editor.draft.description = "Ancora dovuta"
    let directory = vault.root.appending(path: folder, directoryHint: .isDirectory).path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory) }
    await editor.settle()
    contenitore.selection = other
    await lettingTheRetireTaskRun(after: editor)

    #expect(contenitore.firstUnsettledSchedaPath == scheda)
    contenitore.selection = scheda
    contenitore.openEditor(for: scheda)

    #expect(contenitore.editor === editor, "the owed draft is shown again, not read afresh over")
    #expect(contenitore.editor?.draft.description == "Ancora dovuta")
}

/// Lets the background task `retireEditor()` starts run to its end: the editor's own retry has
/// ended (it reports a problem when it has) and the main actor has been handed back to that task
/// enough times for its clean-up to have happened, if it was going to.
@MainActor
private func lettingTheRetireTaskRun(after editor: ContenitoreEditor) async {
    for _ in 0..<2000 where editor.problem == nil { try? await Task.sleep(for: .milliseconds(5)) }
    for _ in 0..<50 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(100))
}

@MainActor
@Test func aRetiredEditorWhoseWriteFailedIsNotForgottenAndTheQuitStillSeesIt() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    let contenitore = harness.contenitore
    contenitore.selection = scheda
    contenitore.openEditor(for: scheda)
    let editor = try #require(contenitore.editor)
    editor.draft.description = "Non deve andare persa"
    let directory = vault.root.appending(path: folder, directoryHint: .isDirectory).path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory) }

    contenitore.selection = other // retires the editor; its task writes, fails, and must keep it
    await lettingTheRetireTaskRun(after: editor)

    #expect(contenitore.hasUnsettledEdits, "the failed write is still owed, so the quit does not go through")
    #expect(contenitore.firstUnsettledSchedaPath == scheda)
    #expect(editor.draft.description == "Non deve andare persa")
}

// MARK: - A date that cannot be committed is not owed

@MainActor
@Test func aDateThatCannotBeCommittedIsNotOwedAndDoesNotHoldTheQuit() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)

    for text in ["2026-13-45", "", "ieri"] {
        editor.dateText = text
        await harness.contenitore.settleEditing()

        #expect(editor.isSettled, "«\(text)» is not owed")
        #expect(!harness.contenitore.hasUnsettledEdits)
        #expect(editor.dateText == "2026-03-14", "the field goes back to the draft's date")
        #expect(try parsed(scheda, in: vault).frontmatter.date == CalendarDate(iso: "2026-03-14"))
    }
    editor.dateText = "2026-13-45"
    await editor.settle()
    #expect(editor.problem?.hasPrefix("Data non valida") == true, "and the person is told why")
}

@MainActor
@Test func anUncommittableDateTextDoesNotCountAsAnEditEvenBeforeSettle() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)

    editor.dateText = ""

    #expect(editor.isSettled)
    #expect(!harness.contenitore.hasUnsettledEdits)
}

// MARK: - A verb does not move a pair whose edit could not be written

@MainActor
private func failingWrite(in vault: borrowing TemporaryVault, on path: String) throws -> () -> Void {
    let directory = vault.root.appending(path: path, directoryHint: .isDirectory).path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory)
    return { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory) }
}

@MainActor
@Test func aRenameIsRefusedWhileTheSchedasEditCouldNotBeWrittenAndTheDraftSurvives() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    let session = try #require(harness.vault.session)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)
    editor.draft.description = "Non deve andare persa"
    let restore = try failingWrite(in: vault, on: folder)
    defer { restore() }

    #expect(await harness.actions.rename(scheda, to: "20260314 Rinominata") == false)

    #expect(session.problems.contains(ContenitoreCommandActions.owedEditSentence), "refused for the owed edit")
    #expect(harness.contenitore.editor === editor)
    #expect(editor.draft.description == "Non deve andare persa")
    #expect(harness.contenitore.hasUnsettledEdits)
}

@MainActor
@Test func aTrashAndAMoveAreRefusedWhileTheSchedasEditCouldNotBeWritten() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    let session = try #require(harness.vault.session)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)
    editor.draft.description = "Non deve andare persa"
    let restore = try failingWrite(in: vault, on: folder)
    defer { restore() }

    #expect(await harness.actions.trash(scheda) == nil)
    #expect(await harness.actions.move(scheda, toContainer: "Contenitore/Utenze") == false)

    #expect(session.problems.filter { $0 == ContenitoreCommandActions.owedEditSentence }.count == 2)
    #expect(FileManager.default.fileExists(atPath: vault.root.appending(path: scheda).path(percentEncoded: false)))
    #expect(editor.draft.description == "Non deve andare persa")
}

@MainActor
@Test func aContainerMoveIsRefusedWhileAnEditInsideItCouldNotBeWritten() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    let session = try #require(harness.vault.session)
    #expect(await harness.actions.createContainer(named: "Utenze", in: "Contenitore") == nil)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)
    editor.draft.description = "Non deve andare persa"
    // The year folder refuses the write; the container above it could still be moved, which is
    // what must not happen.
    let restore = try failingWrite(in: vault, on: folder)
    defer { restore() }

    await harness.actions.moveContainer("Contenitore/Fatture", into: "Contenitore/Utenze", undo: nil)

    #expect(session.problems.contains(ContenitoreCommandActions.owedEditSentence))
    #expect(FileManager.default.fileExists(atPath: vault.root.appending(path: scheda).path(percentEncoded: false)),
            "the container did not move")
    #expect(editor.draft.description == "Non deve andare persa")
    #expect(harness.contenitore.hasUnsettledEdits)
}

@MainActor
@Test func aContainerRenameIsRefusedWhileAnEditInsideItCouldNotBeWritten() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)
    editor.draft.description = "Non deve andare persa"
    let restore = try failingWrite(in: vault, on: folder)
    defer { restore() }

    let sentence = await harness.actions.renameContainer("Contenitore/Fatture", to: "Utenze")

    #expect(sentence?.hasPrefix("Sottocontenitore non rinominato") == true)
    #expect(FileManager.default.fileExists(atPath: vault.root.appending(path: scheda).path(percentEncoded: false)))
    #expect(editor.draft.description == "Non deve andare persa")
}

@MainActor
@Test func aContainerTrashIsRefusedWhileAnEditInsideItCouldNotBeWritten() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    let session = try #require(harness.vault.session)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)
    editor.draft.description = "Non deve andare persa"
    let restore = try failingWrite(in: vault, on: folder)
    defer { restore() }

    await harness.actions.trashContainer("Contenitore/Fatture")

    #expect(session.problems.contains(ContenitoreCommandActions.owedEditSentence))
    #expect(FileManager.default.fileExists(atPath: vault.root.appending(path: scheda).path(percentEncoded: false)),
            "the container was not trashed")
    #expect(editor.draft.description == "Non deve andare persa")
    #expect(harness.contenitore.hasUnsettledEdits)
}

@MainActor
@Test func aVaultChangeNamesAnEditItCouldNotWriteInsteadOfDroppingItSilently() async throws {
    let vault = try TemporaryVault()
    let second = try TemporaryVault()
    let harness = try await harness(vault)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)
    editor.draft.description = "Non deve sparire in silenzio"
    let restore = try failingWrite(in: vault, on: folder)
    defer { restore() }

    await harness.vault.open(second.root)
    await harness.contenitore.start()
    defer { harness.contenitore.stop() }

    let session = try #require(harness.vault.session)
    #expect(session.problems.contains(ContenitoreController.lostEditSentence(for: scheda)))
    #expect(harness.contenitore.editor == nil)
    #expect(!harness.contenitore.hasUnsettledEdits, "the old vault's edit does not hold the new vault's quit")
}

@MainActor
@Test func aRefusedSaveOnAVanishedSchedaKeepsTheDraft() async throws {
    let vault = try TemporaryVault()
    let harness = try await harness(vault)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)
    editor.draft.description = "Ancora mia"
    try FileManager.default.removeItem(at: vault.root.appending(path: scheda))

    await editor.settle()

    #expect(editor.draft.description == "Ancora mia", "not replaced by the last text read")
    #expect(!editor.isSettled)
}
