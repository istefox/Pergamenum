import Foundation
import Testing
@testable import Pergamenum

// PG-341: a Contenitore scheda deleted outside the app while its inspector edit is unsaved used
// to cancel every Cmd+Q, because no write to it can land and the quit offered no «Non salvare»
// for the Contenitore. The quit question now names such a scheda like a note: «Non salvare»
// drops the edit and lets the app go; «Salva» cannot write it, so it cancels, and the next
// Cmd+Q asks again.

@MainActor
private final class SchedaQuitProbe {
    var replies: [Bool] = []
    var asked: [QuitReview] = []
    var revealedContenitore: [String?] = []
    let hold = Gate()

    func coordinator(
        _ harness: ContenitoreHarness, answer: @escaping @MainActor (QuitReview) -> QuitReview.Answer
    ) -> QuitCoordinator {
        QuitCoordinator(
            vault: { harness.vault }, diary: { nil }, contenitore: { harness.contenitore },
            commitEditing: {},
            ask: { [unowned self] review in
                asked.append(review)
                return answer(review)
            },
            reply: { [unowned self] in replies.append($0) },
            reveal: { _ in },
            revealContenitore: { [unowned self] in revealedContenitore.append($0) },
            // Every timer waits: the caps must not decide these tests.
            sleep: { [unowned self] _ in await hold.wait() }
        )
    }
}

private let folder = "Contenitore/2026"

/// A scheda with an inspector edit typed and not saved, then deleted from under it.
@MainActor
private func vanishedEdit(in vault: borrowing TemporaryVault) async throws -> (ContenitoreHarness, String) {
    let scheda = try ContenitoreFixture.seed(stem: "20260314 Fattura", in: folder, vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)
    editor.draft.description = "Scritta su una scheda che non c'è più"
    try FileManager.default.removeItem(at: vault.root.appending(path: scheda))
    return (harness, scheda)
}

// MARK: The review (pure)

@Test func aVanishedSchedaIsNamedInTheQuestionWithItsOwnSentence() {
    let copy = QuitReview(columns: [], vanishedSchede: ["Contenitore/2026/20260314 Fattura.md"]).copy

    #expect(copy.message == "Salvare le modifiche a «20260314 Fattura» prima di uscire?")
    #expect(copy.discardLabel == "Non salvare")
    #expect(copy.informative.contains("La scheda «20260314 Fattura» non è più al suo posto"))
}

@Test func aNoteAndAVanishedSchedaAreCountedApart() {
    var column = EditorColumn()
    column.tabs = [NoteTab(note: VaultController.OpenNote(
        relativePath: "Nexion.md", title: "Nexion", text: "x", savedText: "y"
    ))]
    let review = QuitReview(columns: [column], vanishedSchede: ["Contenitore/2026/20260314 Fattura.md"])

    #expect(!review.isEmpty)
    #expect(review.copy.message == "Salvare le modifiche a 1 nota e 1 scheda prima di uscire?")
    #expect(review.copy.saveLabel == "Salva tutto")
    #expect(review.copy.informative.hasPrefix("«Nexion»\n«20260314 Fattura»"))
}

// MARK: The quit

@MainActor
@Test func nonSalvareOnAVanishedSchedaLetsTheAppGo() async throws {
    let vault = try TemporaryVault()
    let (harness, scheda) = try await vanishedEdit(in: vault)
    let probe = SchedaQuitProbe()
    let quit = probe.coordinator(harness) { _ in .discard }

    #expect(quit.shouldTerminate() == .now)

    #expect(probe.asked.map { $0.schede.map(\.path) } == [[scheda]])
    #expect(!harness.contenitore.hasUnsettledEdits, "the edit is dropped, not owed")
    #expect(!FileManager.default.fileExists(atPath: vault.root.appending(path: scheda).path(percentEncoded: false)))
    probe.hold.open()
    harness.vault.close()
}

@MainActor
@Test func salvaOnAVanishedSchedaCancelsAndTheNextQuitCanStillDiscard() async throws {
    let vault = try TemporaryVault()
    let (harness, scheda) = try await vanishedEdit(in: vault)
    let probe = SchedaQuitProbe()
    var answer = QuitReview.Answer.save
    let quit = probe.coordinator(harness) { _ in answer }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [false], "the write cannot land, so the quit does not pretend it did")
    #expect(probe.revealedContenitore == [scheda])
    #expect(harness.vault.problems.contains { $0.contains("Uscita annullata: modifiche alla scheda non salvate") })
    #expect(harness.contenitore.editor?.draft.description == "Scritta su una scheda che non c'è più")

    answer = .discard
    #expect(quit.shouldTerminate() == .now, "the next Cmd+Q is never blocked")
    #expect(probe.asked.count == 2)
    #expect(!harness.contenitore.hasUnsettledEdits)
    probe.hold.open()
    harness.vault.close()
}

@MainActor
@Test func annullaOnAVanishedSchedaOnlyBringsThePaneBack() async throws {
    let vault = try TemporaryVault()
    let (harness, scheda) = try await vanishedEdit(in: vault)
    let probe = SchedaQuitProbe()
    let quit = probe.coordinator(harness) { _ in .cancel }

    #expect(quit.shouldTerminate() == .cancel)

    #expect(probe.revealedContenitore == [scheda])
    #expect(harness.contenitore.hasUnsettledEdits, "nothing is dropped")
    probe.hold.open()
    harness.vault.close()
}

@MainActor
@Test func anEditToASchedaStillThereIsNotAskedAbout() async throws {
    let vault = try TemporaryVault()
    let scheda = try ContenitoreFixture.seed(stem: "20260314 Fattura", in: folder, vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)
    editor.draft.description = "Scritta in silenzio all'uscita"

    #expect(harness.contenitore.vanishedSchedaEdits.isEmpty)
    let probe = SchedaQuitProbe()
    let quit = probe.coordinator(harness) { _ in .cancel }
    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.asked.isEmpty)
    #expect(probe.replies == [true])
    probe.hold.open()
    harness.vault.close()
}
