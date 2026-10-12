import Foundation
import Testing
@testable import Pergamenum

// ADR-0084 §D6 («Dove compare» is asked for), SPEC R-28, plan docs/plans/note-workflow-n3.md
// Task 5.
//
// `WhereNoteAppearsScan` is the model behind the section: resting until the person presses the
// button, then the boards and the pratiche that point at the note. The read itself is pinned in
// `NoteAppearancesSessionTests`; what is pinned here is the state machine around it. A
// controller over a temporary vault, no timer, no sleep.

private func note(_ body: String) -> String {
    "---\ndate: 2026-10-07\ntags:\n  - type-note\n---\n\n\(body)\n"
}

private let praticaFolder = "01 Progetti/Rossi/Offerta"

private func board(withFilesAt paths: [String]) -> String {
    let nodes = paths.enumerated().map { index, path in
        "{\"id\":\"n\(index)\",\"type\":\"file\",\"file\":\"\(path)\",\"x\":0,\"y\":0,\"width\":260,\"height\":180}"
    }
    return "{\"nodes\":[\(nodes.joined(separator: ","))],\"edges\":[]}"
}

private let praticaText = """
---
pergamenum-dossier: 1
pergamenum-dossier-counterparts:
  - m.rossi@rossi-spa.it
pergamenum-dossier-links-notes:
  - "[[Curva]]"
---

Appunti pratica.

"""

private let messageText = """
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
pergamenum-mail-note: "[[Curva]]"
---

Buongiorno,
"""

@MainActor
private func openController(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    try vault.write(note("Corpo."), to: "Tecnica/Curva.md")
    try vault.write(board(withFilesAt: ["Tecnica/Curva.md"]), to: "Lavagne/Taratura.canvas")
    try vault.write(praticaText, to: "\(praticaFolder)/pratica.md")
    try vault.write(messageText, to: "\(praticaFolder)/email/msg.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    return controller
}

/// The appearances of a `.found` state, or a recorded issue.
private func found(_ state: WhereNoteAppearsScan.State) -> NoteAppearances? {
    guard case .found(let appearances) = state else {
        Issue.record("atteso .found, ottenuto \(state)")
        return nil
    }
    return appearances
}

@MainActor
@Test func theScanRestsUntilItIsAskedFor() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }

    let scan = WhereNoteAppearsScan(vault: controller, notePath: "Tecnica/Curva.md")

    #expect(scan.state == .resting, "reading every message file is never automatic")
}

@MainActor
@Test func scanningFindsTheBoardsAndPraticheOfTheFixtureVault() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    let scan = WhereNoteAppearsScan(vault: controller, notePath: "Tecnica/Curva.md")

    await scan.scan(again: false)

    let appearances = try #require(found(scan.state))
    #expect(appearances.boards.map(\.path) == ["Lavagne/Taratura.canvas"])
    #expect(appearances.pratiche.map(\.folder) == [praticaFolder])
    let pratica = try #require(appearances.pratiche.first)
    #expect(pratica.linksNote)
    #expect(pratica.messages == ["\(praticaFolder)/email/msg.md"])
    #expect(appearances == controller.noteAppearances(ofNoteAt: "Tecnica/Curva.md", rescan: true))
}

@MainActor
@Test func aNoteNobodyPointsAtIsFoundEmptyNotLeftResting() async throws {
    let vault = try TemporaryVault()
    try vault.write(note("Isolata."), to: "Isolata.md")
    let controller = try await openController(vault)
    defer { controller.close() }
    let scan = WhereNoteAppearsScan(vault: controller, notePath: "Isolata.md")

    await scan.scan(again: false)

    let appearances = try #require(found(scan.state))
    #expect(appearances.boards.isEmpty)
    #expect(appearances.pratiche.isEmpty)
}

@MainActor
@Test func scanningAgainRescansWhatABoardSaveChanged() async throws {
    let vault = try TemporaryVault()
    let controller = try await openController(vault)
    defer { controller.close() }
    let scan = WhereNoteAppearsScan(vault: controller, notePath: "Tecnica/Curva.md")
    await scan.scan(again: false)
    try #require(found(scan.state)?.boards.count == 1)
    let generation = controller.indexGeneration

    // A board save does not move the index generation, so only a rescan can see it.
    try vault.write(board(withFilesAt: []), to: "Lavagne/Taratura.canvas")
    try #require(controller.indexGeneration == generation, "a board save must not move the generation")

    await scan.scan(again: true)

    #expect(try #require(found(scan.state)).boards.isEmpty, "«Cerca di nuovo» reads the files again")
    #expect(try #require(found(scan.state)).pratiche.count == 1)
}
