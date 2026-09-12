import Foundation
import Testing
@testable import Pergamenum

// The three guardrails of ADR-0007 §D6: a rehearsal that changes nothing, a diff that
// says what would change, and a journal that can put it back.
//
// These are the tests that matter most in the connector. Everything else is a feature
// that can be wrong and noticed; these are what stands between a model and a vault.

// MARK: - The diff

@Test func aDiffOfIdenticalTextIsNothingRatherThanEmpty() {
    // Nil, not "": a caller has to tell "nothing would change" from "something changed
    // and rendered to nothing", and only the first is worth saying out loud.
    #expect(UnifiedDiff.between("uguale\n", "uguale\n", path: "N.md") == nil)
}

@Test func aChangedLineIsShownWithItsNeighbours() throws {
    let before = "uno\ndue\ntre\nquattro\ncinque\n"
    let after = "uno\ndue\nTRE\nquattro\ncinque\n"
    let diff = try #require(UnifiedDiff.between(before, after, path: "N.md"))

    #expect(diff.contains("--- a/N.md"))
    #expect(diff.contains("+++ b/N.md"))
    #expect(diff.contains("-tre"))
    #expect(diff.contains("+TRE"))
    // Context, so the change is readable rather than merely reported.
    #expect(diff.contains(" due"))
    #expect(diff.contains(" quattro"))
}

@Test func aLongFileShowsTheChangeAndNotTheFile() throws {
    let before = (1...200).map { "riga \($0)" }.joined(separator: "\n")
    let after = before.replacingOccurrences(of: "riga 100", with: "riga cento")
    let diff = try #require(UnifiedDiff.between(before, after, path: "N.md"))

    // Two header lines, one hunk header, and 3+1+1+3 lines of body.
    #expect(diff.components(separatedBy: "\n").count < 15, "il diff stampa troppo:\n\(diff)")
    #expect(diff.contains("+riga cento"))
}

@Test func anAddedLineAtTheEndIsAnInsertAndNotARewrite() throws {
    let diff = try #require(UnifiedDiff.between("uno\ndue\n", "uno\ndue\ntre\n", path: "N.md"))
    #expect(diff.contains("+tre"))
    #expect(!diff.contains("-uno"), "una riga aggiunta in fondo non riscrive quelle sopra")
}

// MARK: - The rehearsal

@MainActor
@Test func aDryRunComputesTheWriteAndDoesNotPerformIt() async throws {
    let vault = try TemporaryVault()
    try vault.write("---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\n- [ ] Alfa\n", to: "T.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()

    let onDiskBefore = try String(contentsOf: vault.root.appending(path: "T.md"), encoding: .utf8)
    session.isDryRun = true

    let task = try #require(session.index.allTasks.first)
    guard case .written(let result) = session.apply(.state(.done), to: task) else {
        Issue.record("una prova deve comunque calcolare la scrittura")
        return
    }

    // The result is the text that would have been written…
    #expect(result.text.contains("- [x] Alfa"))
    // …and the file is untouched.
    let onDiskAfter = try String(contentsOf: vault.root.appending(path: "T.md"), encoding: .utf8)
    #expect(onDiskAfter == onDiskBefore)
    // The index is untouched too, so a second command in the same run is not misled.
    #expect(session.index.allTasks.first?.state == .open)
}

@MainActor
@Test func aDryRunOfANewNoteCreatesNoFile() async throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    session.isDryRun = true

    let result = try session.createNote(title: "Nota nuova", date: CalendarDate(iso: "2026-08-11")!)
    #expect(result.text.contains("type-note"))
    #expect(!session.exists("Nota nuova.md"))
    #expect(!FileManager.default.fileExists(
        atPath: vault.root.appending(path: "Nota nuova.md").path(percentEncoded: false)
    ))
}

// MARK: - The journal

@MainActor
@Test func aJournalledWriteKeepsWhatItReplaced() async throws {
    let vault = try TemporaryVault()
    try vault.write("prima\n", to: "N.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    session.journal = session.journalOnDisk
    session.journalCommand = "prova"

    // ADR-0041 Task 8: `VaultSession.write` gained an async overload.
    try await session.write("dopo\n", to: "N.md")

    let entries = session.journalOnDisk.entries()
    #expect(entries.count == 1)
    let entry = try #require(entries.first)
    #expect(entry.path == "N.md")
    #expect(entry.textBefore == "prima\n")
    #expect(entry.command == "prova")
    // The hash of what is on disk now, which is what an undo has to check against.
    #expect(entry.hashAfter == NoteStore.hash(Data("dopo\n".utf8)))
}

@MainActor
@Test func aJournalMarksACreationAsHavingNoTextBefore() async throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    session.journal = session.journalOnDisk

    // ADR-0041 Task 8: `VaultSession.write` gained an async overload.
    try await session.write("nuovo\n", to: "N.md")

    let entry = try #require(session.journalOnDisk.entries().first)
    // Nil rather than "": undoing a creation means deleting, which is a different act
    // and one the CLI refuses to perform.
    #expect(entry.textBefore == nil)
    #expect(entry.hashBefore == nil)
}

@MainActor
@Test func aDryRunIsNotJournalled() async throws {
    let vault = try TemporaryVault()
    try vault.write("prima\n", to: "N.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    session.journal = session.journalOnDisk
    session.isDryRun = true

    // ADR-0041 Task 8: `VaultSession.write` gained an async overload.
    try await session.write("dopo\n", to: "N.md")

    // Nothing happened, and an entry saying otherwise would be a lie in the one file
    // whose whole job is to be trusted.
    #expect(session.journalOnDisk.entries().isEmpty)
}

@Test func aJournalSurvivesALineItCannotRead() throws {
    let vault = try TemporaryVault()
    let journal = WriteJournal(directory: vault.stateBase.appending(path: "ai-journal"))
    let now = Date()
    #expect(journal.record(WriteJournal.Entry(
        id: "uno", timestamp: now, path: "A.md",
        hashBefore: nil, hashAfter: "h", textBefore: nil, command: "c"
    )) == nil)

    // Something appends rubbish to the file.
    let file = journal.directory.appending(path: "journal.jsonl")
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("{non è json\n".utf8))
    try handle.close()

    #expect(journal.record(WriteJournal.Entry(
        id: "due", timestamp: now, path: "B.md",
        hashBefore: nil, hashAfter: "h", textBefore: nil, command: "c"
    )) == nil)

    // One unreadable line must not hide the rest of the net.
    #expect(journal.entries().map(\.id) == ["uno", "due"])
}
