import Foundation
import Testing
@testable import Pergamenum

// ADR-0043 batch 1, Tasks 1–3, R-03: awaitable writes retain their existing outcomes.
// The tester may change tests only. These overloads reject an unconverted signature at
// runtime, without adding production stubs or making the test target fail to compile.
// A plain assignment to an async function would silently promote a synchronous writer.
private enum CascadeContractError: Error {
    case synchronousWriter
}

@MainActor
private func cascadeAsync<each Argument, Result>(
    _ function: @escaping @MainActor (repeat each Argument) throws -> Result
) throws -> @MainActor (repeat each Argument) async throws -> Result {
    throw CascadeContractError.synchronousWriter
}

@MainActor
private func cascadeAsync<each Argument, Result>(
    _ function: @escaping @MainActor (repeat each Argument) async throws -> Result
) throws -> @MainActor (repeat each Argument) async throws -> Result {
    function
}

private func cascadeNote(_ body: String) -> String {
    "---\ndate: 2026-09-13\ntags:\n  - type-note\n---\n\n\(body)\n"
}

@MainActor
private func cascadeSession(_ vault: borrowing TemporaryVault) async -> VaultSession {
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    session.journal = session.journalOnDisk
    return session
}

// Control for the signature guard: it must distinguish real async functions from promotion.
@MainActor
@Test func cascadeSignatureGuardRejectsSyncAndAcceptsAsync() async throws {
    func synchronous(_ value: Int) -> Int { value }
    func asynchronous(_ value: Int) async -> Int { value }

    #expect(throws: CascadeContractError.self) {
        _ = try cascadeAsync(synchronous)
    }
    let accepted = try cascadeAsync(asynchronous)
    #expect(try await accepted(42) == 42)
}

// R-03, Task 1: capture and task mutation return only after their writes are observable.
@MainActor
@Test func cascadeCaptureThenCompletionPersistsBothOutcomes() async throws {
    let vault = try TemporaryVault()
    let session = await cascadeSession(vault)
    let capture = try cascadeAsync(session.captureTask)
    let apply = try cascadeAsync(session.apply(_:to:))
    let draft = VaultSession.TaskDraft(text: "Deliver report", due: CalendarDate(iso: "2026-09-14"))

    let captured = try #require(try await capture(draft))
    #expect(try String(contentsOf: vault.root.appending(path: captured.path), encoding: .utf8) == captured.text)
    let task = try #require(session.index.allTasks.first)
    guard case .written(let completed) = try await apply(.state(.done), task) else {
        Issue.record("An awaited task completion must return its written result")
        return
    }
    #expect(completed.text.contains("- [x] Deliver report"))
    #expect(try String(contentsOf: vault.root.appending(path: completed.path), encoding: .utf8) == completed.text)
}

// R-03, Task 1: conversion must preserve stale-write refusal and the external edit.
@MainActor
@Test func cascadeStaleTaskDoesNotOverwriteChangedText() async throws {
    let vault = try TemporaryVault()
    try vault.write(cascadeNote("- [ ] Original"), to: "Tasks.md")
    let session = await cascadeSession(vault)
    let apply = try cascadeAsync(session.apply(_:to:))
    let task = try #require(session.index.allTasks.first)
    let replacement = cascadeNote("- [ ] Replacement")
    try vault.write(replacement, to: "Tasks.md")

    guard case .stale = try await apply(.state(.done), task) else {
        Issue.record("A stale task must remain refused after the async conversion")
        return
    }
    #expect(try String(contentsOf: vault.root.appending(path: "Tasks.md"), encoding: .utf8) == replacement)
    #expect(session.journalOnDisk.entries().isEmpty)
}

// R-03, Task 1: the empty-input outcome must still be delivered to the caller.
@MainActor
@Test func cascadeEmptyTimeBlocksDoNotCreateADailyNote() async throws {
    let vault = try TemporaryVault()
    let session = await cascadeSession(vault)
    let setBlocks = try cascadeAsync({ (blocks: [TimeBlock], day: CalendarDate) async in
        await session.setTimeBlocks(blocks, on: day)
    })
    let day = try #require(CalendarDate(iso: "2026-09-13"))

    guard case .unchanged = try await setBlocks([], day) else {
        Issue.record("Empty blocks on an absent day must return unchanged")
        return
    }
    #expect(!session.exists(session.dailyNotePath(for: day)))
    #expect(session.journalOnDisk.entries().isEmpty)
}

// R-03, Task 1: diary data at the end-of-day boundary survives an awaited round trip.
@MainActor
@Test func cascadeDiaryPreservesTheLastMinuteOfTheDay() async throws {
    let vault = try TemporaryVault()
    let session = await cascadeSession(vault)
    let write = try cascadeAsync(session.writeDiary)
    let day = try #require(CalendarDate(iso: "2026-09-13"))
    let entry = DiaryEntry(startMinutes: 1439, durationMinutes: 1, title: "Day end")

    guard case .written = try await write(session.emptyDiaryNote(for: day), [entry], day) else {
        Issue.record("The diary write must finish before returning written")
        return
    }
    let read = try #require(session.readDiary(on: day))
    #expect(read.entries.map(\.title) == ["Day end"])
    #expect(read.entries.map(\.startMinutes) == [1439])
    #expect(read.entries.map(\.durationMinutes) == [1])
}

// R-03, Task 2: note creation retains its result and files-first/index-second contract.
@MainActor
@Test func cascadeNoteCreationReturnsPersistedAndIndexedContent() async throws {
    let vault = try TemporaryVault()
    let session = await cascadeSession(vault)
    _ = try cascadeAsync({ (title: String, folder: String, date: CalendarDate, category: NoteCategory, topics: [Pergamenum.Tag], body: String) async throws in
        try await session.createNote(title: title, in: folder, date: date, category: category, topics: topics, body: body)
    })
    let day = try #require(CalendarDate(iso: "2026-09-13"))

    let result = try await session.createNote(title: "Report", date: day)

    #expect(result.path == "Report.md")
    #expect(try String(contentsOf: vault.root.appending(path: result.path), encoding: .utf8) == result.text)
    #expect(session.index.note(at: result.path)?.contentHash == NoteStore.hash(Data(result.text.utf8)))
}

// R-03, Task 2: invalid note titles still throw instead of writing a partial result.
@MainActor
@Test func cascadeInvalidNoteTitleLeavesDiskIndexAndJournalAlone() async throws {
    let vault = try TemporaryVault()
    let session = await cascadeSession(vault)
    _ = try cascadeAsync({ (title: String, folder: String, date: CalendarDate, category: NoteCategory, topics: [Pergamenum.Tag], body: String) async throws in
        try await session.createNote(title: title, in: folder, date: date, category: category, topics: topics, body: body)
    })
    let day = try #require(CalendarDate(iso: "2026-09-13"))
    let before = session.index.allNotes.map(\.relativePath)

    await #expect(throws: VaultSession.CreationError.self) {
        _ = try await session.createNote(title: "Folder/Report", date: day)
    }

    #expect(session.index.allNotes.map(\.relativePath) == before)
    #expect(!session.exists("Folder/Report.md"))
    #expect(session.journalOnDisk.entries().isEmpty)
}

// R-03, Task 3: await completion of each rename write, then undo the entire gesture.
@MainActor
@Test func cascadeRenameAndUndoKeepOneJournalGesture() async throws {
    let vault = try TemporaryVault()
    let original = cascadeNote("Original body")
    let link = cascadeNote("See [[Original]].")
    try vault.write(original, to: "Original.md")
    try vault.write(link, to: "Reference.md")
    let session = await cascadeSession(vault)
    let rename = try cascadeAsync(session.renameNote)
    let undo = try cascadeAsync(session.undo)

    let result = try await rename("Original.md", "Renamed")
    #expect(result.newPath == "Renamed.md")
    #expect(result.failures.isEmpty)
    #expect(try String(contentsOf: vault.root.appending(path: "Renamed.md"), encoding: .utf8) == original)
    #expect(try String(contentsOf: vault.root.appending(path: "Reference.md"), encoding: .utf8)
        == cascadeNote("See [[Renamed]]."))
    let entries = session.journalOnDisk.entries()
    #expect(entries.count == 2)
    let operation = try #require(entries.first?.operation)
    #expect(entries.allSatisfy { $0.operation == operation })
    #expect(session.currentOperation == nil)

    let undone = try await undo(operation)
    #expect(undone.failures.isEmpty)
    #expect(!session.exists("Renamed.md"))
    #expect(try String(contentsOf: vault.root.appending(path: "Original.md"), encoding: .utf8) == original)
    #expect(try String(contentsOf: vault.root.appending(path: "Reference.md"), encoding: .utf8) == link)
    #expect(session.currentOperation == nil)
}

// R-03, Task 3: preserve a move's collision error and both files, with no journal write.
@MainActor
@Test func cascadeMoveCollisionPreservesBothFiles() async throws {
    let vault = try TemporaryVault()
    let source = cascadeNote("Source")
    let destination = cascadeNote("Destination")
    try vault.write(source, to: "Source.md")
    try vault.write(destination, to: "Destination.md")
    let session = await cascadeSession(vault)
    let move = try cascadeAsync(session.moveFile)

    await #expect(throws: FileOperationError.self) {
        try await move("Source.md", "Destination.md")
    }

    #expect(try String(contentsOf: vault.root.appending(path: "Source.md"), encoding: .utf8) == source)
    #expect(try String(contentsOf: vault.root.appending(path: "Destination.md"), encoding: .utf8) == destination)
    #expect(session.journalOnDisk.entries().isEmpty)
    #expect(session.index.note(at: "Source.md") != nil)
    #expect(session.index.note(at: "Destination.md") != nil)
}

// R-03, Task 3: raw-file writes, moves and removals each finish before the next action.
@MainActor
@Test func cascadeRawFileWriteMoveAndTrashFinishInCallOrder() async throws {
    let vault = try TemporaryVault()
    let original = "{\"nodes\":[],\"edges\":[]}"
    let replacement = "{\"nodes\":[],\"edges\":[],\"version\":1}"
    try vault.write(original, to: "Board.canvas")
    let session = await cascadeSession(vault)
    let write = try cascadeAsync(session.writeFile)
    let move = try cascadeAsync(session.moveFile)
    let trash = try cascadeAsync(session.trashFile)

    try await write(replacement, "Board.canvas")
    #expect(try String(contentsOf: vault.root.appending(path: "Board.canvas"), encoding: .utf8) == replacement)
    try await move("Board.canvas", "Archive/Board.canvas")
    #expect(!session.exists("Board.canvas"))
    #expect(try String(contentsOf: vault.root.appending(path: "Archive/Board.canvas"), encoding: .utf8) == replacement)
    try await trash("Archive/Board.canvas")
    #expect(!session.exists("Archive/Board.canvas"))

    let entries = session.journalOnDisk.entries()
    #expect(entries.map(\.kind) == [.textReplacement, .move, .removal])
    #expect(entries.last?.textBefore == replacement)
    #expect(session.index.note(at: "Board.canvas") == nil)
    #expect(session.index.note(at: "Archive/Board.canvas") == nil)
}
