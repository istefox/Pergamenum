import Foundation
import Testing
@testable import Pergamenum

// The layer both connectors sit on (ADR-0007 §D2): the readings that turn a string into
// a date or a task, the payload shapes that are the contract, and the writes with their
// guardrails.
//
// Worth testing here rather than through either binary. `perg` and `pergamenum-mcp`
// differ only in how they are spoken to; what they do to a vault is this file.

private let note = """
---
date: 2026-08-11
tags:
  - type-note
---

Corpo, con un [[Link che non esiste]].

- [ ] Alfa >2026-08-20
- [ ] Beta !2026-08-21
- [x] Gamma
"""

@MainActor
private func openVault(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(note, to: "Nota.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

// MARK: - Reading what a caller wrote

@Test func aDateIsReadInBothFormsAndRefusedInAnyOther() throws {
    #expect(try VaultAPI.day("2026-08-20") == CalendarDate(iso: "2026-08-20"))
    #expect(try VaultAPI.day("20260820") == CalendarDate(iso: "2026-08-20"))
    // Absent means today, which is what every command that takes a day defaults to.
    #expect(try VaultAPI.day(nil) == .today)
    #expect(try VaultAPI.day("") == .today)

    #expect(throws: ConnectorError.self) { try VaultAPI.day("20 agosto") }
    #expect(throws: ConnectorError.self) { try VaultAPI.day("2026-13-01") }
}

@Test func aViewIsNamedInEitherLanguageAndRefusedOtherwise() throws {
    #expect(try VaultAPI.taskView("inbox") == .inbox)
    #expect(try VaultAPI.taskView("oggi") == .today)
    #expect(try VaultAPI.taskView("prossimi") == .upcoming)
    #expect(try VaultAPI.taskView("progetto") == .byProject)
    // Absent is `all`, so `perg task list` with no flags lists everything.
    #expect(try VaultAPI.taskView(nil) == .all)

    #expect(throws: ConnectorError.self) { try VaultAPI.taskView("scadute") }
}

@Test func anHourIsRefusedWhenItIsNotOne() throws {
    #expect(try VaultAPI.minutesFromMidnight("09:30") == 570)
    #expect(try VaultAPI.minutesFromMidnight("00:00") == 0)

    // 24:00 is a time nobody means: the day it belongs to is the next one.
    #expect(throws: ConnectorError.self) { try VaultAPI.minutesFromMidnight("24:00") }
    #expect(throws: ConnectorError.self) { try VaultAPI.minutesFromMidnight("09:60") }
    #expect(throws: ConnectorError.self) { try VaultAPI.minutesFromMidnight("9") }
}

@MainActor
@Test func aTaskIsFoundByTextAndExactlyByPathAndLine() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)

    #expect(try VaultAPI.task(session, matching: "Alfa").text == "Alfa")
    // `percorso:riga` is one-based, as an editor counts and as every payload reports.
    let line = try VaultAPI.task(session, matching: "Alfa").lineIndex + 1
    #expect(try VaultAPI.task(session, matching: "Nota.md:\(line)").text == "Alfa")

    #expect(throws: ConnectorError.self) { try VaultAPI.task(session, matching: "Delta") }
    #expect(throws: ConnectorError.self) { try VaultAPI.task(session, matching: "Nota.md:999") }
}

@MainActor
@Test func aPhraseMatchingSeveralTasksIsRefusedRatherThanGuessed() async throws {
    let vault = try TemporaryVault()
    try vault.write(
        "---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\n- [ ] Chiamare Rossi\n- [ ] Chiamare Bianchi\n",
        to: "Chiamate.md"
    )
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()

    // Completing the wrong task is silent, and whoever asked would find out much later.
    #expect(throws: ConnectorError.self) { try VaultAPI.task(session, matching: "Chiamare") }
}

// MARK: - The shapes that are the contract

@MainActor
@Test func aTaskPayloadCountsItsLineTheWayAnEditorDoes() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)

    let tasks = try VaultAPI.tasks(session, view: "all", on: nil, includingCompleted: true)
    let alfa = try #require(tasks.first { $0.text == "Alfa" })

    // Five lines of frontmatter, a blank, the body, a blank, then the task: line 9 as an
    // editor shows it, not the 8 the parser counts from zero.
    #expect(alfa.line == 9)
    #expect(alfa.path == "Nota.md")
    #expect(alfa.state == " ")
    #expect(alfa.scheduled == "2026-08-20")
    // The line the task is on, one-based: `Nota.md:9` is what `task done` takes back.
    #expect(try VaultAPI.task(session, matching: "Nota.md:\(alfa.line)").text == "Alfa")

    let done = try #require(tasks.first { $0.text == "Gamma" })
    #expect(done.state == "x")
}

@MainActor
@Test func completedTasksAreHiddenUnlessAskedFor() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)

    let open = try VaultAPI.tasks(session, view: "all", on: nil, includingCompleted: false)
    #expect(!open.contains { $0.text == "Gamma" })

    let all = try VaultAPI.tasks(session, view: "all", on: nil, includingCompleted: true)
    #expect(all.contains { $0.text == "Gamma" })
}

@MainActor
@Test func linksAreReportedWithTheDanglingOnesKeptApart() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)

    let links = try VaultAPI.links(session, at: "Nota.md")
    #expect(links.resolved.isEmpty)
    #expect(links.unresolved == ["Link che non esiste"])

    // And the same fact from the other end of the vault.
    let unresolved = VaultAPI.unresolvedLinks(session)
    #expect(unresolved.count == 1)
    #expect(unresolved.first?.sources == ["Nota.md"])
}

@MainActor
@Test func readingAMissingNoteIsARefusalAndNotAnEmptyAnswer() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)

    #expect(throws: ConnectorError.self) { try VaultAPI.note(session, at: "Assente.md") }
    #expect(throws: ConnectorError.self) { try VaultAPI.links(session, at: "Assente.md") }
    #expect(throws: ConnectorError.self) { try VaultAPI.lint(session, at: "Assente.md") }
}

@MainActor
@Test func aVaultWithoutItsVocabulariesSaysSoInsteadOfPassing() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)

    // No `.pergamenum/vocabolari.json`, so the tag rules had nothing to judge against.
    // A clean report here means less than it looks, and the payload admits it.
    let report = try VaultAPI.lint(session, at: nil)
    #expect(report.checked == 1)
    #expect(report.warning != nil)
}

@MainActor
@Test func theEncoderIsTheOneBothConnectorsUse() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)

    let json = try ConnectorJSON.encode(try VaultAPI.note(session, at: "Nota.md"))
    // Sorted keys, so two runs diff cleanly; slashes unescaped, so a path stays readable.
    let note = try #require(json.range(of: "\"note\""))
    let text = try #require(json.range(of: "\"text\""))
    #expect(note.lowerBound < text.lowerBound)
    #expect(!json.contains("\\/"))
}

// The two category reads (ADR-0047 §D9, R-09) live in `Tests/CategoryConnectorTests.swift`,
// split out once this file crossed SwiftLint's `file_length` warning.

// MARK: - Writing, and the guardrails around it

@MainActor
@Test func armingForARehearsalKeepsTheJournalOutOfIt() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)

    VaultAPI.arm(session, command: "add_task", dryRun: true)
    // Nothing happened, and a journal entry saying otherwise would be a lie in the one
    // file whose job is to be trusted.
    #expect(session.journal == nil)
    #expect(session.isDryRun)

    let summary = try await VaultAPI.addTask(
        session, text: "Delta", scheduled: nil, due: nil, note: "Nota.md"
    )
    #expect(!summary.applied)
    #expect(try #require(summary.diff).contains("+- [ ] Delta"))

    let onDisk = try String(contentsOf: vault.root.appending(path: "Nota.md"), encoding: .utf8)
    #expect(!onDisk.contains("Delta"), "una prova non deve toccare il file")
}

@MainActor
@Test func aRealWriteIsAppliedAndRecorded() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)

    VaultAPI.arm(session, command: "add_task", dryRun: false)
    let summary = try await VaultAPI.addTask(
        session, text: "Delta", scheduled: "2026-08-22", due: nil, note: "Nota.md"
    )
    #expect(summary.applied)
    // No diff on an applied write: the file already says what the diff would have said.
    #expect(summary.diff == nil)

    let onDisk = try String(contentsOf: vault.root.appending(path: "Nota.md"), encoding: .utf8)
    #expect(onDisk.contains("- [ ] Delta >2026-08-22"))

    let log = try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: nil)
    #expect(log.count == 1)
    #expect(log.first?.command == "add_task")
    #expect(log.first?.created == false)
}

@MainActor
@Test func aWriteIsUndoneAndRefusedOnceTheFileHasMovedOn() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)

    VaultAPI.arm(session, command: "append_to_note", dryRun: false)
    _ = try await VaultAPI.appendToNote(session, at: "Nota.md", text: "Aggiunta")
    let id = try #require(try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: nil).last?.id)

    // Somebody else edits the file after that write.
    try vault.write(note + "\n\nScritto da qualcun altro\n", to: "Nota.md")
    await session.rescan()
    VaultAPI.arm(session, command: "undo_write", dryRun: false)
    await #expect(throws: ConnectorError.self) { try await VaultAPI.undo(session, id: id) }

    let onDisk = try String(contentsOf: vault.root.appending(path: "Nota.md"), encoding: .utf8)
    #expect(onDisk.contains("Scritto da qualcun altro"), "un undo rifiutato non tocca niente")
}

@MainActor
@Test func anUndoPutsTheFileBackWhenNobodyElseTouchedIt() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    let before = try String(contentsOf: vault.root.appending(path: "Nota.md"), encoding: .utf8)

    VaultAPI.arm(session, command: "append_to_note", dryRun: false)
    _ = try await VaultAPI.appendToNote(session, at: "Nota.md", text: "Aggiunta")
    let id = try #require(try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: nil).last?.id)

    VaultAPI.arm(session, command: "undo_write", dryRun: false)
    _ = try await VaultAPI.undo(session, id: id)

    #expect(try String(contentsOf: vault.root.appending(path: "Nota.md"), encoding: .utf8) == before)
}

@MainActor
@Test func undoingACreationIsDeclinedRatherThanDeletingTheFile() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)

    VaultAPI.arm(session, command: "create_note", dryRun: false)
    _ = try await VaultAPI.createNote(session, title: "Nuova", folder: nil, topic: nil, date: nil)
    let id = try #require(try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: nil).last?.id)

    VaultAPI.arm(session, command: "undo_write", dryRun: false)
    // This command does not delete. Saying so beats removing a file on a model's say-so.
    await #expect(throws: ConnectorError.self) { try await VaultAPI.undo(session, id: id) }
    #expect(FileManager.default.fileExists(atPath: vault.root.appending(path: "Nuova.md").path))
}

// MARK: - ADR-0063 §D1: a malformed `limit` is one usage sentence, and `0` answers empty

/// The sentence a refused `limit` produces, read off the rule itself so every test
/// below compares against the same words.
private func limitSentence(_ attempt: () throws -> Any?) -> ConnectorError? {
    do {
        _ = try attempt()
        return nil
    } catch let error as ConnectorError {
        return error
    } catch {
        return nil
    }
}

@Test func aNegativeLimitIsOneUsageSentence() throws {
    let error = try #require(limitSentence { try VaultAPI.checkedLimit(-1) })
    #expect(error.isUsage)
    #expect(error.description.contains("limit"))
    #expect(error.description.contains("-1"))
    // Absent and zero are both legal.
    #expect(try VaultAPI.checkedLimit(nil) == nil)
    #expect(try VaultAPI.checkedLimit(0) == 0)
}

@Test func unreadableLimitTextIsTheSameSentence() throws {
    let unreadable = try #require(limitSentence { try VaultAPI.limit(parsing: "abc") })
    #expect(unreadable.isUsage)
    #expect(unreadable.description.contains("abc"))
    // An empty value is not «no limit given»: the caller typed the option and left it blank.
    let empty = try #require(limitSentence { try VaultAPI.limit(parsing: "") })
    #expect(empty.isUsage)

    // The same sentence as a negative number, apart from the raw value it quotes.
    let negative = try #require(limitSentence { try VaultAPI.checkedLimit(-1) })
    #expect(unreadable.description.replacingOccurrences(of: "abc", with: "-1") == negative.description)

    // `-1` is a number: the text rule reads it and leaves the refusal to `checkedLimit`.
    #expect(try VaultAPI.limit(parsing: "-1") == -1)
    #expect(try VaultAPI.limit(parsing: nil) == nil)
}

@MainActor
@Test func journalLogRefusesANegativeLimitBeforeAnyDiskWork() throws {
    // A vault this process never opened: the state lookup would say «vault mai aperto».
    // The usage error must win, because it is the caller's mistake whatever the vault.
    let vault = try TemporaryVault()
    let error = try #require(limitSentence {
        try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: -1)
    })
    let expected = try #require(limitSentence { try VaultAPI.checkedLimit(-1) })
    #expect(error.isUsage)
    #expect(error.description == expected.description)
}

@MainActor
@Test func searchRefusesANegativeLimit() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    let error = try #require(limitSentence { try VaultAPI.search(session, "Corpo", limit: -1) })
    let expected = try #require(limitSentence { try VaultAPI.checkedLimit(-1) })
    #expect(error.isUsage)
    #expect(error.description == expected.description)
}

@MainActor
@Test func searchWithLimitZeroAnswersEmpty() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    // The query matches: the positive control proves `0` is what empties the answer.
    #expect(try VaultAPI.search(session, "Corpo", limit: nil).count == 1)
    #expect(try VaultAPI.search(session, "Corpo", limit: 0).isEmpty)
}

@MainActor
@Test func journalLogWithLimitZeroAnswersEmpty() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "append_to_note", dryRun: false)
    _ = try await VaultAPI.appendToNote(session, at: "Nota.md", text: "Aggiunta")
    #expect(try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: nil).count == 1)
    #expect(try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: 0).isEmpty)
}

@MainActor
@Test func journalLogRefusesANegativeLimitOnAnOpenedVault() async throws {
    // Before ADR-0063 this reached `suffix(-1)` and trapped the process: written only
    // together with the guard, so it can never take the test host down with it.
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "append_to_note", dryRun: false)
    _ = try await VaultAPI.appendToNote(session, at: "Nota.md", text: "Aggiunta")

    let error = try #require(limitSentence {
        try VaultAPI.journalLog(at: vault.root, base: vault.stateBase, limit: -1)
    })
    let expected = try #require(limitSentence { try VaultAPI.checkedLimit(-1) })
    #expect(error.isUsage)
    #expect(error.description == expected.description)
}

// MARK: - Task 5 (R-02, R-05, R-06): a refusal folds into `failures`, with its own sentence

@Test func aRefusalFoldsIntoFailuresWithItsOwnSentenceRatherThanANewKey() {
    // `foldedFailures` is the one seam `VaultAPI.renameNote`/`moveNote` share (ADR-0046 §D4).
    // A genuine refusal cannot be forced through either deterministically (§D11 - the same
    // synchronous-plan-then-write constraint `Tests/VaultSessionFileOperationsTests.swift`'s
    // Task 4 tests name), so this drives the fold directly with a hand-built
    // `NoteFileOperations.Outcome` rather than racing a concurrent write.
    let outcome = NoteFileOperations.Outcome(
        newPath: "Nuovo titolo.md",
        rewrittenPaths: ["Altra.md"],
        failures: ["Board.canvas: non leggibile come testo"],
        refusals: ["Terza.md"]
    )

    let failures = VaultAPI.foldedFailures(outcome)

    #expect(failures == [
        "Board.canvas: non leggibile come testo",
        VaultWriteRefusal.movedOn("Terza.md").description,
    ])
}

@Test func aCleanOutcomeWithNoRefusalsFoldsToExactlyItsOwnFailures() {
    let outcome = NoteFileOperations.Outcome(newPath: "Nuovo titolo.md", failures: ["Board.canvas: errore"])

    #expect(VaultAPI.foldedFailures(outcome) == outcome.failures)
}

@MainActor
@Test func aTitleTheRulesRejectIsRefusedAndNotCorrected() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "create_note", dryRun: false)

    await #expect(throws: ConnectorError.self) {
        try await VaultAPI.createNote(session, title: "questo/non va", folder: nil, topic: nil, date: nil)
    }
    // And the sentence is one a person can read: interpolating the array of violations
    // would put the module name in it.
    do {
        _ = try await VaultAPI.createNote(session, title: "questo/non va", folder: nil, topic: nil, date: nil)
    } catch let refusal as ConnectorError {
        #expect(!refusal.description.contains("Pergamenum.NoteName"))
        #expect(refusal.description.contains("containsForbiddenCharacter"))
    }
}

@MainActor
@Test func aTaskInANoteThatDoesNotExistIsRefused() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "add_task", dryRun: false)

    // Inventing a note from a task is how a vault fills with files nobody meant to make.
    await #expect(throws: ConnectorError.self) {
        try await VaultAPI.addTask(session, text: "Delta", scheduled: nil, due: nil, note: "Assente.md")
    }
}

@MainActor
@Test func aBlockOnAnOccupiedHourMovesAndSaysSo() async throws {
    let vault = try TemporaryVault()
    let session = try await openVault(vault)
    VaultAPI.arm(session, command: "add_time_block", dryRun: false)

    _ = try await VaultAPI.addTimeBlock(
        session, title: "Primo", at: "09:00", minutes: 60, on: "2026-08-20"
    )
    let second = try await VaultAPI.addTimeBlock(
        session, title: "Secondo", at: "09:00", minutes: 30, on: "2026-08-20"
    )

    // It moved rather than overlapped, and the payload says so rather than leaving it to
    // be discovered on the timeline later.
    #expect(second.note != nil)
    let day = try VaultAPI.day(session, on: "2026-08-20")
    #expect(day.blocks.count == 2)
    #expect(day.blocks.map(\.start) == ["09:00", "10:00"])
}
