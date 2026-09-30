import Foundation
import Testing
@testable import Pergamenum

// ADR-0071 (Contenitore) §D3 and §D6: the undo of a pair's rename or move. The binary is journalled
// as a move with an empty `hashAfter` (the disk actor derives no record for a non-note, so the
// main actor never reads it), and `preflightMove` must not read that file to compare it with "" -
// the refusal that used to leave the scheda, the file and every rewritten link where the gesture
// put them.

private let pdfBytes = Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37, 0x0A, 0xFF, 0x00, 0xE2])
private let sha = String(repeating: "ab", count: 32)
private let folder = "Contenitore/Fatture"
private let stem = "20260314 Fattura"
private var scheda: String { "\(folder)/\(stem).md" }
private var pdf: String { "\(folder)/\(stem).pdf" }

private func plainNote(_ body: String) -> String {
    "---\ndate: 2026-09-29\ntags:\n  - type-note\n---\n\n\(body)\n"
}

private func readText(_ relativePath: String, in root: URL) throws -> String {
    try String(contentsOf: root.appending(path: relativePath, directoryHint: .notDirectory), encoding: .utf8)
}

/// A scheda and its PDF, a note linking both, and a session with the journal armed as a connector
/// arms it (ADR-0007 §D6).
@MainActor
private func armedPair(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    let date = try #require(CalendarDate(iso: "2026-03-14"))
    try vault.write(
        ContenitoreScheda.render(date: date, fileName: "\(stem).pdf", originalName: "Scansione.pdf", sha256: sha),
        to: scheda
    )
    let url = vault.root.appending(path: pdf, directoryHint: .notDirectory)
    try pdfBytes.write(to: url)
    try vault.write(plainNote("Vedi [[\(stem).pdf]] e [[\(stem)]]."), to: "Nota.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    session.journal = session.journalOnDisk
    return session
}

@MainActor
@Test func undoOfAPairRenamePutsBothFilesTheSchedaKeyAndTheLinksBack() async throws {
    let vault = try TemporaryVault()
    let session = try await armedPair(vault)
    let schedaBefore = try readText(scheda, in: vault.root)
    let noteBefore = try readText("Nota.md", in: vault.root)

    _ = try await session.renameNote(at: scheda, to: "20260314 Fattura Enel")
    let operationID = try #require(session.journalOnDisk.entries().first?.operation)
    #expect(session.exists("\(folder)/20260314 Fattura Enel.pdf"))

    let undone = await session.undo(operation: operationID)

    #expect(undone.failures.isEmpty, "\(undone.failures)")
    #expect(session.exists(scheda))
    #expect(session.exists(pdf))
    #expect(!session.exists("\(folder)/20260314 Fattura Enel.md"))
    #expect(!session.exists("\(folder)/20260314 Fattura Enel.pdf"))
    #expect(try readText(scheda, in: vault.root) == schedaBefore)
    #expect(try readText("Nota.md", in: vault.root) == noteBefore)
    #expect(try Data(contentsOf: vault.root.appending(path: pdf)) == pdfBytes)
    #expect(session.companion(ofScheda: scheda) == pdf)
}

@MainActor
@Test func undoOfAPairMoveBringsBothFilesBack() async throws {
    let vault = try TemporaryVault()
    let session = try await armedPair(vault)

    _ = try await session.moveNote(at: scheda, toFolder: "Altrove")
    let operationID = try #require(session.journalOnDisk.entries().first?.operation)
    #expect(session.exists("Altrove/\(stem).pdf"))

    let undone = await session.undo(operation: operationID)

    #expect(undone.failures.isEmpty, "\(undone.failures)")
    #expect(session.exists(scheda))
    #expect(session.exists(pdf))
    #expect(!session.exists("Altrove/\(stem).md"))
    #expect(!session.exists("Altrove/\(stem).pdf"))
    #expect(session.companion(ofScheda: scheda) == pdf)
}

@MainActor
@Test func undoOfAPairMoveIsStillRefusedWhenTheFilesOldPathIsTaken() async throws {
    let vault = try TemporaryVault()
    let session = try await armedPair(vault)

    _ = try await session.moveNote(at: scheda, toFolder: "Altrove")
    let operationID = try #require(session.journalOnDisk.entries().first?.operation)
    try Data("occupato".utf8).write(to: vault.root.appending(path: pdf))

    let undone = await session.undo(operation: operationID)

    #expect(undone.changed.isEmpty)
    #expect(undone.failures.contains { $0.contains(pdf) })
    #expect(session.exists("Altrove/\(stem).md"))
    #expect(session.exists("Altrove/\(stem).pdf"))
}

@MainActor
@Test func undoOfAPairMoveIsRefusedWhenTheMovedFileIsGone() async throws {
    let vault = try TemporaryVault()
    let session = try await armedPair(vault)

    _ = try await session.moveNote(at: scheda, toFolder: "Altrove")
    let operationID = try #require(session.journalOnDisk.entries().first?.operation)
    try FileManager.default.removeItem(at: vault.root.appending(path: "Altrove/\(stem).pdf"))

    let undone = await session.undo(operation: operationID)

    #expect(undone.changed.isEmpty)
    #expect(undone.failures.contains { $0.contains("Altrove/\(stem).pdf") })
    #expect(session.exists("Altrove/\(stem).md"))
}

// The binary's removal carries no text (§D3), so its entry cannot be reversed, and `undo` refuses
// the whole gesture rather than bring the scheda back alone: the pair never ends up split, and
// both halves stay in the Finder Trash.
@MainActor
@Test func undoOfAPairTrashIsRefusedWholeAndRestoresNeitherFile() async throws {
    let vault = try TemporaryVault()
    let session = try await armedPair(vault)

    _ = try await session.trashNote(at: scheda)
    let operationID = try #require(
        session.journalOnDisk.entries().last { $0.kind == .removal }?.operation
    )
    #expect(session.journalOnDisk.entries(operation: operationID).count == 2)

    let undone = await session.undo(operation: operationID)

    #expect(undone.changed.isEmpty)
    #expect(undone.failures.contains { $0.contains(pdf) })
    #expect(!session.exists(scheda))
    #expect(!session.exists(pdf))
}
