import Foundation
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0085 §D7 and ADR-0083 §D6, plan docs/plans/pg-387-n4-birth-of-note.md, Task 4 -
// R-11. Quick Open's create row no longer writes at the vault root: it offers the composer,
// prefilled (`VaultController.offerNoteFromQuickOpen(title:)`), and the composer creates through
// `VaultController.createComposedNote(_:)`. These tests replace the five of n1-seams R-18 that
// pinned `createNoteFromQuickOpen` and `quickSwitcherProblem` (the change Stefano approved in chat
// before Task 4 ran); the old door and field are deleted in Task 6.

private let existing = """
---
date: 2026-10-01
tags:
  - type-note
---

Corpo.
"""

@MainActor
private func opened(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    try vault.write(existing, to: "Prova.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    return controller
}

private func exists(_ path: String, in root: URL) -> Bool {
    FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false))
}

// MARK: - offerNoteFromQuickOpen

@MainActor
@Test func theCreateRowOpensTheComposerPrefilledAndClosesTheSwitcher() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    controller.isShowingQuickSwitcher = true

    controller.offerNoteFromQuickOpen(title: "Idea nuova")

    #expect(controller.isComposingNote) // R-11
    #expect(controller.noteDraft?.title == "Idea nuova") // R-11
    #expect(controller.noteDraft?.folder == "") // R-11: the vault root, the pane host's default
    #expect(!controller.isShowingQuickSwitcher) // R-11
    controller.close()
}

@MainActor
@Test func theCreateRowWritesNothingAndOpensNoTab() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    let tabsBefore = controller.columns.flatMap(\.tabs).count

    controller.offerNoteFromQuickOpen(title: "Idea nuova")

    #expect(!exists("Idea nuova.md", in: vault.root)) // R-11: the composer is the one naming surface
    #expect(controller.columns.flatMap(\.tabs).count == tabsBefore) // R-11
    controller.close()
}

@MainActor
@Test func aParkedDraftWinsAndTheProblemIsRecorded() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    var parked = VaultController.NoteDraft()
    parked.title = "Bozza in corso"
    parked.folder = ""
    controller.noteDraft = parked
    let problemsBefore = controller.problems.count

    controller.offerNoteFromQuickOpen(title: "Idea nuova")

    #expect(controller.noteDraft?.title == "Bozza in corso") // ADR-0083 §D6: never overwritten
    #expect(controller.isComposingNote) // the composer opens on the parked draft
    #expect(controller.problems.count == problemsBefore + 1) // the offer says why it did not take
    #expect(controller.problems.last?.contains("già in preparazione") == true)
    controller.close()
}

// MARK: - createComposedNote

@MainActor
@Test func aTakenTitleThrowsRecordsItsSentenceAndOpensNoTab() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    let tabsBefore = controller.columns.flatMap(\.tabs).count

    // The sentence a failed creation produces, taken from the same failure through the older
    // door; independent of what the new method records.
    var expected = ""
    do {
        try await controller.createNote(title: "Prova", date: .today)
        Issue.record("creating a note whose title is taken should have thrown")
    } catch {
        expected = ConformanceText.creationFailure(error)
    }
    #expect(!expected.isEmpty)
    let problemsBefore = controller.problems

    var thrown: (any Error)?
    do {
        try await controller.createComposedNote(NoteComposition(title: "Prova", folder: ""))
    } catch {
        thrown = error
    }

    #expect(thrown != nil) // R-11: a taken title is refused
    #expect(controller.problems.count == problemsBefore.count + 1) // R-11 / note-workflow R-11
    #expect(controller.problems.contains(expected))
    #expect(controller.columns.flatMap(\.tabs).count == tabsBefore)
    #expect(controller.openNote?.relativePath != "Prova.md")
    controller.close()
}

@MainActor
@Test func aFreeTitleCreatesTheNoteOpensItInANewTabAndRecordsNoProblem() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    let tabsBefore = controller.columns.flatMap(\.tabs).count
    let problemsBefore = controller.problems

    let path = try await controller.createComposedNote(NoteComposition(title: "Nota nuova", folder: ""))

    #expect(path == "Nota nuova.md")
    #expect(exists("Nota nuova.md", in: vault.root))
    #expect(controller.openNote?.relativePath == "Nota nuova.md")
    #expect(controller.columns.flatMap(\.tabs).count == tabsBefore + 1)
    #expect(controller.problems == problemsBefore)
    controller.close()
}
