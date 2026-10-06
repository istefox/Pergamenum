import Foundation
import Testing
@testable import Pergamenum

// ADR-0073 §D1/§D5/§D6/§D7, plan Task 3: one reply over three phases, driven with a fake
// `ask`, a recording `reply` and a `sleep` that records its calls and either returns at once
// or waits on a gate - over a real `VaultController` and `DiaryController` on a vault on disk.

/// Everything the coordinator hands to AppKit, recorded.
@MainActor
private final class QuitProbe {
    var replies: [Bool] = []
    var revealed: [NoteTab.ID?] = []
    var slept: [Duration] = []
    /// `slept` as it was when `ask` ran.
    var sleptWhenAsked: [Duration]?
    /// Durations whose sleep returns at once; every other one waits on its gate.
    var instant: Set<Duration> = []
    private var gates: [Duration: Gate] = [:]

    func gate(for duration: Duration) -> Gate {
        if let gate = gates[duration] { return gate }
        let gate = Gate()
        gates[duration] = gate
        return gate
    }

    /// Lets every held sleep finish, so a late cap can be shown to answer nothing.
    func openAllGates() {
        gates.values.forEach { $0.open() }
    }

    func coordinator(
        _ controller: VaultController,
        diary: DiaryController?,
        answer: @escaping @MainActor (QuitReview) -> QuitReview.Answer,
        commitEditing: @escaping @MainActor () -> Void = {},
        saveAll: (@MainActor (QuitReview) async -> QuitSaveReport)? = nil
    ) -> QuitCoordinator {
        QuitCoordinator(
            vault: { controller },
            diary: { diary },
            contenitore: { nil },
            commitEditing: commitEditing,
            ask: { [unowned self] review in
                sleptWhenAsked = slept
                return answer(review)
            },
            reply: { [unowned self] in replies.append($0) },
            reveal: { [unowned self] in revealed.append($0) },
            revealContenitore: { _ in },
            revealBoard: {},
            revealDiary: {},
            sleep: { [unowned self] duration in
                slept.append(duration)
                if instant.contains(duration) { return }
                await gate(for: duration).wait()
            },
            saveAll: saveAll
        )
    }
}

@MainActor
private func diary(for controller: VaultController) -> DiaryController {
    let diary = DiaryController(vault: controller)
    diary.show(testDay)
    return diary
}

// MARK: No dirty tab: as before (R-10)

@MainActor
@Test func withNoDirtyTabAndASettledDiaryTheAppGoesNowWithoutAsking() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    controller.openNote(at: "Nexion.md")
    let probe = QuitProbe()
    var asked = false
    let quit = probe.coordinator(controller, diary: diary(for: controller)) { _ in
        asked = true
        return .cancel
    }

    #expect(quit.shouldTerminate() == .now)
    #expect(!asked)
    #expect(probe.replies.isEmpty)
    controller.close()
}

@MainActor
@Test func withNoDirtyTabAPendingDiaryIsWaitedForAndRepliedToOnce() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let diary = diary(for: controller)
    diary.prose += "Frase del diario prima di uscire.\n"
    let probe = QuitProbe()
    let quit = probe.coordinator(controller, diary: diary) { _ in .cancel }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [true])
    #expect(diaryOnDisk(root)?.contains("Frase del diario prima di uscire.") == true)
    probe.openAllGates()
    await drain()
    #expect(probe.replies == [true])
    controller.close()
}

// MARK: An edit still open in a field editor

// A GFM table cell reaches the note's text only when its editing ends
// (`TableGridView.controlTextDidEndEditing`). `commitEditing` stands in for the key window
// giving up its first responder: it puts the cell's text in the buffer, as the grid's commit does.

@MainActor
@Test func aCellStillBeingEditedMakesACleanNoteAskInsteadOfGoingNow() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    controller.openNote(at: "Nexion.md")
    let id = try #require(controller.focusedTab?.id)
    #expect(controller.openNote?.hasUnsavedChanges == false)
    let probe = QuitProbe()
    var commits = 0
    var reviewed: QuitReview?
    let quit = probe.coordinator(
        controller, diary: diary(for: controller),
        answer: { review in
            #expect(commits == 1, "the review was built before the open edit ended")
            reviewed = review
            return .cancel
        },
        commitEditing: {
            commits += 1
            controller.updateOpenNoteText((controller.openNote?.text ?? "") + "\n| cella |\n")
        }
    )

    #expect(quit.shouldTerminate() == .cancel)
    #expect(commits == 1)
    #expect(reviewed?.entries.map(\.tabID) == [id])
    #expect(reviewed?.entries.first?.text.contains("| cella |") == true)
    controller.close()
}

@MainActor
@Test func salvaTuttoWritesTheCellThatWasStillBeingEdited() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nGià scritto.\n", inColumn: 0, of: controller)
    let probe = QuitProbe()
    let quit = probe.coordinator(
        controller, diary: diary(for: controller),
        answer: { _ in .save },
        commitEditing: {
            controller.updateOpenNoteText((controller.openNote?.text ?? "") + "| cella |\n")
        }
    )

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [true])
    #expect(quitOnDisk(root, "Nexion.md")?.contains("Già scritto.\n| cella |") == true)
    probe.openAllGates()
    await drain()
    #expect(probe.replies == [true])
    controller.close()
}

// MARK: The question (R-01, R-03, R-04, R-09)

@MainActor
@Test func noTimerRunsWhileTheQuestionIsOpen() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    let diary = diary(for: controller)
    diary.prose += "Diario.\n"
    _ = try openDirty("Nexion.md", adding: "\nx\n", inColumn: 0, of: controller)
    let probe = QuitProbe()
    let quit = probe.coordinator(controller, diary: diary) { _ in .discard }

    #expect(quit.shouldTerminate() == .later)

    #expect(probe.sleptWhenAsked == [])
    try await waitUntil { !probe.replies.isEmpty }
    #expect(probe.slept == [QuitCoordinator.diaryCap])
    controller.close()
}

@MainActor
@Test func theQuestionCoversEveryDirtyTabOfBothColumns() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    let a = try openDirty("Nexion.md", adding: "\nx\n", inColumn: 0, of: controller)
    let b = try openDirty("Progetti/Pressa.md", adding: "\ny\n", inColumn: 0, of: controller)
    let c = try openDirty("Progetti/Sospensione.md", adding: "\nz\n", inColumn: 1, of: controller)
    let probe = QuitProbe()
    var shown: QuitReview?
    let quit = probe.coordinator(controller, diary: nil) { review in
        shown = review
        return .cancel
    }

    _ = quit.shouldTerminate()

    #expect(shown?.entries.map(\.tabID) == [a, b, c])
    controller.close()
}

@MainActor
@Test func annullaCancelsWritesNothingAndReveals() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let id = try openDirty("Nexion.md", adding: "\nNon ancora.\n", inColumn: 0, of: controller)
    let before = quitOnDisk(root, "Nexion.md")
    let probe = QuitProbe()
    let quit = probe.coordinator(controller, diary: diary(for: controller)) { _ in .cancel }

    #expect(quit.shouldTerminate() == .cancel)

    await drain()
    #expect(quitOnDisk(root, "Nexion.md") == before)
    #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == true)
    #expect(probe.revealed == [nil])
    #expect(probe.replies.isEmpty)
    controller.close()
}

@MainActor
@Test func nonSalvareGoesNowAndWritesNothing() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nDa scartare.\n", inColumn: 0, of: controller)
    let before = quitOnDisk(root, "Nexion.md")
    let probe = QuitProbe()
    let quit = probe.coordinator(controller, diary: diary(for: controller)) { _ in .discard }

    #expect(quit.shouldTerminate() == .now)

    await drain()
    #expect(quitOnDisk(root, "Nexion.md") == before)
    #expect(probe.replies.isEmpty)
    controller.close()
}

// MARK: «Salva tutto» (R-05, R-06, R-07)

@MainActor
@Test func salvaTuttoWritesBothColumnsAndRepliesTrueOnce() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nSinistra salvata.\n", inColumn: 0, of: controller)
    _ = try openDirty("Progetti/Sospensione.md", adding: "\nDestra salvata.\n", inColumn: 1, of: controller)
    let probe = QuitProbe()
    let quit = probe.coordinator(controller, diary: diary(for: controller)) { _ in .save }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [true])
    #expect(quitOnDisk(root, "Nexion.md")?.contains("Sinistra salvata.") == true)
    #expect(quitOnDisk(root, "Progetti/Sospensione.md")?.contains("Destra salvata.") == true)
    probe.openAllGates()
    await drain()
    #expect(probe.replies == [true])
    controller.close()
}

@MainActor
@Test func aFailedSaveCancelsTheQuitAndRevealsTheTab() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let id = try openDirty("Progetti/Pressa.md", adding: "\nNon scrivibile.\n", inColumn: 0, of: controller)
    let probe = QuitProbe()
    let quit = probe.coordinator(controller, diary: diary(for: controller)) { _ in .save }

    let reply = try await withReadOnlyFolder(root, "Progetti") {
        let reply = quit.shouldTerminate()
        try await waitUntil { !probe.replies.isEmpty }
        return reply
    }

    #expect(reply == .later)
    #expect(probe.replies == [false])
    #expect(probe.revealed == [id])
    #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == true)
    #expect(controller.problems.contains { $0.contains("Progetti/Pressa.md") })
    controller.close()
}

@MainActor
@Test func aConflictedTabIsLeftTheOthersAreSavedAndTheQuitIsCancelled() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let conflicted = try openDirty("Nexion.md", adding: "\nMia.\n", inColumn: 0, of: controller)
    _ = try openDirty("Progetti/Pressa.md", adding: "\nSalvata.\n", inColumn: 1, of: controller)
    controller.updateTabs(showing: "Nexion.md") { $0.note.externalChangePending = .text("altro") }
    let before = quitOnDisk(root, "Nexion.md")
    let probe = QuitProbe()
    let quit = probe.coordinator(controller, diary: diary(for: controller)) { _ in .save }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [false])
    #expect(probe.revealed == [conflicted])
    #expect(quitOnDisk(root, "Progetti/Pressa.md")?.contains("Salvata.") == true)
    #expect(quitOnDisk(root, "Nexion.md") == before)
    controller.close()
}

// MARK: What the answer covers (R-08)

@MainActor
@Test func typingThatRacedNonSalvareCancelsTheQuit() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    let id = try openDirty("Nexion.md", adding: "\nPrima.\n", inColumn: 0, of: controller)
    let probe = QuitProbe()
    let quit = probe.coordinator(controller, diary: diary(for: controller)) { _ in
        controller.updateTabs(showing: "Nexion.md") { $0.note.text += "Digitato durante la domanda.\n" }
        return .discard
    }

    #expect(quit.shouldTerminate() == .cancel)
    #expect(probe.revealed == [id])
    #expect(probe.replies.isEmpty)
    controller.close()
}

// MARK: The caps (R-09)

@MainActor
@Test func theNoteSaveCapCancelsOnceAndALateSaveAnswersNothing() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nx\n", inColumn: 0, of: controller)
    let probe = QuitProbe()
    probe.instant = [QuitReview.noteSaveCap]
    let hung = Gate()
    let quit = probe.coordinator(
        controller, diary: diary(for: controller),
        answer: { _ in .save },
        saveAll: { _ in
            await hung.wait()
            return QuitSaveReport()
        }
    )

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [false])
    #expect(controller.problems.contains { $0.contains("non è terminato") })
    hung.open()
    probe.openAllGates()
    await drain()
    #expect(probe.replies == [false])
    controller.close()
}

// ADR-0073 departure 17: on «Salva tutto» the diary settles before the notes are written, and
// the notes' cap starts only once it has (or once its own cap has won).

@MainActor
@Test func theDiarySettlesBeforeTheSavesAndOneReplyFollows() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let diary = diary(for: controller)
    _ = try openDirty("Nexion.md", adding: "\nNota salvata.\n", inColumn: 0, of: controller)
    diary.prose += "Diario prima delle note.\n"
    let probe = QuitProbe()
    let quit = probe.coordinator(controller, diary: diary) { _ in .save }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [true])
    #expect(probe.slept == [QuitCoordinator.diaryCap, QuitReview.noteSaveCap])
    #expect(diaryOnDisk(root)?.contains("Diario prima delle note.") == true)
    #expect(quitOnDisk(root, "Nexion.md")?.contains("Nota salvata.") == true)
    probe.openAllGates()
    await drain()
    #expect(probe.replies == [true])
    controller.close()
}

@MainActor
@Test func theDiaryCapWinningBeforeTheSavesStillSavesTheNotes() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let diary = diary(for: controller)
    let held = Gate()
    diary.testOnlyWriteHook = { phase in
        if phase == .willWrite { await held.wait() }
    }
    _ = try openDirty("Nexion.md", adding: "\nNota salvata comunque.\n", inColumn: 0, of: controller)
    diary.prose += "Diario bloccato.\n"
    let probe = QuitProbe()
    probe.instant = [QuitCoordinator.diaryCap]
    let quit = probe.coordinator(controller, diary: diary) { _ in .save }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    // Fail-open, as ADR-0060 §D2: the notes are saved, and the phase after them waits for the
    // still-unsettled diary once more under the same cap before letting go.
    #expect(probe.replies == [true])
    #expect(probe.slept == [QuitCoordinator.diaryCap, QuitReview.noteSaveCap, QuitCoordinator.diaryCap])
    #expect(quitOnDisk(root, "Nexion.md")?.contains("Nota salvata comunque.") == true)
    held.open()
    probe.openAllGates()
    await drain()
    #expect(probe.replies == [true])
    controller.close()
}

@MainActor
@Test func salvaTuttoLetsTheDiaryWriteTheDayFileADirtyTabShowsAndCancels() async throws {
    // The Diario owes a write and a tab shows the same day file, dirty. The diary's guarded
    // write lands first; the tab hears it (the banner), is left unwritten, and the quit is
    // cancelled on it - where the old order wrote the tab, refused the diary as stale and quit
    // with the diary's text gone.
    let vault = try TemporaryVault()
    let root = vault.root
    try vault.write(quitNote("Testo iniziale del giorno."), to: "Diario/20260811.md")
    let controller = try await quitController(vault)
    let diary = diary(for: controller)
    let dayTab = try openDirty("Diario/20260811.md", adding: "\nDalla tab.\n", inColumn: 0, of: controller)
    diary.prose += "Dal Diario.\n"
    let probe = QuitProbe()
    let quit = probe.coordinator(controller, diary: diary) { _ in .save }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [false])
    #expect(probe.revealed == [dayTab])
    #expect(diaryOnDisk(root)?.contains("Dal Diario.") == true)
    #expect(diaryOnDisk(root)?.contains("Dalla tab.") == false)
    #expect(diary.saveState == .saved)
    let tab = try #require(controller.tab(withID: dayTab))
    #expect(tab.note.hasUnsavedChanges)
    #expect(tab.note.text.contains("Dalla tab."))
    #expect(tab.note.externalChangePending != nil)
    probe.openAllGates()
    await drain()
    #expect(probe.replies == [false])
    controller.close()
}

// MARK: A split copy of the note (ADR-0073 departure 15)

@MainActor
@Test func salvaTuttoOverANoteSplitIntoBothColumnsQuitsWithoutAFalseConflict() async throws {
    // Typed first, split second: both columns hold the same unsaved text. Saving the left one
    // writes exactly the right one's text, which must not read as a change on disk.
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    controller.openNote(at: "Nexion.md")
    controller.updateOpenNoteText((controller.openNote?.text ?? "") + "\nIn due colonne.\n")
    controller.splitEditor()
    try #require(controller.columns.count == 2)
    let probe = QuitProbe()
    var shown: QuitReview?
    let quit = probe.coordinator(controller, diary: diary(for: controller)) { review in
        shown = review
        return .save
    }

    #expect(quit.shouldTerminate() == .later)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(shown?.entries.count == 2)
    #expect(probe.replies == [true])
    #expect(probe.revealed.isEmpty)
    #expect(quitOnDisk(root, "Nexion.md")?.contains("In due colonne.") == true)
    #expect(controller.columns.allSatisfy { $0.tabs.allSatisfy { $0.note.externalChangePending == nil } })
    probe.openAllGates()
    await drain()
    controller.close()
}

// MARK: Re-entrancy (ADR-0073 departure 16)

@MainActor
@Test func aSecondQuitWhileAReplyIsOwedAnswersLaterAndStartsNothing() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nSalvata una volta.\n", inColumn: 0, of: controller)
    let probe = QuitProbe()
    let hung = Gate()
    var asks = 0
    var saves = 0
    let quit = probe.coordinator(
        controller, diary: diary(for: controller),
        answer: { _ in
            asks += 1
            return .save
        },
        saveAll: { review in
            saves += 1
            await hung.wait()
            return await controller.saveForQuit(review)
        }
    )

    #expect(quit.shouldTerminate() == .later)
    #expect(quit.shouldTerminate() == .later)
    #expect(asks == 1)

    hung.open()
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [true])
    #expect(saves == 1)
    #expect(quitOnDisk(root, "Nexion.md")?.contains("Salvata una volta.") == true)
    probe.openAllGates()
    await drain()
    #expect(probe.replies == [true])
    #expect(probe.slept.filter { $0 == QuitReview.noteSaveCap }.count == 1)
    controller.close()
}

@MainActor
@Test func aQuitArrivingWhileTheQuestionIsOnScreenIsCancelledAndTheFirstGoesOn() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try openDirty("Nexion.md", adding: "\nDopo la domanda.\n", inColumn: 0, of: controller)
    let probe = QuitProbe()
    var nested: QuitReply?
    var asks = 0
    var quit: QuitCoordinator?
    quit = probe.coordinator(controller, diary: diary(for: controller)) { _ in
        asks += 1
        // Without the re-entrancy guard the nested call asks again; stop the recursion there
        // so the regression reads as `asks == 2`, not as a stack overflow.
        guard asks == 1 else { return .cancel }
        nested = quit?.shouldTerminate()
        return .save
    }

    #expect(quit?.shouldTerminate() == .later)
    #expect(nested == .cancel)
    #expect(asks == 1)
    try await waitUntil { !probe.replies.isEmpty }

    #expect(probe.replies == [true])
    #expect(quitOnDisk(root, "Nexion.md")?.contains("Dopo la domanda.") == true)
    probe.openAllGates()
    await drain()
    #expect(probe.replies == [true])
    controller.close()
}
