import Foundation
import Testing
@testable import Pergamenum

// MARK: `selectedTask` staleness after a sub-task capture (ADR-0021 D9, A9)
//
// Plan `docs/superpowers/plans/2026-08-24-workspace-tasks-notes-integration.md`, Task 10.
//
// `VaultController.selectedTask` (`Sources/Vault/VaultController.swift:267`) is a value
// snapshot. `captureTask`/`captureSubtask` (`Sources/Vault/VaultController+Tasks.swift`,
// `Sources/Vault/VaultSession+Tasks.swift:169-190`) write through `VaultSession.write`, whose
// announcement (`VaultController.landed(_:)`, ADR-0067) only keeps an *open editor tab* in
// step - nothing re-resolves `selectedTask` the way
// `rescheduleSelectedTask` does (`Sources/Vault/VaultController+Tasks.swift:36-48`).
//
// «Aggiungi sotto-task» appends `^id(N)` to the parent's own line as a side effect of its
// first use (ADR-0021 D9) via `TaskParser.insertingSubtask(in:below:draft:)`, whose staleness
// guard (`Sources/Core/Tasks/TaskParser.swift:473`, `lines[parent.lineIndex] ==
// parent.rawLine`) then refuses a *second* sub-task capture built from the still-unrefreshed
// `selectedTask`, because the file has moved on since that value was captured. The failure is
// silent: `captureSubtask` returns nil and the composer's guard just leaves the sheet open
// (`Sources/Features/Tasks/TaskComposer.swift:323`).
@MainActor
@Test func selectedTaskStaysStaleAfterASubtaskCaptureAndBreaksASecondOne() async throws {
    let vault = try TemporaryVault()
    try vault.write(parentTaskNote, to: "01 Progetti/Nexion.md")

    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)

    let parent = try #require(controller.index.allTasks.first { $0.text == "Progetto padre" })
    #expect(parent.localID == nil)
    controller.selectedTask = parent

    // First capture: succeeds and, as a side effect, appends `^id(1)` to the parent's own
    // line (ADR-0021 D9).
    var firstSubtask = VaultController.TaskDraft(
        text: "Sotto-task uno", destination: .note(parent.sourcePath)
    )
    firstSubtask.parent = controller.selectedTask
    #expect(await controller.captureTask(firstSubtask) != nil)

    let parentAfterFirstWrite = try #require(controller.index.allTasks.first { $0.localID == 1 })
    #expect(parentAfterFirstWrite.text == "Progetto padre")

    // The bug: nothing refreshed `selectedTask` after the write above, so it is still the
    // pre-`^id` snapshot rather than the line now on disk.
    let selectedLocalID = String(describing: controller.selectedTask?.localID)
    #expect(
        controller.selectedTask?.localID == 1,
        "selectedTask non aggiornato dopo la cattura: localID \(selectedLocalID) invece di 1"
    )

    // The second-order symptom: a second «Aggiungi sotto-task» built from that stale
    // selection silently fails `TaskParser.insertingSubtask`'s staleness guard, because
    // `selectedTask.rawLine` no longer matches what is on disk.
    var secondSubtask = VaultController.TaskDraft(
        text: "Sotto-task due", destination: .note(parent.sourcePath)
    )
    secondSubtask.parent = controller.selectedTask
    #expect(
        await controller.captureTask(secondSubtask) != nil,
        "il secondo sotto-task è stato scartato silenziosamente: \(controller.problems)"
    )

    controller.close()
}

// MARK: Fixture

private let parentTaskNote = """
---
date: 2026-08-11
tags:
  - type-note
---

# Nexion

- [ ] Progetto padre

"""
