import Foundation
import Testing
@testable import Pergamenum

// «Crea la nota» from the quick switcher says what went wrong when it cannot (n1-seams R-18):
// `VaultController.createNoteFromQuickOpen` answers whether it worked, and on a failure leaves
// the creation failure's sentence on `quickSwitcherProblem`, where the switcher shows it, instead
// of swallowing the error as the call it replaces did.

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

@MainActor
@Test func aTakenTitleReturnsFalseSetsTheSentenceAndOpensNoTab() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    let tabsBefore = controller.columns.flatMap(\.tabs).count

    // The sentence a failed creation produces, taken from the same failure through the door
    // the switcher uses; independent of what the new method records.
    var expected = ""
    do {
        try await controller.createNote(title: "Prova", date: .today)
        Issue.record("creating a note whose title is taken should have thrown")
    } catch {
        expected = ConformanceText.creationFailure(error)
    }
    #expect(!expected.isEmpty)

    let created = await controller.createNoteFromQuickOpen(title: "Prova")

    #expect(created == false) // (n1-seams R-18)
    #expect(controller.quickSwitcherProblem == expected) // (n1-seams R-18)
    #expect(controller.columns.flatMap(\.tabs).count == tabsBefore) // (n1-seams R-18)
    #expect(controller.openNote?.relativePath != "Prova.md") // (n1-seams R-18)
    controller.close()
}

@MainActor
@Test func aFreeTitleReturnsTrueClearsTheProblemAndOpensTheNoteInANewTab() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)
    controller.quickSwitcherProblem = "una frase di un tentativo precedente"
    let tabsBefore = controller.columns.flatMap(\.tabs).count

    let created = await controller.createNoteFromQuickOpen(title: "Nota nuova")

    #expect(created == true) // (n1-seams R-18)
    #expect(controller.quickSwitcherProblem == nil) // (n1-seams R-18)
    #expect(controller.openNote?.relativePath == "Nota nuova.md") // (n1-seams R-18)
    #expect(controller.columns.flatMap(\.tabs).count == tabsBefore + 1) // (n1-seams R-18)
    #expect(FileManager.default.fileExists(
        atPath: vault.root.appending(path: "Nota nuova.md").path(percentEncoded: false)
    ))
    controller.close()
}

@MainActor
@Test func aFailureAfterASuccessAndASuccessAfterAFailureEachLeaveTheirOwnState() async throws {
    let vault = try TemporaryVault()
    let controller = try await opened(vault)

    #expect(await controller.createNoteFromQuickOpen(title: "Prova") == false) // (n1-seams R-18)
    #expect(controller.quickSwitcherProblem != nil) // (n1-seams R-18)

    #expect(await controller.createNoteFromQuickOpen(title: "Altra nota") == true) // (n1-seams R-18)
    #expect(controller.quickSwitcherProblem == nil) // (n1-seams R-18)
    controller.close()
}
