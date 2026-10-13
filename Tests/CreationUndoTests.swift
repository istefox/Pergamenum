import Foundation
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0085 §D9, plan docs/plans/pg-387-n4-birth-of-note.md, Task 4 - R-16. The
// «Nota creata · Annulla» offer: pure first (the offer, its 10-second window, the decision), then
// the controller (`undoCreation(now:)` within and after the window, a second creation replacing
// the offer, no other creation path offering one).
//
// The hosted check of the strip's constant height needs `CreationUndoStrip`, which the plan
// declares in Task 6 and not in Task 4: it is a gap reported, not a view invented here.

private let created = VaultSession.WriteResult(path: "Nota.md", text: "---\ndate: 2026-10-01\n---\n\nCorpo.\n")
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func hashOfCreated() -> String {
    NoteStore.hash(Data(created.text.utf8))
}

// MARK: - The offer

@Test func theOfferNamesThePathAndHashesTheBytesTheCreationWrote() {
    let offer = CreationUndo.offer(for: created, at: t0)

    #expect(offer.path == "Nota.md") // R-16
    #expect(offer.createdHash == hashOfCreated()) // R-16: what «Annulla» later compares against
    #expect(offer.expiresAt == t0.addingTimeInterval(10)) // R-16: ten seconds
    #expect(CreationUndo.window == 10)
}

@Test func anOfferIsLiveAtNinePointNineSecondsAndExpiredAtTen() {
    let offer = CreationUndo.offer(for: created, at: t0)
    let hash = hashOfCreated()

    let live = CreationUndo.decide(offer, now: t0.addingTimeInterval(9.9), currentHash: hash, tabIsDirty: false)
    let expired = CreationUndo.decide(offer, now: t0.addingTimeInterval(10), currentHash: hash, tabIsDirty: false)

    #expect(live == .trashed) // R-16
    #expect(expired == .expired) // R-16
}

@Test func aDirtyTabRefusesWithUnsaved() {
    let offer = CreationUndo.offer(for: created, at: t0)

    let decision = CreationUndo.decide(
        offer, now: t0.addingTimeInterval(1), currentHash: hashOfCreated(), tabIsDirty: true
    )

    #expect(decision == .unsaved) // R-16
}

@Test func aMovedHashRefusesWithChanged() {
    let offer = CreationUndo.offer(for: created, at: t0)

    let decision = CreationUndo.decide(
        offer, now: t0.addingTimeInterval(1), currentHash: "not-the-created-hash", tabIsDirty: false
    )

    #expect(decision == .changed) // R-16: the person already wrote into it
}

@Test func onlyARefusalCarriesASentenceAndEachRefusalHasItsOwn() throws {
    let unsaved = try #require(CreationUndo.Decision.unsaved.sentence) // R-16: refused with a sentence
    let changed = try #require(CreationUndo.Decision.changed.sentence) // R-16

    #expect(CreationUndo.Decision.trashed.sentence == nil) // it did what was asked
    #expect(!unsaved.isEmpty)
    #expect(!changed.isEmpty)
    #expect(unsaved != changed)
}

// MARK: - The controller

@MainActor
private func openedForUndo(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    try vault.write("---\ndate: 2026-10-01\ntags:\n  - type-note\n---\n\nEsistente.\n", to: "Esistente.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    return controller
}

private func fileExists(_ path: String, in root: URL) -> Bool {
    FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false))
}

@MainActor
@Test func undoWithinTheWindowTrashesTheNoteForgetsItsIdAndClosesTheCleanTab() async throws {
    let vault = try TemporaryVault()
    let controller = try await openedForUndo(vault)
    let path = try await controller.createComposedNote(NoteComposition(title: "Da annullare", folder: ""))
    let offer = try #require(controller.creationUndo)
    let session = try #require(controller.session)
    let id = try #require(session.mintNoteID(for: path))
    try #require(session.lookUpNote(id: id) == .found(path))
    let tabsBefore = controller.columns.flatMap(\.tabs).count

    let decision = await controller.undoCreation(now: offer.expiresAt.addingTimeInterval(-1))

    #expect(decision == .trashed) // R-16
    #expect(!fileExists(path, in: vault.root)) // R-16: moved to the Trash
    #expect(session.lookUpNote(id: id) == .unknown) // R-16: the id is forgotten (ADR-0059 §D6)
    #expect(controller.columns.flatMap(\.tabs).count == tabsBefore - 1) // the landed door closed the tab
    controller.close()
}

@MainActor
@Test func undoAfterTheWindowIsExpiredAndTheNoteStays() async throws {
    let vault = try TemporaryVault()
    let controller = try await openedForUndo(vault)
    let path = try await controller.createComposedNote(NoteComposition(title: "Resta", folder: ""))
    let offer = try #require(controller.creationUndo)

    let decision = await controller.undoCreation(now: offer.expiresAt)

    #expect(decision == .expired) // R-16
    #expect(fileExists(path, in: vault.root)) // R-16: after the window the note stays
    controller.close()
}

@MainActor
@Test func undoRefusesWhileTheTabHasUnsavedChangesAndTouchesNothing() async throws {
    let vault = try TemporaryVault()
    let controller = try await openedForUndo(vault)
    let path = try await controller.createComposedNote(NoteComposition(title: "Sporca", folder: ""))
    let offer = try #require(controller.creationUndo)
    var note = try #require(controller.openNote)
    note.text += "\nScritto dopo."
    controller.replaceOpenNote(note)
    try #require(controller.openNote?.hasUnsavedChanges == true)

    let decision = await controller.undoCreation(now: offer.expiresAt.addingTimeInterval(-1))

    #expect(decision == .unsaved) // R-16
    #expect(fileExists(path, in: vault.root))
    #expect(controller.openNote?.hasUnsavedChanges == true) // the person's work is untouched
    controller.close()
}

@MainActor
@Test func undoRefusesWhenTheFileChangedSinceCreation() async throws {
    let vault = try TemporaryVault()
    let controller = try await openedForUndo(vault)
    let path = try await controller.createComposedNote(NoteComposition(title: "Cambiata", folder: ""))
    let offer = try #require(controller.creationUndo)
    let url = vault.root.appending(path: path)
    let original = try String(contentsOf: url, encoding: .utf8)
    try (original + "\nUn'altra mano ha scritto qui.\n").write(to: url, atomically: true, encoding: .utf8)

    let decision = await controller.undoCreation(now: offer.expiresAt.addingTimeInterval(-1))

    #expect(decision == .changed) // R-16
    #expect(fileExists(path, in: vault.root))
    controller.close()
}

@MainActor
@Test func aSecondCreationReplacesTheOffer() async throws {
    let vault = try TemporaryVault()
    let controller = try await openedForUndo(vault)
    _ = try await controller.createComposedNote(NoteComposition(title: "Prima", folder: ""))
    let first = try #require(controller.creationUndo)

    let secondPath = try await controller.createComposedNote(NoteComposition(title: "Seconda", folder: ""))

    let second = try #require(controller.creationUndo)
    #expect(second.path == secondPath) // R-16: at most one offer, the newest
    #expect(second.path != first.path)
    controller.close()
}

@MainActor
@Test func noOtherCreationPathOffersTheStrip() async throws {
    let vault = try TemporaryVault()
    let controller = try await openedForUndo(vault)

    controller.offerNoteFromQuickOpen(title: "Solo un'offerta")
    #expect(controller.creationUndo == nil) // an offer of the composer is not a creation

    _ = try await controller.openDailyNote(for: .today)
    #expect(controller.creationUndo == nil) // R-16: the daily note is a navigation target
    controller.close()
}
