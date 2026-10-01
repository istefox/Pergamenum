import Foundation
import Testing
@testable import Pergamenum

// ADR-0073 §D5, departure 13 (fix loop, 2026-09-29): a tab that survives a vault switch is never
// written by the quit into the vault that replaced its own. These tests call `open(_:)` directly,
// below `switchVault(to:)` - PG-334's door, which empties the tabs first (`VaultSwitchTests`) - so
// the mark they pin is the defence in depth behind that door.

/// Vault B: it has a `Nexion.md` of its own, which a stale write from vault A would overwrite,
/// and no `Dopo.md`, which it would create.
private func otherVault(_ vault: borrowing TemporaryVault) throws {
    try vault.write(quitNote("Nexion di B."), to: "Nexion.md")
}

@MainActor
@Test func aTabOfThePreviousVaultIsMarkedWhenAnotherVaultOpens() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    try otherVault(b)
    let controller = try await quitController(a)
    let id = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    #expect(controller.tab(withID: id)?.isFromPreviousVault == false)

    await controller.open(b.root)

    #expect(controller.tab(withID: id)?.isFromPreviousVault == true)
    controller.close()
}

@MainActor
@Test func reopeningTheSameVaultLeavesItsTabsUnmarked() async throws {
    let a = try TemporaryVault()
    let controller = try await quitController(a)
    let id = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)

    await controller.open(a.root)

    #expect(controller.tab(withID: id)?.isFromPreviousVault == false)
    controller.close()
}

@MainActor
@Test func returningToTheTabsOwnVaultClearsTheMarkAndSavesThere() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    try otherVault(b)
    let rootA = a.root
    let controller = try await quitController(a)
    let id = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)

    await controller.open(b.root)
    #expect(controller.tab(withID: id)?.isFromPreviousVault == true)
    await controller.open(rootA)

    #expect(controller.tab(withID: id)?.isFromPreviousVault == false)
    controller.focusTab(id)
    await controller.saveOpenNote()
    #expect(quitOnDisk(rootA, "Nexion.md")?.contains("Di A.") == true)
    #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == false)

    // And the bulk answer reports it saved, not foreign.
    controller.updateOpenNoteText((controller.openNote?.text ?? "") + "Ancora.\n")
    let review = QuitReview(columns: controller.columns)
    let report = await controller.saveForQuit(review)
    #expect(report == QuitSaveReport(saved: [id]))
    controller.close()
}

@MainActor
@Test func aTabStaysForeignAcrossASecondSwitchAwayFromItsVault() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let c = try TemporaryVault()
    try otherVault(b)
    let controller = try await quitController(a)
    let id = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)

    await controller.open(b.root)
    await controller.open(c.root)
    #expect(controller.tab(withID: id)?.isFromPreviousVault == true)
    await controller.open(b.root)
    #expect(controller.tab(withID: id)?.isFromPreviousVault == true)
    controller.close()
}

/// A symlink to `target`, in a scratch directory that goes away with the test.
private func symlink(to target: URL) throws -> URL {
    let link = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-link-\(UUID().uuidString)", directoryHint: .notDirectory)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    return link
}

@MainActor
@Test func aVaultOpenedThroughASymlinkAndThenByItsRealPathIsTheSameVault() async throws {
    let a = try TemporaryVault()
    let real = a.root.resolvingSymlinksInPath()
    let link = try symlink(to: real)
    defer { try? FileManager.default.removeItem(at: link) }
    let controller = try await quitController(a)
    await controller.open(link)
    let id = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)

    // The open panel hands over the link, Recents the resolved path.
    await controller.open(real)
    #expect(controller.tab(withID: id)?.isFromPreviousVault == false)
    await controller.open(link)
    #expect(controller.tab(withID: id)?.isFromPreviousVault == false)

    controller.focusTab(id)
    await controller.saveOpenNote()
    #expect(quitOnDisk(real, "Nexion.md")?.contains("Di A.") == true)
    controller.close()
}

@MainActor
@Test func leavingAVaultOpenedByItsRealPathAndReturningThroughASymlinkClearsTheMark() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    try otherVault(b)
    let real = a.root.resolvingSymlinksInPath()
    let link = try symlink(to: real)
    defer { try? FileManager.default.removeItem(at: link) }
    let controller = try await quitController(a)
    await controller.open(real)
    let id = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)

    await controller.open(b.root)
    #expect(controller.tab(withID: id)?.isFromPreviousVault == true)
    await controller.open(link)

    #expect(controller.tab(withID: id)?.isFromPreviousVault == false)
    controller.close()
}

@MainActor
@Test func aTabBornInTheSecondVaultIsForeignOnceTheFirstReopensWhileTheFirstsOwnIsCleared() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    try otherVault(b)
    let rootA = a.root
    let controller = try await quitController(a)
    let ofA = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)

    await controller.open(b.root)
    let ofB = try openDirty("Nexion.md", adding: "\nDi B.\n", inColumn: 1, of: controller)
    #expect(controller.tab(withID: ofA)?.isFromPreviousVault == true)
    #expect(controller.tab(withID: ofB)?.isFromPreviousVault == false)

    await controller.open(rootA)

    #expect(controller.tab(withID: ofA)?.isFromPreviousVault == false)
    #expect(controller.tab(withID: ofB)?.isFromPreviousVault == true)
    #expect(controller.tab(withID: ofB)?.previousVaultRoot?.vaultKey == b.root.vaultKey)
    controller.close()
}

@MainActor
@Test func aTabShowingANewNoteIsNoLongerFromThePreviousVault() {
    var tab = NoteTab(note: VaultController.OpenNote(
        relativePath: "Nexion.md", title: "Nexion", text: "x", savedText: "y"
    ))
    tab.previousVaultRoot = URL(filePath: "/tmp/a", directoryHint: .isDirectory)

    let shown = tab.showing(VaultController.OpenNote(
        relativePath: "Altra.md", title: "Altra", text: "z", savedText: "z"
    ))

    #expect(!shown.isFromPreviousVault)
    #expect(shown.id == tab.id)
}

@MainActor
@Test func saveAllAfterAVaultSwitchWritesNothingIntoTheNewVault() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    try otherVault(b)
    let rootB = b.root
    let controller = try await quitController(a)
    let overwriting = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    let creating = try openDirty("Dopo.md", adding: "\nDi A.\n", inColumn: 1, of: controller)
    await controller.open(b.root)
    let before = quitOnDisk(rootB, "Nexion.md")
    let review = QuitReview(columns: controller.columns)
    #expect(review.saveCandidates.isEmpty)
    #expect(review.entries.map(\.isFromPreviousVault) == [true, true])

    let report = await controller.saveForQuit(review)

    #expect(report == QuitSaveReport(foreign: [overwriting, creating]))
    #expect(quitOnDisk(rootB, "Nexion.md") == before)
    #expect(quitOnDisk(rootB, "Dopo.md") == nil)
    #expect(controller.tab(withID: overwriting)?.note.hasUnsavedChanges == true)
    #expect(controller.problems.contains { $0.contains("Nexion.md") })
    controller.close()
}

@MainActor
@Test func aQuitWithSaveAllAfterAVaultSwitchIsCancelledAndRevealsTheTab() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    try otherVault(b)
    let rootB = b.root
    let controller = try await quitController(a)
    let id = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    await controller.open(b.root)
    let before = quitOnDisk(rootB, "Nexion.md")
    var replies: [Bool] = []
    var revealed: [NoteTab.ID?] = []
    let quit = QuitCoordinator(
        vault: { controller },
        diary: { nil },
        contenitore: { nil },
        commitEditing: {},
        ask: { _ in .save },
        reply: { replies.append($0) },
        reveal: { revealed.append($0) },
        revealContenitore: { _ in },
        sleep: { _ in try? await Task.sleep(for: .seconds(60)) }
    )

    let reply = quit.shouldTerminate()
    try await waitUntil { !replies.isEmpty }

    #expect(reply == .later)
    #expect(replies == [false])
    #expect(revealed == [id])
    #expect(quitOnDisk(rootB, "Nexion.md") == before)
    controller.close()
}

@Test func theQuestionNamesANoteOfAPreviousVault() {
    var note = VaultController.OpenNote(
        relativePath: "Nexion.md", title: "Nexion", text: "x", savedText: "y"
    )
    note.externalChangePending = nil
    var tab = NoteTab(note: note)
    tab.previousVaultRoot = URL(filePath: "/tmp/a", directoryHint: .isDirectory)
    var column = EditorColumn()
    column.tabs = [tab]

    let copy = QuitReview(columns: [column]).copy

    #expect(copy.informative.contains("cartella note aperta prima"))
}

// The refusal lives in `saveTab(_:)`, the one save door, so every caller inherits it: Cmd+S, the
// «Salva» chip and the close dialog are where a cancelled quit sends the person.

@MainActor
@Test func saveOnATabOfThePreviousVaultWritesNothingIntoTheNewVault() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    try otherVault(b)
    let rootB = b.root
    let controller = try await quitController(a)
    let overwriting = try openDirty("Nexion.md", adding: "\nDi A.\n", inColumn: 0, of: controller)
    let creating = try openDirty("Dopo.md", adding: "\nDi A.\n", inColumn: 1, of: controller)
    await controller.open(b.root)
    let before = quitOnDisk(rootB, "Nexion.md")

    // Cmd+S on the focused tab (the one for Dopo.md, which vault B does not have).
    controller.focusTab(creating)
    await controller.saveOpenNote()
    // The «Salva» chip and the close dialog's «Salva» go through the same door.
    let chip = await controller.saveTab(overwriting)
    let closing = await controller.saveAndCloseTab(overwriting)

    #expect(quitOnDisk(rootB, "Dopo.md") == nil)
    #expect(quitOnDisk(rootB, "Nexion.md") == before)
    guard case .failed = chip, case .failed = closing else {
        Issue.record("a previous vault's tab was not refused: \(chip) \(closing)")
        return
    }
    #expect(controller.tab(withID: overwriting)?.note.hasUnsavedChanges == true)
    #expect(controller.tab(withID: creating)?.note.hasUnsavedChanges == true)
    #expect(controller.problems.contains { $0.contains("Nexion.md") })
    #expect(controller.problems.contains { $0.contains("Dopo.md") })
    controller.close()
}
