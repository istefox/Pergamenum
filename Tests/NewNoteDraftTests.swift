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
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
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
@Test func clickingTheCoveredNoteStepsOutWithoutReadingItAgain() async throws {
    // The list's selection binding reads nil while composing, so clicking the note the
    // composer covers is a change and reaches the setter - which must step out rather
    // than re-open, since re-reading would discard whatever is unsaved in that note.
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.openNote(at: "Nexion.md")
    controller.updateOpenNoteText("Testo non salvato.\n")
    controller.beginNewNote()

    controller.leaveComposer()

    #expect(controller.isComposingNote == false)
    #expect(controller.isOpenNoteVisible)
    #expect(controller.openNote?.text == "Testo non salvato.\n")
    #expect(controller.noteDraft != nil)
    controller.close()
}

// MARK: `hasParkedDraft` drives the toolbar badge (PG-029)

@MainActor
@Test func hasParkedDraftIsTrueOnlyWhileStoppedOutOfAComposerWithATitle() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    #expect(controller.hasParkedDraft == false)

    controller.beginNewNote()
    #expect(controller.hasParkedDraft == false)

    controller.openNote(at: "Nexion.md")
    controller.parkNewNote(.init(title: "Curva di trasmissibilità"))
    #expect(controller.hasParkedDraft)

    controller.beginNewNote()
    #expect(controller.hasParkedDraft == false)
    controller.close()
}

@MainActor
@Test func hasParkedDraftIsFalseAfterDiscardingTheDraft() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.beginNewNote()
    controller.parkNewNote(.init(title: "Curva di trasmissibilità"))
    controller.openNote(at: "Nexion.md")
    #expect(controller.hasParkedDraft)

    controller.beginNewNote()
    controller.endNewNote()

    #expect(controller.hasParkedDraft == false)
    controller.close()
}

@MainActor
@Test func hasParkedDraftIsFalseForATitlelessDraft() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.beginNewNote(in: "Progetti")
    controller.openNote(at: "Nexion.md")
    controller.parkNewNote(.init(folder: "Progetti", title: "   "))

    #expect(controller.hasParkedDraft == false)
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

// MARK: Cmd+N seeds the folder from the tree (n1-seams R-11)

@MainActor
@Test func aSeedPointsTheComposerAtThatFolderWhenNothingIsParked() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)

    controller.beginNewNote(seed: "Progetti")

    #expect(controller.isComposingNote)
    #expect(controller.noteDraft?.folder == "Progetti") // (n1-seams R-11)
    controller.close()
}

@MainActor
@Test func aParkedTitledDraftKeepsItsOwnFolderWhateverTheSeed() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)
    controller.beginNewNote()
    controller.parkNewNote(.init(folder: "Archivio", title: "Curva di trasmissibilità"))

    controller.beginNewNote(seed: "Progetti")

    #expect(controller.noteDraft?.title == "Curva di trasmissibilità")
    #expect(controller.noteDraft?.folder == "Archivio") // (n1-seams R-11)
    controller.close()
}

@MainActor
@Test func nuovaNotaQuiStillOverridesTheSeedAndTheParkedFolder() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)

    controller.beginNewNote(in: "X", seed: "Progetti")

    #expect(controller.noteDraft?.folder == "X") // (n1-seams R-11)
    controller.close()
}

@MainActor
@Test func noSeedAndNothingParkedComposesAtTheRoot() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)

    controller.beginNewNote()

    #expect(controller.noteDraft?.folder == "")
    controller.close()
}

@MainActor
@Test func theNewNoteCommandReadsTheTreeSelectionFromAnyPaneAndLeavesForTheNotePane() async throws {
    let vault = try TemporaryVault()
    try vault.write(note, to: "Progetti/Alfa/Nota.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    let calendarStore = EventKitStore()
    let actions = CommandActions(
        navigation: Navigation(),
        vault: controller,
        day: DayController(store: calendarStore, vault: controller),
        calendar: calendarStore,
        capturePanel: CapturePanel(
            controller: CaptureController(),
            session: { controller.session },
            theme: { ThemeEngine().current },
            shortcutCaption: { nil }
        ),
        history: NavigationHistory(),
        pasteboard: .volatile()
    )
    actions.navigation.pane = .tasks
    actions.navigation.noteTreeSelection = ["Progetti/Alfa/Nota.md"]

    actions.run(.newNote)

    #expect(actions.navigation.pane == .notes) // (n1-seams R-11)
    #expect(controller.isComposingNote) // (n1-seams R-11)
    #expect(controller.noteDraft?.folder == "Progetti/Alfa") // (n1-seams R-11)
    controller.close()
}
