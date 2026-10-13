import Foundation
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0085 §D8, plan docs/plans/pg-387-n4-birth-of-note.md, Task 4 - R-13, R-14:
// the controller side of «Estrai in una nota». `beginExtraction` builds the draft from the focused
// tab's selection; `extract(_:as:savingFirst:)` saves a dirty source first, re-reads the tab after
// the `await`, re-verifies the text at the range, then calls the session door; the half-done
// outcome (the new note kept, the source write refused) reaches the caller unthrown.

private let sourcePath = "Progetti/Sorgente.md"

private let source = """
---
date: 2026-10-01
tags:
  - type-note
  - topic-x
---

Prima riga del pensiero
Seconda riga

Ultimo paragrafo.
"""

@MainActor
private func opened(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    try vault.write(source, to: sourcePath)
    try FileManager.default.createDirectory(
        at: vault.root.appending(path: "Altro", directoryHint: .isDirectory), withIntermediateDirectories: true
    )
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNote(at: sourcePath)
    return controller
}

private func selection(of fragment: String, in text: String = source) -> NSRange {
    (text as NSString).range(of: fragment)
}

private func disk(_ path: String, in root: URL) throws -> String {
    try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

private func exists(_ path: String, in root: URL) -> Bool {
    FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false))
}

@MainActor
private func beginDraft(
    _ controller: VaultController, selecting fragment: String = "Prima riga del pensiero\nSeconda riga"
) throws -> VaultController.ExtractionDraft {
    controller.recordSelection(selection(of: fragment, in: try #require(controller.openNote).text), inColumn: 0)
    try #require(controller.beginExtraction(), "a selection should begin an extraction")
    return try #require(controller.extraction)
}

// MARK: - beginExtraction (R-13)

@MainActor
@Test func aSelectionBuildsTheDraftFromTheTabTheFolderAndTheFirstLine() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)

    let draft = try beginDraft(controller)

    #expect(draft.sourcePath == sourcePath)
    #expect(draft.folder == "Progetti", "the folder defaults to the source note's") // R-13
    #expect(draft.text == "Prima riga del pensiero\nSeconda riga")
    #expect(draft.range == selection(of: "Prima riga del pensiero\nSeconda riga"))
    #expect(draft.title == "Prima riga del pensiero", "the title is derived from the first line") // R-13
    #expect(draft.tabID == controller.focusedTab?.id)
    #expect(!draft.sourceIsDirty)
    controller.close()
}

@MainActor
@Test func withoutASelectionThereIsNothingToExtract() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)

    #expect(controller.beginExtraction() == false) // R-13: enabled by a non-empty selection
    #expect(controller.extraction == nil)
    controller.close()
}

@MainActor
@Test func aCollapsedSelectionAfterASelectionThereIsNothingToExtractEither() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    controller.recordSelection(selection(of: "Seconda riga"), inColumn: 0)
    controller.recordSelection(nil, inColumn: 0)

    #expect(controller.beginExtraction() == false)
    #expect(controller.extraction == nil)
    controller.close()
}

@MainActor
@Test func aDirtySourceMarksTheDraftSoTheButtonReadsSalvaEdEstrai() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    var note = try #require(controller.openNote)
    note.text += "\nUna riga non salvata."
    controller.replaceOpenNote(note)

    let draft = try beginDraft(controller)

    #expect(draft.sourceIsDirty) // R-14, ADR-0085 §D8 (G2)
    controller.close()
}

// MARK: - extract (R-13, R-14)

@MainActor
@Test func aCleanExtractLeavesTheSourceTabHoldingTheLinkWithNoPromptAndOpensNothing() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    let draft = try beginDraft(controller)
    let tabsBefore = controller.columns.flatMap(\.tabs).map(\.note.relativePath)

    let outcome = try await controller.extract(
        draft, as: NoteComposition(title: "Titolo estratto", folder: "Altro", body: draft.text), savingFirst: false
    )

    #expect(outcome.created.path == "Altro/Titolo estratto.md") // R-13
    guard case .replaced = outcome.source else {
        Issue.record("expected the source to be replaced, got \(outcome.source)")
        return
    }
    #expect(NoteDocument.parse(try disk("Altro/Titolo estratto.md", in: vault.root)).body.contains("Seconda riga"))
    let onDisk = try disk(sourcePath, in: vault.root)
    #expect(onDisk.contains("[[Titolo estratto]]")) // R-13
    #expect(!onDisk.contains("Prima riga del pensiero"))
    let tab = try #require(controller.columns.flatMap(\.tabs).first { $0.note.relativePath == sourcePath })
    #expect(tab.note.text == onDisk, "the source tab adopted the landed text (ADR-0067)")
    #expect(tab.note.externalChangePending == nil, "and raised no conflict prompt")
    #expect(controller.columns.flatMap(\.tabs).map(\.note.relativePath) == tabsBefore, "the new note is not opened")
    controller.close()
}

@MainActor
@Test func aDirtySourceIsSavedFirstThenTheTabIsReReadAndTheExtractGoesThrough() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    var note = try #require(controller.openNote)
    note.text += "\nUna riga non salvata."
    controller.replaceOpenNote(note)
    let draft = try beginDraft(controller)
    try #require(draft.sourceIsDirty)

    let outcome = try await controller.extract(
        draft, as: NoteComposition(title: "Titolo estratto", folder: "Altro", body: draft.text), savingFirst: true
    )

    guard case .replaced = outcome.source else {
        Issue.record("expected the source to be replaced, got \(outcome.source)")
        return
    }
    let onDisk = try disk(sourcePath, in: vault.root)
    #expect(onDisk.contains("Una riga non salvata."), "the unsaved edit was saved, not lost") // R-14
    #expect(onDisk.contains("[[Titolo estratto]]"))
    #expect(controller.openNote?.text == onDisk)
    #expect(controller.openNote?.hasUnsavedChanges == false)
    #expect(controller.openNote?.externalChangePending == nil)
    controller.close()
}

@MainActor
@Test func ifTheTextAtTheRangeChangedWhileSavingTheExtractIsRefusedAndCreatesNothing() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    let draft = try beginDraft(controller)
    // The person edits inside the selection after the sheet opened: the buffer is now dirty and
    // the text at the draft's range is no longer the text the sheet showed.
    var note = try #require(controller.openNote)
    note.text = note.text.replacingOccurrences(of: "Seconda riga", with: "Terza riga")
    controller.replaceOpenNote(note)

    var refused = false
    do {
        _ = try await controller.extract(
            draft, as: NoteComposition(title: "Titolo estratto", folder: "Altro", body: draft.text), savingFirst: true
        )
    } catch {
        refused = true
    }

    #expect(refused, "the range is re-verified after the save (ADR-0043 §D7)") // R-14
    #expect(!exists("Altro/Titolo estratto.md", in: vault.root), "nothing was created")
    #expect(try !disk(sourcePath, in: vault.root).contains("[[Titolo estratto]]"))
    controller.close()
}

@MainActor
@Test func aRefusedSecondWriteReachesTheCallerAsAnOutcomeWithTheNewNoteKept() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    let draft = try beginDraft(controller)
    // The source's folder refuses a new file, so the replacement (an atomic write) fails after
    // the new note, in `Altro`, has landed. Restored in `defer` (ADR-0046 §D11).
    let sourceFolder = vault.root.appending(path: "Progetti", directoryHint: .isDirectory)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sourceFolder.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sourceFolder.path) }

    let outcome = try await controller.extract(
        draft, as: NoteComposition(title: "Titolo estratto", folder: "Altro", body: draft.text), savingFirst: false
    )

    guard case .refused(let sentence) = outcome.source else {
        Issue.record("expected the second write to be refused, got \(outcome.source)")
        return
    }
    #expect(!sentence.isEmpty) // R-14: the sheet names it
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sourceFolder.path)
    #expect(exists("Altro/Titolo estratto.md", in: vault.root), "the new note stays") // R-14
    #expect(try disk(sourcePath, in: vault.root) == source)
    controller.close()
}
