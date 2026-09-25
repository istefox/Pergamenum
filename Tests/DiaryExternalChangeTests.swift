import Foundation
import Testing
@testable import Pergamenum

/// #495: `DiaryController.handleExternalChange(path:text:)`, wired from
/// `VaultController+Watching.swift`'s `reconcile(_:)` through the new
/// `VaultController.didObserveExternalChange` fan-out (`PergamenumApp.init`) - the Diario
/// pane is not a tab, so it needed its own hand-off from the watcher.
///
/// Exercised by calling `handleExternalChange` directly (as `VaultControllerReconcileTests.swift`
/// exercises the tab fan-out through `reconcile(_:)` itself): the wiring from `reconcile` to
/// this method is one line in `VaultController+Watching.swift` and is not re-proven here.

private func diaryExternalChangeText(_ body: String) -> String {
    "---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\n\(body)\n"
}

@MainActor
@Test func aCleanPaneReloadsWhenItsOwnDayChangesExternally() async throws {
    let vault = try TemporaryVault()
    try vault.write(diaryExternalChangeText("Testo iniziale."), to: "Diario/20260811.md")
    let (diary, controller) = try await makeDiary(vault)
    #expect(diary.saveState == .saved)

    let newText = diaryExternalChangeText("Cambiato da un altro processo.")
    // The real watcher only fires after the file itself changed - `reload()` re-reads from
    // disk (by design, so a second reader's write is picked up too), so the fixture must put
    // the new bytes there before simulating the notification, not just compute them in memory.
    try vault.write(newText, to: "Diario/20260811.md")
    diary.handleExternalChange(path: controller.diaryNotePath(for: testDay), text: newText)

    #expect(diary.prose.contains("Cambiato da un altro processo."))
    #expect(diary.saveState == .saved)
    #expect(diary.origin.disk == .present(hash: NoteStore.hash(Data(newText.utf8))))
    controller.close()
}

@MainActor
@Test func aDirtyPaneEntersConflictInsteadOfDiscardingEitherSide() async throws {
    let vault = try TemporaryVault()
    try vault.write(diaryExternalChangeText("Testo iniziale."), to: "Diario/20260811.md")
    let (diary, controller) = try await makeDiary(vault)

    diary.prose += "La mia frase non ancora salvata.\n"
    #expect(diary.saveState == .pending)

    let newText = diaryExternalChangeText("Cambiato da un altro processo.")
    // Same as above: the external process's write already landed on disk before the
    // notification fires, and this test's second assertion (the change was not overwritten)
    // is meaningless unless the change is actually there to begin with.
    try vault.write(newText, to: "Diario/20260811.md")
    diary.handleExternalChange(path: controller.diaryNotePath(for: testDay), text: newText)

    guard case .conflicted = diary.saveState else {
        Issue.record("expected .conflicted, got \(diary.saveState)")
        return
    }
    // Neither side was silently discarded: the local edit is still in memory...
    #expect(diary.prose.contains("La mia frase non ancora salvata."))
    // ...and the external change was not written over.
    #expect(try String(contentsOf: vault.root.appending(path: "Diario/20260811.md"), encoding: .utf8) == newText)
    controller.close()
}

@MainActor
@Test func aChangeToADifferentDayIsIgnoredEntirely() async throws {
    let vault = try TemporaryVault()
    try vault.write(diaryExternalChangeText("Testo iniziale."), to: "Diario/20260811.md")
    let (diary, controller) = try await makeDiary(vault)
    let proseBefore = diary.prose
    let saveStateBefore = diary.saveState
    let originBefore = diary.origin

    diary.handleExternalChange(
        path: "Diario/20260812.md", text: diaryExternalChangeText("Un altro giorno.")
    )

    #expect(diary.day == testDay)
    #expect(diary.prose == proseBefore)
    #expect(diary.saveState == saveStateBefore)
    #expect(diary.origin == originBefore)
    controller.close()
}

@MainActor
@Test func onceConflictedAFurtherExternalChangeIsIgnored() async throws {
    let vault = try TemporaryVault()
    try vault.write(diaryExternalChangeText("Testo iniziale."), to: "Diario/20260811.md")
    let (diary, controller) = try await makeDiary(vault)

    diary.prose += "Frase mia.\n"
    diary.handleExternalChange(
        path: controller.diaryNotePath(for: testDay),
        text: diaryExternalChangeText("Primo cambiamento esterno.")
    )
    guard case .conflicted(let firstReason) = diary.saveState else {
        Issue.record("expected .conflicted after the first external change")
        return
    }
    let proseAtConflict = diary.prose

    diary.handleExternalChange(
        path: controller.diaryNotePath(for: testDay),
        text: diaryExternalChangeText("Secondo cambiamento esterno, deve essere ignorato.")
    )

    guard case .conflicted(let secondReason) = diary.saveState else {
        Issue.record("expected to remain .conflicted, got \(diary.saveState)")
        return
    }
    #expect(firstReason == secondReason)
    #expect(diary.prose == proseAtConflict)
    controller.close()
}

/// A self-write echo - the text handed back matches what `origin` already says the file
/// holds - must not trigger a spurious reload. Confirmed against the production check
/// (`DiaryController.swift`: `if case .read(_, .present(let hash)) = origin, NoteStore.hash(...)
/// == hash { return }`) rather than assumed from the plan.
@MainActor
@Test func aSelfWriteEchoIsIgnoredAndDoesNotReload() async throws {
    let vault = try TemporaryVault()
    let initialText = diaryExternalChangeText("Testo iniziale.")
    try vault.write(initialText, to: "Diario/20260811.md")
    let (diary, controller) = try await makeDiary(vault)
    let originBefore = diary.origin
    guard case .read(_, .present(let hash)) = originBefore else {
        Issue.record("expected the pane to have read a present file before this test's own check")
        return
    }
    #expect(hash == NoteStore.hash(Data(initialText.utf8)))

    // Handing back the exact text `origin` already reflects, at this pane's own path, is
    // indistinguishable from this session's own write echoing back through the watcher.
    diary.handleExternalChange(path: controller.diaryNotePath(for: testDay), text: initialText)

    #expect(diary.saveState == .saved)
    #expect(diary.origin == originBefore)
    controller.close()
}
