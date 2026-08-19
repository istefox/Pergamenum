import Foundation
import Testing
@testable import Pergamenum

// The new-note draft, after PG-027 and PG-028 split what `newNote` used to mean in two.
//
// `noteDraft` is the draft, alive or parked; `isComposingNote` is whether the composer
// occupies the editor column. They were one property, and that is exactly how a note came
// to open *underneath* the composer while the index in the sidebar described it.

private let note = """
---
date: 2026-08-11
tags:
  - type-note
---

## Una sezione

Corpo.
"""

@MainActor
private func controller(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    try vault.write(note, to: "Nexion.md")
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)
    return controller
}

// MARK: Stepping out keeps the draft (PG-028)

@MainActor
@Test func openingANoteWhileComposingParksWhatWasTyped() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.beginNewNote()

    // What the composer's `onDisappear` hands over when a note is clicked in the list.
    controller.openNote(at: "Nexion.md")
    controller.parkNewNote(
        .init(
            folder: "Progetti",
            title: "Curva di trasmissibilità",
            topic: "topic-x",
            template: "Templates/Riunione.md"
        )
    )

    #expect(controller.isComposingNote == false)
    #expect(controller.openNote?.relativePath == "Nexion.md")

    controller.beginNewNote()
    #expect(controller.isComposingNote)
    #expect(controller.noteDraft?.title == "Curva di trasmissibilità")
    #expect(controller.noteDraft?.folder == "Progetti")
    #expect(controller.noteDraft?.topic == "topic-x")
    #expect(controller.noteDraft?.template == "Templates/Riunione.md")
    controller.close()
}

@MainActor
@Test func nuovaNotaQuiMovesARestoredDraftWithoutLosingItsTitle() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.beginNewNote()
    controller.parkNewNote(.init(title: "Curva di trasmissibilità"))

    controller.beginNewNote(in: "Progetti")

    #expect(controller.noteDraft?.title == "Curva di trasmissibilità")
    #expect(controller.noteDraft?.folder == "Progetti")
    controller.close()
}

@MainActor
@Test func aDraftWithNoTitleIsNotWorthParking() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.beginNewNote(in: "Progetti")

    controller.parkNewNote(.init(folder: "Progetti", title: "   "))

    #expect(controller.noteDraft == nil)
    controller.beginNewNote()
    #expect(controller.noteDraft?.folder.isEmpty == true)
    controller.close()
}

// MARK: Dismissing throws it away, in either order (PG-028)

@MainActor
@Test func cancellingDiscardsTheDraft() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.beginNewNote()
    controller.parkNewNote(.init(title: "Curva di trasmissibilità"))

    controller.endNewNote()

    #expect(controller.noteDraft == nil)
    #expect(controller.isComposingNote == false)
    controller.beginNewNote()
    #expect(controller.noteDraft?.title.isEmpty == true)
    controller.close()
}

@MainActor
@Test func parkingAfterDismissalResurrectsNothing() async throws {
    // SwiftUI decides whether `onDisappear` runs before or after the button's action, so
    // the guard in `parkNewNote` has to hold whichever way round they arrive. Without it,
    // «Crea» would leave the title of the note just created waiting for the next Cmd+N.
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.beginNewNote()

    controller.endNewNote()
    controller.parkNewNote(.init(title: "Curva di trasmissibilità"))

    #expect(controller.noteDraft == nil)
    controller.close()
}

// MARK: The panes stop describing a covered note (PG-027)

@MainActor
@Test func theOpenNoteIsNotVisibleWhileTheComposerCoversIt() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    #expect(controller.isOpenNoteVisible)

    controller.beginNewNote()

    // The note is still open - the composer is over it, not instead of it - and that is
    // the distinction the index and the inspector were missing.
    #expect(controller.openNote != nil)
    #expect(controller.isOpenNoteVisible == false)

    controller.endNewNote()
    #expect(controller.isOpenNoteVisible)
    controller.close()
}

@MainActor
@Test func aFailedReadLeavesTheComposerAlone() async throws {
    // Closing the composer for a note that could not be read would take the draft off the
    // screen and put nothing in its place.
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.beginNewNote()

    controller.openNote(at: "Non esiste.md")

    #expect(controller.isComposingNote)
    controller.close()
}
