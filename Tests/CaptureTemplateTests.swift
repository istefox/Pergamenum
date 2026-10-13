import Foundation
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0086 §D5, plan docs/plans/pg-387-n4-birth-of-note.md, Task 4 - R-09: the
// capture panel's template menu. «Nota nuova» offers one, and the controller hands its choice to
// `VaultAPI.capture` so the title, the captured text and the template are one write; «Task»,
// «Oggi» and «In una nota» offer none.
//
// The menu itself is a SwiftUI control inside a panel that appears over another application
// (CapturePanelTests says why that is not reachable), so what is tested is the decision it feeds.

private let riunione = """
---
date: 2026-01-01
tags:
  - type-note
---

# {{title}}

Prima
{{cursor}}
Dopo
"""

@MainActor
private func session(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(riunione, to: "Templates/Riunione.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    return try #require(controller.session)
}

// MARK: - Which destinations offer a template

@Test func onlyANewNoteOffersATemplateMenu() {
    for destination in CaptureController.Destination.allCases {
        #expect(destination.takesTemplate == (destination == .note), "\(destination.rawValue)") // R-09
    }
}

// MARK: - A template on a new note

@MainActor
@Test func theControllerPassesItsTemplateToTheCaptureAndTheNoteHoldsTheTextAtTheMarker() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    let controller = CaptureController()
    controller.destination = .note
    controller.text = "Idea per la riunione\nSecondo rigo del pensiero"
    controller.template = "Templates/Riunione.md"

    let closed = await controller.capture(into: session)

    #expect(closed, "the capture went through") // R-09
    guard case .wrote(let path) = controller.outcome else {
        Issue.record("expected a written capture, got \(String(describing: controller.outcome))")
        return
    }
    let text = try String(contentsOf: vault.root.appending(path: path), encoding: .utf8)
    #expect(!text.contains("{{cursor}}"))
    #expect(text.contains("# Idea per la riunione"), "the template's heading is the derived title") // R-09
    let before = try #require(text.range(of: "Prima"))
    let captured = try #require(text.range(of: "Secondo rigo del pensiero"))
    let after = try #require(text.range(of: "Dopo"))
    #expect(before.upperBound <= captured.lowerBound, "the captured text sits at the marker") // R-09
    #expect(captured.upperBound <= after.lowerBound)
}

@MainActor
@Test func aNewNoteWithoutATemplateIsWrittenAsBefore() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    let controller = CaptureController()
    controller.destination = .note
    // Two lines: without a template the first line is the title (the file name) and only the
    // rest is the body, so a one-line capture would leave the body empty (unchanged since main).
    controller.text = "Titolo del pensiero\nSolo un pensiero"

    #expect(await controller.capture(into: session))

    guard case .wrote(let path) = controller.outcome else {
        Issue.record("expected a written capture")
        return
    }
    #expect(path.hasSuffix("Titolo del pensiero.md"), "the first line names the file")
    let text = try String(contentsOf: vault.root.appending(path: path), encoding: .utf8)
    #expect(text.contains("Solo un pensiero"))
    #expect(!text.contains("Prima"), "no template, no template text")
}

// MARK: - A template that is gone

@MainActor
@Test func aRememberedTemplateThatNoLongerExistsIsDroppedNotSent() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    let controller = CaptureController()
    controller.destination = .note
    controller.text = "Titolo del pensiero\nSolo un pensiero"
    // The menu shows «Nessun modello» for this, so the capture must ask for none (R-09).
    controller.template = "Templates/Cancellato.md"

    let closed = await controller.capture(into: session)

    #expect(closed, "a stale template must not refuse a capture that shows none chosen") // R-09
    guard case .wrote(let path) = controller.outcome else {
        Issue.record("expected a written capture, got \(String(describing: controller.outcome))")
        return
    }
    #expect(controller.template == nil)
    let text = try String(contentsOf: vault.root.appending(path: path), encoding: .utf8)
    #expect(text.contains("Solo un pensiero"))
    #expect(!text.contains("Prima"), "no template, no template text")
}

/// The menu labels by exact path, so a remembered path that moved is shown as «Nessun modello»; the
/// connector resolves a reference by file name too, and would have composed the capture on the
/// template at its new path, one the person saw as absent.
@MainActor
@Test func aRememberedTemplateThatMovedToAnotherFolderIsDroppedNotResolvedByName() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    let controller = CaptureController()
    controller.destination = .note
    controller.text = "Titolo del pensiero\nSolo un pensiero"
    // `Riunione.md` exists, but under `Templates/`, not `Templates/Sub/`.
    controller.template = "Templates/Sub/Riunione.md"

    let closed = await controller.capture(into: session)

    #expect(closed)
    guard case .wrote(let path) = controller.outcome else {
        Issue.record("expected a written capture, got \(String(describing: controller.outcome))")
        return
    }
    #expect(controller.template == nil) // R-09: the panel showed none
    let text = try String(contentsOf: vault.root.appending(path: path), encoding: .utf8)
    #expect(text.contains("Solo un pensiero"))
    #expect(!text.contains("Prima"), "the template that was not shown is not applied")
}

// MARK: - Switching destination drops the template

@MainActor
@Test func switchingToTaskDropsTheTemplateFromTheCall() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    let controller = CaptureController()
    controller.template = "Templates/Riunione.md"
    controller.destination = .task
    controller.text = "Chiamare il cliente"

    let closed = await controller.capture(into: session)

    // A template reaching `VaultAPI.capture` with a task destination is a usage error there, so
    // a write that went through proves the controller did not pass it.
    #expect(closed, "a template left over from «Nota nuova» must not refuse a task") // R-09
    guard case .wrote = controller.outcome else {
        Issue.record("expected a written task, got \(String(describing: controller.outcome))")
        return
    }
}

@MainActor
@Test func theOtherDestinationsAlsoIgnoreALeftOverTemplate() async throws {
    for destination in [CaptureController.Destination.today] {
        let vault = try TemporaryVault()
        let session = try await session(vault)
        let controller = CaptureController()
        controller.template = "Templates/Riunione.md"
        controller.destination = destination
        controller.text = "Un appunto"

        #expect(await controller.capture(into: session), "\(destination.rawValue)") // R-09
    }
}
