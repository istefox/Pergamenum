import Foundation
import Testing
@testable import Pergamenum

// ADR-0071 (Contenitore) §D3, plan docs/plans/contenitore.md, Task 3: `VaultDisk` derives a
// note record only for a `.md`, and `trashFile` reads `textBefore` only for one. Every existing
// `moveFile` caller moves a `.md`, so these are the first tests to move anything else.

private let pdfBytes = Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37, 0x0A, 0xFF, 0x00, 0xE2])
private let noteText = "---\ndate: 2026-09-29\ntags:\n  - type-note\n---\n\nCorpo.\n"

private func writeBytes(_ data: Data, to relativePath: String, in root: URL) throws {
    let url = root.appending(path: relativePath, directoryHint: .notDirectory)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

@MainActor
@Test func movingAPDFThroughTheDiskDerivesNoRecord() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteText, to: "Nota.md")
    try writeBytes(pdfBytes, to: "A/documento.pdf", in: vault.root)
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()

    let mutations = try await session.disk.moveFile(from: "A/documento.pdf", to: "B/documento.pdf")

    #expect(mutations.map(\.path) == ["A/documento.pdf", "B/documento.pdf"])
    #expect(mutations.allSatisfy { $0.record == nil })
    #expect(FileManager.default.fileExists(atPath: vault.root.appending(path: "B/documento.pdf").path(percentEncoded: false)))
}

@MainActor
@Test func aTextFileMovedThroughTheSessionNeverBecomesAPhantomNote() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteText, to: "Nota.md")
    try vault.write("Una riga di testo.\n", to: "A/appunti.txt")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    let before = session.index.allNotes.map(\.relativePath)

    try await session.moveFile(from: "A/appunti.txt", to: "B/appunti.txt")

    #expect(session.index.allNotes.map(\.relativePath) == before)
    #expect(session.index.note(at: "B/appunti.txt") == nil)
    #expect(session.exists("B/appunti.txt"))
}

@MainActor
@Test func aNoteMovedThroughTheDiskStillDerivesItsRecord() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteText, to: "A/Nota.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()

    let mutations = try await session.disk.moveFile(from: "A/Nota.md", to: "B/Nota.md")

    #expect(mutations.last?.record?.title == "Nota")
}

@MainActor
@Test func restoringAPDFFromOutsideDerivesNoRecord() async throws {
    let vault = try TemporaryVault()
    try FileManager.default.createDirectory(at: vault.root.appending(path: "A"), withIntermediateDirectories: true)
    let outside = vault.stateBase.appending(path: "fuori.pdf")
    try pdfBytes.write(to: outside)
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()

    let mutation = try await session.disk.restoreFile(from: outside, to: "A/fuori.pdf")

    #expect(mutation.record == nil)
    #expect(session.exists("A/fuori.pdf"))
}

@MainActor
@Test func trashingAPDFJournalsARemovalWithNoText() async throws {
    let vault = try TemporaryVault()
    try writeBytes(pdfBytes, to: "A/documento.pdf", in: vault.root)
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    session.journal = session.journalOnDisk

    let trashURL = try await session.trashFile(at: "A/documento.pdf")
    defer { if let trashURL { try? FileManager.default.removeItem(at: trashURL) } }

    let entry = try #require(session.journalOnDisk.entries().last)
    #expect(entry.kind == .removal)
    #expect(entry.path == "A/documento.pdf")
    #expect(entry.textBefore == nil)
    #expect(entry.hashBefore == nil)
    #expect(!session.exists("A/documento.pdf"))
}
