import Foundation
import Testing
@testable import Pergamenum

// PG-341: a Contenitore scheda deleted outside the app while its inspector edit is unsaved used
// to cancel every Cmd+Q, because no write to it can land and the quit offered no «Non salvare»
// for the Contenitore. The quit question now names such a scheda like a note: «Non salvare»
// drops the edit and lets the app go; «Salva» cannot write it, so it cancels, and the next
// Cmd+Q asks again. PG-373 applies the same rule to a scheda still there whose write failed
// (end of file).

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

// MARK: PG-373: a scheda still there whose write keeps failing

// The scheda's folder is made read-only, so the guarded atomic write cannot create its
// temporary file and the editor's save reports `.failed`: the edit stays owed, and before
// PG-373 every Cmd+Q was cancelled by it with no «Non salvare» to give it up.

private let failedDescription = "Non si riesce a scrivere"

/// The folder's POSIX path, for its permissions.
private func folderPath(in vault: borrowing TemporaryVault) -> String {
    vault.root.appending(path: folder, directoryHint: .isDirectory).path(percentEncoded: false)
}

/// The scheda's bytes on disk.
private func schedaText(_ scheda: String, in vault: borrowing TemporaryVault) throws -> String {
    try String(contentsOf: vault.root.appending(path: scheda), encoding: .utf8)
}

/// A scheda with an inspector edit typed, its folder read-only. With `attempted`, the editor has
/// already tried to write it once and failed.
@MainActor
private func failingEdit(
    in vault: borrowing TemporaryVault, attempted: Bool = true
) async throws -> (ContenitoreHarness, String) {
    let scheda = try ContenitoreFixture.seed(stem: "20260314 Fattura", in: folder, vault: vault)
    let harness = try await ContenitoreHarness.make(root: vault.root, home: vault.stateBase)
    harness.contenitore.openEditor(for: scheda)
    let editor = try #require(harness.contenitore.editor)
    editor.draft.description = failedDescription
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folderPath(in: vault))
    if attempted {
        await editor.settle()
        #expect(editor.problem?.hasPrefix("Modifica non salvata") == true, "the write did fail")
    }
    return (harness, scheda)
}

private func restoreFolder(in vault: borrowing TemporaryVault) {
    restoreFolder(at: folderPath(in: vault))
}

private func restoreFolder(at path: String) {
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
}

@Test func aSchedaWhoseWriteFailedIsNamedWithASentenceOfItsOwn() {
    let copy = QuitReview(columns: [], failedSchede: ["Contenitore/2026/20260314 Fattura.md"]).copy

    #expect(copy.message == "Salvare le modifiche a «20260314 Fattura» prima di uscire?")
    #expect(copy.informative.contains(
        "La modifica alla scheda «20260314 Fattura» non si è potuta salvare: «Salva» riprova, «Non salvare» la scarta."
    ))
    #expect(!copy.informative.contains("non è più al suo posto"))
}

@Test func aGoneSchedaIsNotPromisedARetryAndAFailedOneIs() {
    let gonePath = "Contenitore/2026/20260301 Contratto.md"
    let failedPath = "Contenitore/2026/20260314 Fattura.md"
    let gone = QuitReview(columns: [], vanishedSchede: [gonePath])
    let failed = QuitReview(columns: [], failedSchede: [failedPath])
    let both = QuitReview(columns: [], vanishedSchede: [gonePath], failedSchede: [failedPath])

    #expect(both.schede == [
        QuitReview.Scheda(path: gonePath, problem: .gone),
        QuitReview.Scheda(path: failedPath, problem: .writeFailed),
    ], "the vanished ones first")
    #expect(!gone.copy.informative.contains("riprova"), "no write to a scheda that is gone can land")
    #expect(failed.copy.informative.contains("«Salva» riprova"), "an I/O failure keeps its sentence")
    #expect(!failed.copy.informative.contains("non è più al suo posto"))
}

/// The description the scheda holds on disk, what reverting the field brings back.
@MainActor
private func baselineDescription(of editor: ContenitoreEditor) -> String {
    ContenitoreInspectorModel.description(fromBody: NoteDocument.parse(editor.baselineText).body)
}

@MainActor
@Test func aFailedWriteRevertedToTheBaselineIsNotPinnedOnTheNextEdit() async throws {
    let vault = try TemporaryVault()
    defer { restoreFolder(in: vault) }
    let (harness, _) = try await failingEdit(in: vault)
    let editor = try #require(harness.contenitore.editor)
    #expect(editor.owesFailedWrite)

    editor.draft.description = baselineDescription(of: editor)

    #expect(editor.isSettled)
    #expect(!editor.lastWriteFailed, "a draft back at the baseline owes nothing")

    // A new edit nothing has tried to write yet: the diary phase writes it, the question does
    // not name it as a failed write.
    editor.draft.description = "Un'altra modifica, mai provata"

    #expect(!editor.isSettled)
    #expect(!editor.owesFailedWrite)
    #expect(harness.contenitore.failedSchedaEdits.isEmpty)
    #expect(QuitReview(
        columns: [],
        vanishedSchede: harness.contenitore.vanishedSchedaEdits,
        failedSchede: harness.contenitore.failedSchedaEdits
    ).isEmpty)
    harness.vault.close()
}

@MainActor
@Test func aBaselineThatMovedWithTheDiskClearsTheFailedWrite() async throws {
    let vault = try TemporaryVault()
    defer { restoreFolder(in: vault) }
    let (harness, scheda) = try await failingEdit(in: vault)
    let editor = try #require(harness.contenitore.editor)
    #expect(harness.contenitore.failedSchedaEdits == [scheda])

    // Another writer changes the scheda once the folder can be written again.
    restoreFolder(in: vault)
    try (editor.baselineText + "\nAggiunta da un altro programma.\n")
        .write(to: vault.root.appending(path: scheda), atomically: true, encoding: .utf8)
    editor.refreshFromDisk()

    #expect(editor.draft.description == failedDescription, "the person's edit is kept")
    #expect(!editor.isSettled, "and still owed, over the new baseline")
    #expect(!editor.lastWriteFailed, "a write over the new baseline has not been tried")
    #expect(harness.contenitore.failedSchedaEdits.isEmpty)
    harness.vault.close()
}

@MainActor
@Test func aSchedaWhoseWriteFailedIsNamedInTheQuitReview() async throws {
    let vault = try TemporaryVault()
    defer { restoreFolder(in: vault) }
    let (harness, scheda) = try await failingEdit(in: vault)

    #expect(harness.contenitore.vanishedSchedaEdits.isEmpty, "the scheda is still there")
    #expect(harness.contenitore.failedSchedaEdits == [scheda])
    let probe = SchedaQuitProbe()
    let quit = probe.coordinator(harness) { _ in .cancel }
    _ = quit.shouldTerminate()

    #expect(probe.asked.map { $0.schede } == [[QuitReview.Scheda(path: scheda, problem: .writeFailed)]])
    probe.hold.open()
    harness.vault.close()
}

@MainActor
@Test func nonSalvareOnASchedaWhoseWriteFailedLetsTheAppGoAndDiscardsTheEdit() async throws {
    let vault = try TemporaryVault()
    defer { restoreFolder(in: vault) }
    let (harness, scheda) = try await failingEdit(in: vault)
    let before = try schedaText(scheda, in: vault)
    let probe = SchedaQuitProbe()
    let quit = probe.coordinator(harness) { _ in .discard }

    #expect(quit.shouldTerminate() == .now)

    #expect(probe.asked.count == 1)
    #expect(!harness.contenitore.hasUnsettledEdits, "the edit is dropped, not owed")
    #expect(harness.contenitore.editor?.draft.description != failedDescription)
    #expect(try schedaText(scheda, in: vault) == before, "nothing was written")
    probe.hold.open()
    harness.vault.close()
}

@MainActor
@Test func annullaOnASchedaWhoseWriteFailedKeepsTheEdit() async throws {
    let vault = try TemporaryVault()
    defer { restoreFolder(in: vault) }
    let (harness, scheda) = try await failingEdit(in: vault)
    let probe = SchedaQuitProbe()
    let quit = probe.coordinator(harness) { _ in .cancel }

    #expect(quit.shouldTerminate() == .cancel)

    #expect(probe.revealedContenitore == [scheda])
    #expect(probe.replies.isEmpty)
    #expect(harness.contenitore.hasUnsettledEdits, "nothing is dropped")
    #expect(harness.contenitore.editor?.draft.description == failedDescription)
    probe.hold.open()
    harness.vault.close()
}

@MainActor
@Test func salvaOnASchedaWhoseWriteFailedRetriesItAndGoesWhenItLands() async throws {
    let vault = try TemporaryVault()
    defer { restoreFolder(in: vault) }
    let (harness, scheda) = try await failingEdit(in: vault)
    let probe = SchedaQuitProbe()
    let readOnly = folderPath(in: vault)
    let quit = probe.coordinator(harness) { _ in
        // Whatever made the write fail is gone by the time the person answers.
        restoreFolder(at: readOnly)
        return .save
    }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [true])
    #expect(!harness.contenitore.hasUnsettledEdits)
    #expect(try schedaText(scheda, in: vault).contains(failedDescription))
    probe.hold.open()
    harness.vault.close()
}

@MainActor
@Test func aWriteThatFailsDuringOneQuitIsAskedAboutOnTheNext() async throws {
    let vault = try TemporaryVault()
    defer { restoreFolder(in: vault) }
    let (harness, scheda) = try await failingEdit(in: vault, attempted: false)
    let probe = SchedaQuitProbe()
    let quit = probe.coordinator(harness) { _ in .discard }

    #expect(quit.shouldTerminate() == .later, "never tried yet: written in the diary phase, not asked")
    try await waitUntil { !probe.replies.isEmpty }
    #expect(probe.asked.isEmpty)
    #expect(probe.replies == [false], "the write failed, so this quit is cancelled")
    #expect(probe.revealedContenitore == [scheda])

    #expect(quit.shouldTerminate() == .now, "the next Cmd+Q is never blocked")
    #expect(probe.asked.map { $0.schede.map(\.path) } == [[scheda]])
    #expect(!harness.contenitore.hasUnsettledEdits)
    probe.hold.open()
    harness.vault.close()
}
