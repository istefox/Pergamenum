import Foundation
import Testing
@testable import Pergamenum

// PG-223 / #461, `docs/adr/0058-in-process-writes-reach-every-tab.md`. A write this app makes
// itself is self-hashed, so `VaultSession.reconcile` drops it when FSEvents reports it back
// (ADR-0001 §D3.3): the watcher never tells a tab about it, and the caller's catch-up is the
// tab's only chance to learn of it. `syncOpenNote(with:)`, `saveOpenNote()`, `restoreVersion(_:)`
// and `addStructuralLink` gave that chance to the focused tab only. A copy of the note in a
// background tab or in the other column (ADR-0012 §D4) stayed stale - a clean one reverted the
// write on its next save, a dirty one was never asked (ADR-0001 §D3.4).
//
// No timer, no sleep, no gate: where the timing of an `await` matters, the test calls the half
// that runs after it directly (ADR-0058 §D3; ADR-0046 §D11).

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-09-24\ntags:\n  - type-note\n---\n\n\(body)\n"
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
/// one a focused-only catch-up cannot see.
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

// MARK: §D1 - one per-buffer rule

@Test func catchUpOnADirtyBufferRaisesThePromptAndLeavesBothTextsAlone() {
    var buffer = VaultController.OpenNote(
        relativePath: "A.md", title: "A", text: "mine", savedText: "disk"
    )

    buffer.catchUp(to: "incoming")

    #expect(buffer.externalChangePending == "incoming")
    #expect(buffer.text == "mine")
    #expect(buffer.savedText == "disk")
}

@Test func catchUpOnACleanBufferAdoptsTheIncomingText() {
    var buffer = VaultController.OpenNote(
        relativePath: "A.md", title: "A", text: "disk", savedText: "disk"
    )

    buffer.catchUp(to: "incoming")

    #expect(buffer.text == "incoming")
    #expect(buffer.savedText == "incoming")
    #expect(buffer.externalChangePending == nil)
}

@Test func catchUpOnACleanBufferClearsAStalePrompt() {
    // Clean while a prompt is still pending: the person undid their edits back to `savedText`
    // after the banner appeared. Once the buffer has the newest text, the older one has
    // nothing left to ask about (ADR-0058 §D1, last paragraph).
    var buffer = VaultController.OpenNote(
        relativePath: "A.md", title: "A", text: "disk", savedText: "disk",
        externalChangePending: "stale"
    )

    buffer.catchUp(to: "incoming")

    #expect(buffer.text == "incoming")
    #expect(buffer.externalChangePending == nil)
}

// MARK: §D2 - `syncOpenNote(with:)` reaches every tab showing the path

@MainActor
@Test func syncOpenNoteRaisesThePromptOnADirtyTabInTheOtherColumn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controllerWithANoteInBothColumns(vault)
    defer { controller.close() }
    controller.updateOpenNoteText(note("A, non salvato."))
    controller.focusColumn(1)
    try #require(controller.focusedColumnIndex == 1)
    let result = VaultSession.WriteResult(path: "A.md", text: note("A, scritto dall'app."))

    controller.syncOpenNote(with: result)

    let dirty = try tab(showing: "A.md", in: controller.columns[0])
    #expect(dirty.note.externalChangePending == result.text)
    #expect(dirty.note.text == note("A, non salvato."), "il testo non salvato non viene toccato")
}

@MainActor
@Test func syncOpenNoteCatchesUpACleanTabInTheOtherColumn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controllerWithANoteInBothColumns(vault)
    defer { controller.close() }
    let result = VaultSession.WriteResult(path: "A.md", text: note("A, scritto dall'app."))

    controller.syncOpenNote(with: result)

    let background = try tab(showing: "A.md", in: controller.columns[1])
    #expect(background.note.text == result.text)
    #expect(background.note.savedText == result.text)
    #expect(background.note.externalChangePending == nil)
}

@MainActor
@Test func syncOpenNoteRaisesThePromptOnADirtyBackgroundTabInTheSameColumn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    defer { controller.close() }
    controller.openNote(at: "A.md")
    let backgroundID = try #require(controller.focusedTab?.id)
    controller.openNoteInNewTab(at: "B.md")
    try #require(controller.focusedTab?.note.relativePath == "B.md")
    controller.updateTab(backgroundID) { $0.note.text = note("A, non salvato in secondo piano.") }
    let result = VaultSession.WriteResult(path: "A.md", text: note("A, scritto dall'app."))

    controller.syncOpenNote(with: result)

    let background = try #require(controller.tabs.first { $0.id == backgroundID })
    #expect(background.note.externalChangePending == result.text)
    #expect(background.note.text == note("A, non salvato in secondo piano."))
}

// Guard, green before and after the fix: a write to one path leaves a tab on another alone.
@MainActor
@Test func syncOpenNoteLeavesATabShowingADifferentPathAlone() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    defer { controller.close() }
    controller.openNote(at: "B.md")
    controller.updateOpenNoteText(note("B, non salvato."))
    controller.splitEditor()
    let before = controller.columns.map { $0.tabs.map(\.note) }
    try #require(before.allSatisfy { $0.allSatisfy { $0.relativePath == "B.md" } })

    controller.syncOpenNote(with: VaultSession.WriteResult(path: "A.md", text: note("A, scritto dall'app.")))

    #expect(controller.columns.map { $0.tabs.map(\.note) } == before)
}

@MainActor
@Test func togglingATaskCatchesUpItsNoteOpenOnlyInTheOtherColumn() async throws {
    let vault = try TemporaryVault()
    try vault.write(note("- [ ] Da fare"), to: "Compiti.md")
    let controller = try await controller(vault)
    defer { controller.close() }
    // The first column shows an unrelated note throughout, so refocusing it genuinely leaves
    // the task's note behind in the second one.
    controller.openNote(at: "B.md")
    controller.splitEditor()
    controller.openNote(at: "Compiti.md")
    controller.focusColumn(0)
    try #require(controller.focusedTab?.note.relativePath == "B.md")
    try #require(!controller.columns[0].tabs.contains { $0.note.relativePath == "Compiti.md" })
    let task = try #require(controller.index.allTasks.first { $0.text == "Da fare" })

    #expect(await controller.toggle(task))

    let background = try tab(showing: "Compiti.md", in: controller.columns[1])
    #expect(background.note.text.contains("- [x] Da fare"))
    #expect(!background.note.hasUnsavedChanges)
}

// MARK: §D3 - `saveOpenNote()` reaches the other copies, and finds its own tab by id

@MainActor
@Test func savingCatchesUpACleanCopyInTheOtherColumn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controllerWithANoteInBothColumns(vault)
    defer { controller.close() }
    let saved = note("A, salvato dalla prima colonna.")
    controller.updateOpenNoteText(saved)

    await controller.saveOpenNote()

    let copy = try tab(showing: "A.md", in: controller.columns[1])
    #expect(copy.note.text == saved)
    #expect(copy.note.savedText == saved)
    #expect(controller.openNote?.hasUnsavedChanges == false)
}

@MainActor
@Test func savingRaisesThePromptOnADirtyCopyInTheOtherColumn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controllerWithANoteInBothColumns(vault)
    defer { controller.close() }
    controller.focusColumn(1)
    controller.updateOpenNoteText(note("A, non salvato nella seconda colonna."))
    controller.focusColumn(0)
    let saved = note("A, salvato dalla prima colonna.")
    controller.updateOpenNoteText(saved)

    await controller.saveOpenNote()

    let copy = try tab(showing: "A.md", in: controller.columns[1])
    #expect(copy.note.externalChangePending == saved)
    #expect(copy.note.text == note("A, non salvato nella seconda colonna."))
    #expect(controller.openNote?.hasUnsavedChanges == false)
    #expect(controller.openNote?.externalChangePending == nil, "il proprio salvataggio non è un conflitto")
}

@MainActor
@Test func theSaveFindsItsWriterByIdAfterTheFocusMovedToAnotherNote() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    defer { controller.close() }
    controller.openNote(at: "A.md")
    let written = note("A, salvato.")
    controller.updateOpenNoteText(written)
    let writerID = try #require(controller.focusedTab?.id)
    // The focus moves during the save's suspension.
    controller.openNoteInNewTab(at: "B.md")
    let focusedBefore = try #require(controller.focusedTab)
    try #require(focusedBefore.id != writerID)

    controller.syncOpenNote(with: VaultSession.WriteResult(path: "A.md", text: written), savedBy: writerID)

    let writer = try #require(controller.tabs.first { $0.id == writerID })
    #expect(!writer.note.hasUnsavedChanges)
    #expect(writer.note.externalChangePending == nil)
    #expect(controller.focusedTab?.id == focusedBefore.id)
    #expect(controller.focusedTab?.note.relativePath == "B.md")
    #expect(controller.focusedTab?.note.text == note("B."))
}

@MainActor
@Test func textTypedIntoTheWriterAfterTheWriteStaysUnsaved() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    defer { controller.close() }
    controller.openNote(at: "A.md")
    let written = note("A, salvato.")
    controller.updateOpenNoteText(written)
    let writerID = try #require(controller.focusedTab?.id)
    // Typed during the save's suspension, after the text above was handed to the write.
    let newer = note("A, salvato e poi ancora modificato.")
    controller.updateOpenNoteText(newer)

    controller.syncOpenNote(with: VaultSession.WriteResult(path: "A.md", text: written), savedBy: writerID)

    let writer = try #require(controller.focusedTab)
    #expect(writer.note.text == newer)
    #expect(writer.note.savedText == written)
    #expect(writer.note.hasUnsavedChanges)
    #expect(writer.note.externalChangePending == nil)
}

// MARK: §D4 - `restoreVersion(_:)` reaches every copy

@MainActor
@Test func restoringCatchesUpACleanCopyInTheOtherColumn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controllerWithANoteInBothColumns(vault)
    defer { controller.close() }
    // A literal no tab holds, so the test cannot pass by accident: `restoreVersion` writes
    // whatever text it is given.
    let restored = note("A, versione ripristinata.")

    await controller.restoreVersion(restored)

    let copy = try tab(showing: "A.md", in: controller.columns[1])
    #expect(copy.note.text == restored)
    #expect(copy.note.savedText == restored)
    #expect(controller.openNote?.text == restored)
}

// MARK: §D5 - `addStructuralLink` catches up both notes and discards nothing

@MainActor
@Test func linkingFromADirtySourceKeepsTheEditsAndRaisesThePrompt() async throws {
    let vault = try TemporaryVault()
    try vault.write(linkableNote, to: "Origine.md")
    try vault.write(linkableNote, to: "03 Risorse/Destinazione.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    defer { controller.close() }
    controller.openNote(at: "Origine.md")
    let unsaved = linkableNote + "\n\nNon salvato."
    controller.updateOpenNoteText(unsaved)

    #expect(await controller.addStructuralLink(
        from: "Origine.md", to: "Destinazione",
        reason: "usa i dati", reverseReason: "fornisce i dati"
    ))

    let onDisk = try String(contentsOf: vault.root.appending(path: "Origine.md"), encoding: .utf8)
    try #require(onDisk.contains("- [[Destinazione]] — usa i dati"))
    #expect(controller.openNote?.text == unsaved, "le modifiche non salvate non vengono scartate")
    #expect(controller.openNote?.externalChangePending == onDisk)
}

@MainActor
@Test func linkingCatchesUpTheTargetOpenInTheOtherColumn() async throws {
    let vault = try TemporaryVault()
    try vault.write(linkableNote, to: "Origine.md")
    try vault.write(linkableNote, to: "03 Risorse/Destinazione.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    defer { controller.close() }
    controller.openNote(at: "Origine.md")
    controller.splitEditor()
    controller.openNote(at: "03 Risorse/Destinazione.md")
    controller.focusColumn(0)
    try #require(controller.focusedTab?.note.relativePath == "Origine.md")

    #expect(await controller.addStructuralLink(
        from: "Origine.md", to: "Destinazione",
        reason: "usa i dati", reverseReason: "fornisce i dati"
    ))

    let target = try tab(showing: "03 Risorse/Destinazione.md", in: controller.columns[1])
    #expect(target.note.text.contains("- [[Origine]] — fornisce i dati"))
    #expect(!target.note.hasUnsavedChanges)
}
