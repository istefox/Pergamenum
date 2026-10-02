import Foundation
import Testing
@testable import Pergamenum

// PG-335: «Chiudi la colonna» asks about the column's unsaved tabs with the quit's own review
// (ADR-0073) before dropping them. The decision is pure (`QuitReview.closeDecision`); the door,
// `VaultController.closeColumn(_:ask:saveAll:)`, is driven with a fake `ask` over a real vault,
// and its races are forced with gates through the `saveAll` seam (ADR-0043 §D9), never timed.

private func dirtyTab(_ path: String, text: String = "modificato", saved: String = "originale") -> NoteTab {
    NoteTab(note: VaultController.OpenNote(
        relativePath: path,
        title: (path as NSString).deletingPathExtension,
        text: text,
        savedText: saved
    ))
}

private func column(_ tabs: [NoteTab]) -> EditorColumn {
    var column = EditorColumn()
    column.tabs = tabs
    column.activeID = tabs.first?.id
    return column
}

// MARK: The decision (pure)

@Test func annullaKeepsTheColumnOpenAndNamesNothing() {
    let review = QuitReview(columns: [column([dirtyTab("A.md")])])

    #expect(review.closeDecision(after: .cancel, now: review) == .keepOpen(unresolved: []))
}

@Test func nonSalvareClosesWhenNothingChangedSinceTheQuestion() {
    let review = QuitReview(columns: [column([dirtyTab("A.md"), dirtyTab("B.md")])])

    #expect(review.closeDecision(after: .discard, now: review) == .close)
}

@Test func nonSalvareKeepsTheColumnOpenForTextTypedAfterTheQuestion() {
    let tab = dirtyTab("A.md")
    let review = QuitReview(columns: [column([tab])])
    var typed = tab
    typed.note.text += " e ancora"
    let now = QuitReview(columns: [column([typed])])

    #expect(review.closeDecision(after: .discard, now: now) == .keepOpen(unresolved: now.entries))
}

@Test func salvaClosesOnlyWhenNoDirtyTabIsLeft() {
    let tab = dirtyTab("A.md")
    let review = QuitReview(columns: [column([tab])])
    var saved = tab
    saved.note.savedText = saved.note.text

    #expect(review.closeDecision(after: .save, now: QuitReview(columns: [column([saved])])) == .close)
    // A tab the save did not write - failed, conflicted, from a previous vault - is still dirty.
    #expect(review.closeDecision(after: .save, now: review) == .keepOpen(unresolved: review.entries))
}

// MARK: The words

@MainActor
@Test func theColumnCloseQuestionHasItsOwnWordsAndIdentifiers() {
    let one = QuitReview(columns: [column([dirtyTab("Nexion.md")])]).copy(for: .columnClose)

    #expect(one.message == "Salvare le modifiche a «Nexion» prima di chiudere la colonna?")
    #expect(one.saveLabel == "Salva")
    #expect(one.discardLabel == "Non salvare")
    #expect(one.cancelLabel == "Annulla")
    #expect(one.informative.contains("Chiudendo la colonna senza salvare"))

    let two = QuitReview(columns: [column([dirtyTab("A.md"), dirtyTab("B.md")])]).copy(for: .columnClose)
    #expect(two.message == "Salvare le modifiche a 2 note prima di chiudere la colonna?")
    #expect(two.saveLabel == "Salva tutto")
    #expect(two.informative.hasPrefix("«A»\n«B»"))

    // Literal: a UI test would spell the same strings.
    #expect(QuitReviewAlert.make(one, for: .columnClose).buttons.map { $0.accessibilityIdentifier() } == [
        "column-close-prompt-save", "column-close-prompt-cancel", "column-close-prompt-discard",
    ])
}

// MARK: The door, over a real vault

@MainActor
@Test func aCleanColumnClosesWithoutAsking() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    controller.openNote(at: "Nexion.md")
    controller.splitEditor()
    var asked = 0

    let closed = await controller.closeColumn(1) { _ in
        asked += 1
        return .cancel
    }

    #expect(closed)
    #expect(asked == 0)
    #expect(controller.columns.count == 1)
    controller.close()
}

@MainActor
@Test func theQuestionNamesOnlyTheClosingColumnsDirtyTabs() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nSinistra.\n", inColumn: 0, of: controller)
    let right = try openDirty("Progetti/Sospensione.md", adding: "\nDestra.\n", inColumn: 1, of: controller)
    var asked: [QuitReview] = []

    _ = await controller.closeColumn(1) { review in
        asked.append(review)
        return .cancel
    }

    #expect(asked.map { $0.entries.map(\.tabID) } == [[right]])
    controller.close()
}

@MainActor
@Test func annullaLeavesTheColumnOpenAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    controller.openNote(at: "Nexion.md")
    let id = try openDirty("Progetti/Sospensione.md", adding: "\nNon ancora.\n", inColumn: 1, of: controller)
    let before = quitOnDisk(root, "Progetti/Sospensione.md")

    let closed = await controller.closeColumn(1) { _ in .cancel }

    #expect(!closed)
    #expect(controller.columns.count == 2)
    #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == true)
    #expect(quitOnDisk(root, "Progetti/Sospensione.md") == before)
    controller.close()
}

@MainActor
@Test func nonSalvareClosesTheColumnAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    controller.openNote(at: "Nexion.md")
    let id = try openDirty("Progetti/Sospensione.md", adding: "\nDa scartare.\n", inColumn: 1, of: controller)
    let before = quitOnDisk(root, "Progetti/Sospensione.md")

    let closed = await controller.closeColumn(1) { _ in .discard }

    #expect(closed)
    #expect(controller.columns.count == 1)
    #expect(controller.focusedColumnIndex == 0)
    #expect(controller.tab(withID: id) == nil)
    #expect(quitOnDisk(root, "Progetti/Sospensione.md") == before)
    controller.close()
}

@MainActor
@Test func salvaWritesEveryDirtyTabOfTheColumnThenClosesIt() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    controller.openNote(at: "Nexion.md")
    _ = try openDirty("Progetti/Sospensione.md", adding: "\nPrima salvata.\n", inColumn: 1, of: controller)
    _ = try openDirty("Dopo.md", adding: "\nSeconda salvata.\n", inColumn: 1, of: controller)

    let closed = await controller.closeColumn(1) { _ in .save }

    #expect(closed)
    #expect(controller.columns.count == 1)
    #expect(quitOnDisk(root, "Progetti/Sospensione.md")?.contains("Prima salvata.") == true)
    #expect(quitOnDisk(root, "Dopo.md")?.contains("Seconda salvata.") == true)
    controller.close()
}

@MainActor
@Test func aFailedSaveKeepsTheColumnOpenAndRevealsTheTab() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    controller.openNote(at: "Nexion.md")
    let id = try openDirty("Progetti/Pressa.md", adding: "\nNon scrivibile.\n", inColumn: 1, of: controller)
    controller.focusColumn(0)

    let closed = try await withReadOnlyFolder(root, "Progetti") {
        await controller.closeColumn(1) { _ in .save }
    }

    #expect(!closed)
    #expect(controller.columns.count == 2)
    #expect(controller.focusedColumnIndex == 1, "the tab left unsaved is brought to the front")
    #expect(controller.focusedTab?.id == id)
    #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == true)
    #expect(controller.problems.contains { $0.hasPrefix("Chiusura della colonna annullata") })
    controller.close()
}

@MainActor
@Test func salvaNeverWritesAConflictedTabAndKeepsTheColumnOpen() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    controller.openNote(at: "Nexion.md")
    let conflicted = try openDirty("Progetti/Sospensione.md", adding: "\nMia.\n", inColumn: 1, of: controller)
    _ = try openDirty("Dopo.md", adding: "\nSalvata.\n", inColumn: 1, of: controller)
    controller.updateTabs(showing: "Progetti/Sospensione.md") { $0.note.externalChangePending = .text("altro") }
    let before = quitOnDisk(root, "Progetti/Sospensione.md")

    let closed = await controller.closeColumn(1) { _ in .save }

    #expect(!closed)
    #expect(controller.columns.count == 2)
    #expect(quitOnDisk(root, "Progetti/Sospensione.md") == before)
    #expect(quitOnDisk(root, "Dopo.md")?.contains("Salvata.") == true)
    #expect(controller.tab(withID: conflicted)?.note.hasUnsavedChanges == true)
    controller.close()
}

// MARK: One close at a time per column

/// Starts `closeColumn(1)` answered «Salva» and suspends it in its `saveAll` seam: `before` opens
/// before the saves run, `after` once they have landed; the close waits on `release` there.
@MainActor
private func suspendedSavingClose(
    of controller: VaultController, before: Gate? = nil, after: Gate? = nil, release: Gate
) -> Task<Bool, Never> {
    Task { @MainActor in
        await controller.closeColumn(1, ask: { _ in .save }, saveAll: { review in
            before?.open()
            if before != nil { await release.wait() }
            let report = await controller.saveForQuit(review)
            after?.open()
            if after != nil { await release.wait() }
            return report
        })
    }
}

@MainActor
@Test func aSecondCloseOfAColumnStillSavingIsIgnored() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    controller.openNote(at: "Nexion.md")
    _ = try openDirty("Progetti/Sospensione.md", adding: "\nSalvata una volta.\n", inColumn: 1, of: controller)
    let saving = Gate()
    let release = Gate()

    let first = suspendedSavingClose(of: controller, before: saving, release: release)
    await saving.wait()
    // What a second «Chiudi la colonna» does while the first is still saving. Answered «Non
    // salvare», it would close the column under the first close if the door let it through.
    var asked = 0
    let second = await controller.closeColumn(1) { _ in
        asked += 1
        return .discard
    }

    #expect(!second)
    #expect(asked == 0, "the question was raised again for a column already closing")
    #expect(controller.columns.count == 2)

    release.open()
    let closed = await first.value
    #expect(closed)
    #expect(controller.columns.count == 1)
    #expect(controller.closingColumns.isEmpty)
    #expect(quitOnDisk(root, "Progetti/Sospensione.md")?.contains("Salvata una volta.") == true)
    controller.close()
}

@MainActor
@Test func aCancelledCloseReleasesTheColumnForTheNextRequest() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    controller.openNote(at: "Nexion.md")
    _ = try openDirty("Progetti/Sospensione.md", adding: "\nAncora qui.\n", inColumn: 1, of: controller)

    _ = await controller.closeColumn(1) { _ in .cancel }
    #expect(controller.closingColumns.isEmpty)
    var asked = 0
    let closed = await controller.closeColumn(1) { _ in
        asked += 1
        return .discard
    }

    #expect(closed)
    #expect(asked == 1)
    controller.close()
}

// MARK: The editor changing under the close, forced with gates (ADR-0043 §D9)

@MainActor
@Test func textTypedAfterTheSavesLandedKeepsTheColumnOpen() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    controller.openNote(at: "Nexion.md")
    let id = try openDirty("Progetti/Sospensione.md", adding: "\nPrima.\n", inColumn: 1, of: controller)
    let saved = Gate()
    let release = Gate()

    let closing = suspendedSavingClose(of: controller, after: saved, release: release)
    await saved.wait()
    #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == false, "the save landed before the keystroke")
    // Typed in the column being closed, while its close is suspended between the saves and
    // its decision; then the focus moves away, so the reveal is observable.
    controller.updateOpenNoteText((controller.openNote?.text ?? "") + "Durante.\n")
    controller.focusColumn(0)
    release.open()
    let closed = await closing.value

    #expect(!closed)
    #expect(controller.columns.count == 2)
    let tab = try #require(controller.tab(withID: id))
    #expect(tab.note.hasUnsavedChanges)
    #expect(tab.note.text.contains("Durante."))
    let onDisk = quitOnDisk(root, "Progetti/Sospensione.md")
    #expect(onDisk?.contains("Prima.") == true)
    #expect(onDisk?.contains("Durante.") == false)
    #expect(controller.problems.contains {
        $0.hasPrefix("Chiusura della colonna annullata") && $0.contains("Progetti/Sospensione.md")
    })
    #expect(controller.focusedColumnIndex == 1, "the tab typed in is brought to the front")
    #expect(controller.focusedTab?.id == id)
    #expect(controller.closingColumns.isEmpty)
    controller.close()
}

@MainActor
@Test func aColumnLeftAloneDuringTheSavesIsNotClosed() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    controller.openNote(at: "Nexion.md")
    _ = try openDirty("Progetti/Sospensione.md", adding: "\nSalvata.\n", inColumn: 1, of: controller)
    let closingID = controller.columns[1].id
    let saved = Gate()
    let release = Gate()

    let closing = suspendedSavingClose(of: controller, after: saved, release: release)
    await saved.wait()
    // The other column, clean, closes at once: the one being closed is now the only column.
    let otherClosed = await controller.closeColumn(0) { _ in .cancel }
    #expect(otherClosed)
    release.open()
    let closed = await closing.value

    #expect(!closed, "the last column was closed")
    #expect(controller.columns.map(\.id) == [closingID])
    #expect(quitOnDisk(root, "Progetti/Sospensione.md")?.contains("Salvata.") == true)
    controller.close()
}

@MainActor
@Test func aColumnMovedDuringTheSavesIsClosedByIdentityNotByIndex() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    controller.openNote(at: "Nexion.md")
    _ = try openDirty("Progetti/Sospensione.md", adding: "\nSalvata.\n", inColumn: 1, of: controller)
    let closingID = controller.columns[1].id
    let saved = Gate()
    let release = Gate()

    let closing = suspendedSavingClose(of: controller, after: saved, release: release)
    await saved.wait()
    // The other column closes and a split puts a new column at index 1, where the one being
    // closed used to be; the one being closed now sits at index 0.
    let otherClosed = await controller.closeColumn(0) { _ in .cancel }
    #expect(otherClosed)
    controller.splitEditor()
    let newID = try #require(controller.columns.last?.id)
    #expect(controller.columns.map(\.id) == [closingID, newID])
    release.open()
    let closed = await closing.value

    #expect(closed)
    #expect(controller.columns.map(\.id) == [newID], "the column at the old index was closed instead")
    #expect(controller.focusedColumnIndex == 0)
    controller.close()
}
