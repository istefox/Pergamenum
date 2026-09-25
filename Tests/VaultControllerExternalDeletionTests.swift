import Foundation
import Testing
@testable import Pergamenum

// ADR-0061 (external deletion reaches the editor tabs and the Diario pane), plan
// `docs/plans/pg-234-external-deletion.md` Task 2, tests 9-18. R-03 (a clean tab closes, in
// every column), R-04/§D3 (a dirty tab is asked, newest wins), R-05/R-06 (the two verbs), the
// banner's copy (R-04), and §D6's move/trash ordering guards (R-09).
//
// No sleep, no timer, no racing two tasks (ADR-0043 §D9). `controller(_:)` stops the watcher
// `open` starts right after building, so the only reconciliation a test sees is the one it calls
// itself (`VaultController.swift:120`). A deletion is always `TemporaryVault.remove(_:)`, never a
// session door, so it always reaches `reconcile` as a real external change.

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-09-25\ntags:\n  - type-note\n---\n\n\(body)\n"
}

@MainActor
private func controller(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    try vault.write(note("A."), to: "A.md")
    try vault.write(note("B."), to: "B.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.watcher?.stop()
    controller.watcher = nil
    return controller
}

// MARK: 9-10 - R-03, a clean tab closes in every column, background tabs included

/// Red on today's code: the missing-path branch reports nothing, so no `ExternalChange` ever
/// reaches `reconcile`, and even once it does, `catchUp(to: .deleted)`'s placeholder body
/// changes nothing and `reconcile` closes no tab for a `.vanished` result yet (Tasks 3-4).
@MainActor
@Test func aCleanTabOnADeletedNoteClosesInEveryColumn() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    defer { controller.close() }
    controller.openNote(at: "A.md")
    controller.splitEditor()
    try #require(controller.columns[0].tabs.contains { $0.note.relativePath == "A.md" })
    try #require(controller.columns[1].tabs.contains { $0.note.relativePath == "A.md" })

    try vault.remove("A.md")
    await controller.reconcile(["A.md"])

    #expect(!controller.columns[0].tabs.contains { $0.note.relativePath == "A.md" })
    #expect(!controller.columns[1].tabs.contains { $0.note.relativePath == "A.md" })
    #expect(!controller.closedTabPaths.contains("A.md"))
    #expect(!controller.recentNotePaths.contains("A.md"))
}

/// Red on today's code, same gap as above: a background, clean tab must close too, leaving the
/// active tab exactly where it was.
@MainActor
@Test func aCleanBackgroundTabClosesTooLeavingTheActiveTabAlone() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    defer { controller.close() }
    controller.openNoteInNewTab(at: "A.md")
    controller.openNoteInNewTab(at: "B.md")
    try #require(controller.focusedTab?.note.relativePath == "B.md")
    try #require(controller.tabs.contains { $0.note.relativePath == "A.md" })

    try vault.remove("A.md")
    await controller.reconcile(["A.md"])

    #expect(controller.focusedTab?.note.relativePath == "B.md")
    #expect(!controller.tabs.contains { $0.note.relativePath == "A.md" })
}

// MARK: 11-12 - R-04/§D3, a dirty tab is asked and newest wins

/// Red on today's code: `catchUp(to: .deleted)`'s placeholder returns `.adopted` and touches
/// nothing, so `externalChangePending` never becomes `.deleted`.
@MainActor
@Test func aDirtyTabIsAskedAndKeepsItsText() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    defer { controller.close() }
    controller.openNote(at: "A.md")
    controller.updateOpenNoteText(note("A, non salvato."))
    try #require(controller.openNote?.hasUnsavedChanges == true)

    try vault.remove("A.md")
    await controller.reconcile(["A.md"])

    #expect(controller.openNote?.externalChangePending == .deleted)
    #expect(controller.openNote?.text == note("A, non salvato."))
    #expect(controller.openNote?.relativePath == "A.md", "la tab resta aperta")
}

/// Red on today's code: the missing-path branch reports nothing, so the pending value never
/// moves from `.text(changed)` to `.deleted`, let alone back to `.text(recreated)`.
@MainActor
@Test func newestWinsOnADirtyBuffer() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    defer { controller.close() }
    controller.openNote(at: "A.md")
    controller.updateOpenNoteText(note("A, non salvato."))

    let changed = note("A, cambiata da un altro scrittore.")
    try vault.write(changed, to: "A.md")
    await controller.reconcile(["A.md"])
    try #require(controller.openNote?.externalChangePending == .text(changed))

    try vault.remove("A.md")
    await controller.reconcile(["A.md"])
    #expect(controller.openNote?.externalChangePending == .deleted)

    let recreated = note("A, ricreata.")
    try vault.write(recreated, to: "A.md")
    await controller.reconcile(["A.md"])
    #expect(controller.openNote?.externalChangePending == .text(recreated))
}

// MARK: 13-14 - R-06/R-05, the two verbs on a `.deleted` pending

/// Red on today's code: reaching a `.deleted` pending at all needs Tasks 3-4, so the `#require`
/// above `acceptExternalChange()` already fails.
@MainActor
@Test func discardAndDeleteClosesTheTabWithoutWriting() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    defer { controller.close() }
    controller.openNote(at: "A.md")
    controller.updateOpenNoteText(note("A, non salvato."))
    try vault.remove("A.md")
    await controller.reconcile(["A.md"])
    try #require(controller.openNote?.externalChangePending == .deleted)

    controller.acceptExternalChange()

    #expect(!controller.tabs.contains { $0.note.relativePath == "A.md" })
    #expect(!FileManager.default.fileExists(atPath: vault.root.appending(path: "A.md").path(percentEncoded: false)))
    #expect(!controller.closedTabPaths.contains("A.md"))
}

/// Red on today's code: same reachability gap, plus `acceptExternalChange`/`keepLocalVersion`
/// still switch only on `.text` (Task 5).
@MainActor
@Test func keepLocalVersionThenSaveRecreatesTheFile() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    defer { controller.close() }
    controller.openNote(at: "A.md")
    let kept = note("A, tenuta.")
    controller.updateOpenNoteText(kept)
    try vault.remove("A.md")
    await controller.reconcile(["A.md"])
    try #require(controller.openNote?.externalChangePending == .deleted)

    controller.keepLocalVersion()

    #expect(controller.openNote?.externalChangePending == nil)
    #expect(controller.openNote?.hasUnsavedChanges == true)

    await controller.saveOpenNote()

    let onDisk = try String(contentsOf: vault.root.appending(path: "A.md"), encoding: .utf8)
    #expect(onDisk == kept)
    #expect(controller.openNote?.externalChangePending == nil)
    #expect(controller.openNote?.hasUnsavedChanges == false)
}

/// Red on today's code: today's `keepLocalVersion()` only clears the pending value, it never
/// sets `savedText = ""` (ADR-0061 §D5), so a buffer undone back to its original text reads
/// clean both before and after the call - there is nothing left for a save to recreate from.
@MainActor
@Test func aBufferUndoneToCleanCanStillBeKeptAndSaved() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    defer { controller.close() }
    controller.openNote(at: "A.md")
    let original = try #require(controller.openNote?.text)
    controller.updateOpenNoteText(note("A, non salvato."))
    try vault.remove("A.md")
    await controller.reconcile(["A.md"])
    try #require(controller.openNote?.externalChangePending == .deleted)

    // Undone back to the saved text: the buffer reads clean again.
    controller.updateOpenNoteText(original)
    try #require(controller.openNote?.hasUnsavedChanges == false)

    controller.keepLocalVersion()

    #expect(
        controller.openNote?.hasUnsavedChanges == true,
        "savedText diventa \"\": non c'è più niente su disco da cui essere uguali"
    )

    await controller.saveOpenNote()

    let onDisk = try String(contentsOf: vault.root.appending(path: "A.md"), encoding: .utf8)
    #expect(onDisk == original)
    #expect(controller.openNote?.hasUnsavedChanges == false)
}

// MARK: 16 - R-04, the banner never offers a reload for a deletion

/// Red on today's code: `ConflictBannerCopy`'s placeholder body reads `.deleted` exactly like
/// `.text` (Task 1), so it still offers "Ricarica da disco" instead of "Scarta ed elimina".
@Test func theBannerForADeletionNeverOffersAReload() {
    let deletedCopy = ConflictBannerCopy(pending: .deleted)

    #expect(deletedCopy.acceptLabel == "Scarta ed elimina")
    #expect(deletedCopy.keepLabel == "Tieni la mia versione")
    #expect(![deletedCopy.message, deletedCopy.acceptLabel, deletedCopy.keepLabel].contains("Ricarica da disco"))

    // Today's three strings, unchanged, for the `.text` side.
    let textCopy = ConflictBannerCopy(pending: .text("qualcosa"))
    #expect(textCopy.message == "La nota è cambiata su disco mentre la stavi modificando.")
    #expect(textCopy.acceptLabel == "Ricarica da disco")
    #expect(textCopy.keepLabel == "Tieni la mia versione")
}

// MARK: 17-18 - §D6/R-09, guards that stay green through Tasks 3-4

/// Green today, and the regression guard gate G1 exists to protect
/// (`Tests/VaultControllerMoveNoteTests.swift:81`'s own race, inferred rather than reproduced):
/// today the missing-path branch reports nothing for the vacated source, so the tab is never
/// closed and simply follows the move once `movedNote` runs. §D6's fix keeps this true on
/// purpose, by suppressing the deletion signal for a session's own move rather than by this gap.
@MainActor
@Test func aSessionMoveReconciledBeforeMovedNoteStillFollows() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    defer { controller.close() }
    controller.openNote(at: "A.md")
    try #require(controller.openNote?.relativePath == "A.md")

    // Not "B.md": `controller(_:)` already seeds that file, and a real `moveFile` refuses a
    // destination that exists - "C.md" is free.
    try await controller.session?.moveFile(from: "A.md", to: "C.md")
    await controller.reconcile(["A.md"])
    controller.movedNote(from: "A.md", to: "C.md")

    #expect(controller.openNote?.relativePath == "C.md")
}

/// Green today: `trashNote(at:)` already closes its tabs synchronously before the watcher's own
/// `reconcile` could, and an explicit `trashedNote(at:)` call after a bare `session.trashFile`
/// closes them just as well the other way round - the R-09 ordering argument the SPEC registers,
/// not independently mechanized, but true in both orders already.
@MainActor
@Test func aTrashEndsInTheSameStateInEitherOrder() async throws {
    let vaultOne = try TemporaryVault()
    let controllerOne = try await controller(vaultOne)
    defer { controllerOne.close() }
    controllerOne.openNote(at: "A.md")
    try #require(controllerOne.openNote?.relativePath == "A.md")

    #expect(await controllerOne.trashNote(at: "A.md"))
    await controllerOne.reconcile(["A.md"])

    #expect(!controllerOne.tabs.contains { $0.note.relativePath == "A.md" })
    #expect(!controllerOne.closedTabPaths.contains("A.md"))
    #expect(!controllerOne.recentNotePaths.contains("A.md"))
    #expect(controllerOne.problems.isEmpty, "\(controllerOne.problems)")

    let vaultTwo = try TemporaryVault()
    let controllerTwo = try await controller(vaultTwo)
    defer { controllerTwo.close() }
    controllerTwo.openNote(at: "A.md")
    try #require(controllerTwo.openNote?.relativePath == "A.md")

    try await controllerTwo.session?.trashFile(at: "A.md")
    await controllerTwo.reconcile(["A.md"])
    controllerTwo.trashedNote(at: "A.md")

    #expect(!controllerTwo.tabs.contains { $0.note.relativePath == "A.md" })
    #expect(!controllerTwo.closedTabPaths.contains("A.md"))
    #expect(!controllerTwo.recentNotePaths.contains("A.md"))
    #expect(controllerTwo.problems.isEmpty, "\(controllerTwo.problems)")
}
