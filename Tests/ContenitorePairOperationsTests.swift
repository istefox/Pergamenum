import Foundation
import Testing
@testable import Pergamenum

// ADR-0071 (Contenitore) §D6, plan docs/plans/contenitore.md, Task 3 - R-19 (disk half), R-20,
// R-21, R-22, R-23 (id half). A document is a pair: a scheda note and a binary file beside it
// with the same stem, which rename, move and trash together at the session's note doors.

private let pdfBytes = Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37, 0x0A, 0xFF, 0x00, 0xE2])
private let hash = String(repeating: "ab", count: 32)

private func schedaText(for fileName: String, date: String = "2026-03-14") throws -> String {
    let date = try #require(CalendarDate(iso: date))
    return ContenitoreScheda.render(date: date, fileName: fileName, originalName: "Scansione.pdf", sha256: hash)
}

private func plainNote(_ body: String) -> String {
    "---\ndate: 2026-09-29\ntags:\n  - type-note\n---\n\n\(body)\n"
}

private func writeBytes(_ data: Data, to relativePath: String, in root: URL) throws {
    let url = root.appending(path: relativePath, directoryHint: .notDirectory)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

private func readText(_ relativePath: String, in root: URL) throws -> String {
    try String(contentsOf: root.appending(path: relativePath, directoryHint: .notDirectory), encoding: .utf8)
}

private func board(pointingAt file: String) -> String {
    """
    {"nodes":[{"id":"a","type":"file","file":"\(file)","x":0,"y":0,"width":260,"height":180}],"edges":[]}
    """
}

/// A scheda and its PDF at `folder/stem.{md,pdf}`.
private func seedPair(stem: String, in folder: String, date: String = "2026-03-14", vault: borrowing TemporaryVault) throws {
    try vault.write(try schedaText(for: "\(stem).pdf", date: date), to: "\(folder)/\(stem).md")
    try writeBytes(pdfBytes, to: "\(folder)/\(stem).pdf", in: vault.root)
}

@MainActor
private func openSession(_ vault: borrowing TemporaryVault) async -> VaultSession {
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

private func trash(_ urls: [URL]) {
    for url in urls { try? FileManager.default.removeItem(at: url) }
}

private let folder = "Contenitore/Fatture"
private let stem = "20260314 Fattura"
private var scheda: String { "\(folder)/\(stem).md" }
private var pdf: String { "\(folder)/\(stem).pdf" }

// MARK: - The companion

@MainActor
@Test func aSchedaWithItsFileBesideItNamesThatFileAsItsCompanion() async throws {
    let vault = try TemporaryVault()
    try seedPair(stem: stem, in: folder, vault: vault)
    try vault.write(plainNote("Nessun documento."), to: "\(folder)/Altra.md")
    let session = await openSession(vault)

    #expect(session.companion(ofScheda: scheda) == pdf)
    #expect(session.companion(ofScheda: "\(folder)/Altra.md") == nil)
}

@MainActor
@Test func aSchedaWhoseFileIsMissingHasNoCompanion() async throws {
    let vault = try TemporaryVault()
    try vault.write(try schedaText(for: "\(stem).pdf"), to: scheda)
    let session = await openSession(vault)

    #expect(session.companion(ofScheda: scheda) == nil)
}

// MARK: - Rename (R-21)

@MainActor
@Test func renamingASchedaRenamesBothFilesAndEveryLinkToEither() async throws {
    let vault = try TemporaryVault()
    try seedPair(stem: stem, in: folder, vault: vault)
    try vault.write(
        plainNote("Vedi [[\(stem).pdf]], ![[\(stem).pdf|400]] e [[\(stem)]]."), to: "Nota.md"
    )
    try vault.write(board(pointingAt: pdf), to: "Tavola.canvas")
    let session = await openSession(vault)
    let id = try #require(session.mintNoteID(for: scheda))

    let newStem = "20260314 Fattura Enel"
    let outcome = try await session.renameNote(at: scheda, to: newStem)

    let newScheda = "\(folder)/\(newStem).md"
    let newPDF = "\(folder)/\(newStem).pdf"
    #expect(outcome.newPath == newScheda)
    #expect(outcome.failures.isEmpty)
    #expect(outcome.refusals.isEmpty)
    #expect(session.exists(newScheda))
    #expect(session.exists(newPDF))
    #expect(!session.exists(scheda))
    #expect(!session.exists(pdf))

    let note = try readText("Nota.md", in: vault.root)
    #expect(note.contains("[[\(newStem).pdf]]"))
    #expect(note.contains("![[\(newStem).pdf|400]]"))
    #expect(note.contains("[[\(newStem)]]"))
    #expect(!note.contains("[[\(stem).pdf"))

    #expect(try readText("Tavola.canvas", in: vault.root).contains(newPDF))
    #expect(session.index.note(at: newScheda)?.contenitore?.fileName == "\(newStem).pdf")
    #expect(session.companion(ofScheda: newScheda) == newPDF)
    #expect(session.lookUpNote(id: id) == .found(newScheda))
}

@MainActor
@Test func aTakenStemRefusesBothFiles() async throws {
    let vault = try TemporaryVault()
    try seedPair(stem: stem, in: folder, vault: vault)
    try writeBytes(pdfBytes, to: "\(folder)/Occupato.pdf", in: vault.root)
    let session = await openSession(vault)

    await #expect(throws: FileOperationError.self) {
        _ = try await session.renameNote(at: scheda, to: "Occupato")
    }
    #expect(session.exists(scheda))
    #expect(session.exists(pdf))
    #expect(!session.exists("\(folder)/Occupato.md"))
}

@MainActor
@Test func anAmbiguousOldFileNameSkipsTheFileNameRewriteAndSaysSo() async throws {
    let vault = try TemporaryVault()
    try seedPair(stem: stem, in: folder, vault: vault)
    try writeBytes(pdfBytes, to: "Archivio/\(stem).pdf", in: vault.root)
    try vault.write(plainNote("Vedi [[\(stem).pdf]]."), to: "Nota.md")
    let session = await openSession(vault)

    let outcome = try await session.renameNote(at: scheda, to: "20260314 Fattura Enel")

    #expect(outcome.failures.contains { $0.contains("nome non univoco") })
    #expect(try readText("Nota.md", in: vault.root).contains("[[\(stem).pdf]]"))
    #expect(session.exists("\(folder)/20260314 Fattura Enel.pdf"))
    // The scheda's own key is not a guess: it follows regardless, so the pair stays a pair.
    let renamed = "\(folder)/20260314 Fattura Enel.md"
    #expect(session.index.note(at: renamed)?.contenitore?.fileName == "20260314 Fattura Enel.pdf")
    #expect(session.companion(ofScheda: renamed) == "\(folder)/20260314 Fattura Enel.pdf")
}

// MARK: - Move (R-20)

@MainActor
@Test func movingADocumentIntoAContainerFilesThePairUnderTheYearOfItsDate() async throws {
    let vault = try TemporaryVault()
    let inbox = "Contenitore/Arrivi"
    let stem = "20251102 Bolletta"
    try seedPair(stem: stem, in: inbox, date: "2025-11-02", vault: vault)
    let session = await openSession(vault)
    let id = try #require(session.mintNoteID(for: "\(inbox)/\(stem).md"))

    let outcome = try await session.moveDocument(at: "\(inbox)/\(stem).md", toContainer: "Contenitore/Utenze")

    #expect(outcome.newPath == "Contenitore/Utenze/2025/\(stem).md")
    #expect(session.exists("Contenitore/Utenze/2025/\(stem).md"))
    #expect(session.exists("Contenitore/Utenze/2025/\(stem).pdf"))
    #expect(!session.exists("\(inbox)/\(stem).pdf"))
    #expect(session.lookUpNote(id: id) == .found("Contenitore/Utenze/2025/\(stem).md"))
}

@MainActor
@Test func aCollisionInTheYearFolderGivesThePairOneUniqueStem() async throws {
    let vault = try TemporaryVault()
    let inbox = "Contenitore/Arrivi"
    let stem = "20251102 Bolletta"
    try seedPair(stem: stem, in: inbox, date: "2025-11-02", vault: vault)
    try writeBytes(pdfBytes, to: "Contenitore/Utenze/2025/\(stem).pdf", in: vault.root)
    let session = await openSession(vault)

    let outcome = try await session.moveDocument(at: "\(inbox)/\(stem).md", toContainer: "Contenitore/Utenze")

    let moved = "Contenitore/Utenze/2025/\(stem)-2"
    #expect(outcome.newPath == "\(moved).md")
    #expect(session.exists("\(moved).md"))
    #expect(session.exists("\(moved).pdf"))
    #expect(session.index.note(at: "\(moved).md")?.contenitore?.fileName == "\(stem)-2.pdf")
}

@MainActor
@Test func movingASchedaThroughMoveNoteMovesBothFiles() async throws {
    let vault = try TemporaryVault()
    try seedPair(stem: stem, in: folder, vault: vault)
    let session = await openSession(vault)
    let id = try #require(session.mintNoteID(for: scheda))

    let outcome = try await session.moveNote(at: scheda, toFolder: "Altrove")

    #expect(outcome.newPath == "Altrove/\(stem).md")
    #expect(session.exists("Altrove/\(stem).md"))
    #expect(session.exists("Altrove/\(stem).pdf"))
    #expect(!session.exists(pdf))
    #expect(session.lookUpNote(id: id) == .found("Altrove/\(stem).md"))
}

@MainActor
@Test func aCollisionAtTheMoveNoteDestinationRefusesBothFiles() async throws {
    let vault = try TemporaryVault()
    try seedPair(stem: stem, in: folder, vault: vault)
    try writeBytes(pdfBytes, to: "Altrove/\(stem).pdf", in: vault.root)
    let session = await openSession(vault)

    await #expect(throws: FileOperationError.self) {
        _ = try await session.moveNote(at: scheda, toFolder: "Altrove")
    }
    #expect(session.exists(scheda))
    #expect(session.exists(pdf))
    #expect(!session.exists("Altrove/\(stem).md"))
}

/// The collision the plan could not see: the destination of the file is taken only once the
/// scheda has already moved, so the file's move fails and the scheda must come back. The
/// session's landed-change subscriber runs synchronously after the scheda's move, which is the
/// deterministic moment to take the path.
@MainActor
@Test func aFileMoveFailingAfterTheSchedaMovedPutsTheSchedaBack() async throws {
    let vault = try TemporaryVault()
    try seedPair(stem: stem, in: folder, vault: vault)
    let session = await openSession(vault)
    let id = try #require(session.mintNoteID(for: scheda))
    let takenAfterPlan = vault.root.appending(path: "Altrove/\(stem).pdf", directoryHint: .isDirectory)
    session.landedChangeSubscriber = { change in
        if case .moved(let from, _) = change, from == scheda {
            try? FileManager.default.createDirectory(at: takenAfterPlan, withIntermediateDirectories: true)
        }
    }

    await #expect(throws: FileOperationError.self) {
        _ = try await session.moveNote(at: scheda, toFolder: "Altrove")
    }

    #expect(session.exists(scheda))
    #expect(session.exists(pdf))
    #expect(!session.exists("Altrove/\(stem).md"))
    #expect(try Data(contentsOf: vault.root.appending(path: pdf, directoryHint: .notDirectory)) == pdfBytes)
    #expect(session.index.note(at: scheda)?.contenitore?.fileName == "\(stem).pdf")
    #expect(session.index.note(at: "Altrove/\(stem).md") == nil)
    #expect(session.lookUpNote(id: id) == .found(scheda))
}

// MARK: - Trash (R-22)

@MainActor
@Test func trashingADocumentSendsBothFilesToTheTrashAndReturnsWhereTheyWent() async throws {
    let vault = try TemporaryVault()
    try seedPair(stem: stem, in: folder, vault: vault)
    try vault.write(plainNote("Vedi [[\(stem)]]."), to: "Nota.md")
    let session = await openSession(vault)

    let result = try await session.trashDocument(at: scheda)
    defer { trash(result.trashURLs) }

    #expect(!session.exists(scheda))
    #expect(!session.exists(pdf))
    #expect(result.trashURLs.count == 2)
    #expect(result.orphaned == ["Nota.md"])
}

@MainActor
@Test func trashNoteOnASchedaTakesItsFileToo() async throws {
    let vault = try TemporaryVault()
    try seedPair(stem: stem, in: folder, vault: vault)
    let session = await openSession(vault)

    _ = try await session.trashNote(at: scheda)

    #expect(!session.exists(scheda))
    #expect(!session.exists(pdf))
    #expect(session.index.note(at: scheda) == nil)
}

// MARK: - The note doors refuse a companion path (ADR-0071 §D6)

/// A companion named at a note door would be moved, renamed or trashed alone, splitting its pair.
/// The doors are for notes: the pair is operated on through its scheda.
@MainActor
@Test func theNoteDoorsRefuseACompanionPathAndSplitNothing() async throws {
    let vault = try TemporaryVault()
    try seedPair(stem: stem, in: folder, vault: vault)
    try FileManager.default.createDirectory(at: vault.root.appending(path: "Altrove"), withIntermediateDirectories: true)
    let session = await openSession(vault)

    await #expect(throws: FileOperationError.self) {
        _ = try await session.renameNote(at: pdf, to: "Altro nome")
    }
    await #expect(throws: FileOperationError.self) {
        _ = try await session.moveNote(at: pdf, toFolder: "Altrove")
    }
    await #expect(throws: FileOperationError.self) {
        _ = try await session.trashNote(at: pdf)
    }

    #expect(session.exists(scheda))
    #expect(session.exists(pdf))
    #expect(!session.exists("\(folder)/Altro nome.md"))
    #expect(!session.exists("Altrove/\(stem).pdf"))
    #expect(try Data(contentsOf: vault.root.appending(path: pdf, directoryHint: .notDirectory)) == pdfBytes)
    #expect(session.companion(ofScheda: scheda) == pdf)
}

/// The file goes to the trash first; a scheda the Finder then refuses to trash (here: locked,
/// so `trashItem` fails with a permission error) brings the file back with its bytes, and the
/// scheda keeps its id.
@MainActor
@Test func aSchedaTrashFailingAfterTheFileWentBringsTheFileBack() async throws {
    let vault = try TemporaryVault()
    try seedPair(stem: stem, in: folder, vault: vault)
    let session = await openSession(vault)
    let id = try #require(session.mintNoteID(for: scheda))
    let schedaPath = vault.root.appending(path: scheda, directoryHint: .notDirectory).path(percentEncoded: false)
    try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: schedaPath)
    defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: schedaPath) }

    await #expect(throws: FileOperationError.self) {
        _ = try await session.trashDocument(at: scheda)
    }

    #expect(session.exists(scheda))
    #expect(session.exists(pdf))
    #expect(try Data(contentsOf: vault.root.appending(path: pdf, directoryHint: .notDirectory)) == pdfBytes)
    #expect(session.index.note(at: scheda) != nil)
    #expect(session.companion(ofScheda: scheda) == pdf)
    #expect(session.lookUpNote(id: id) == .found(scheda))
}

// MARK: - Sub-containers (R-19, disk half)

@MainActor
@Test func renamingAContainerCarriesANestedPairWithItsId() async throws {
    let vault = try TemporaryVault()
    let nested = "Contenitore/A/B/C"
    try seedPair(stem: stem, in: nested, vault: vault)
    let session = await openSession(vault)
    let id = try #require(session.mintNoteID(for: "\(nested)/\(stem).md"))

    _ = try session.renameFolder(at: "Contenitore/A", to: "Z")

    #expect(session.exists("Contenitore/Z/B/C/\(stem).md"))
    #expect(session.exists("Contenitore/Z/B/C/\(stem).pdf"))
    #expect(session.lookUpNote(id: id) == .found("Contenitore/Z/B/C/\(stem).md"))
}

@MainActor
@Test func movingAContainerCarriesANestedPairWithItsId() async throws {
    let vault = try TemporaryVault()
    let nested = "Contenitore/A/B/C"
    try seedPair(stem: stem, in: nested, vault: vault)
    try FileManager.default.createDirectory(at: vault.root.appending(path: "Archivio"), withIntermediateDirectories: true)
    let session = await openSession(vault)
    let id = try #require(session.mintNoteID(for: "\(nested)/\(stem).md"))

    let outcome = await session.moveItems([VaultItemRef(path: "Contenitore/A", kind: .folder)], into: "Archivio")

    #expect(outcome.failures.isEmpty)
    #expect(session.exists("Archivio/A/B/C/\(stem).md"))
    #expect(session.exists("Archivio/A/B/C/\(stem).pdf"))
    #expect(session.lookUpNote(id: id) == .found("Archivio/A/B/C/\(stem).md"))
}

@MainActor
@Test func trashingAContainerTakesANestedPairAndForgetsItsId() async throws {
    let vault = try TemporaryVault()
    let nested = "Contenitore/A/B/C"
    try seedPair(stem: stem, in: nested, vault: vault)
    let session = await openSession(vault)
    let id = try #require(session.mintNoteID(for: "\(nested)/\(stem).md"))

    let result = try session.trashFolder(at: "Contenitore/A")
    defer { trash(result.url.map { [$0] } ?? []) }

    #expect(!session.exists("\(nested)/\(stem).md"))
    #expect(!session.exists("\(nested)/\(stem).pdf"))
    #expect(session.lookUpNote(id: id) == .unknown)
}

// MARK: - Batch move

@MainActor
@Test func aBatchHoldingASchedaAndItsFileMovesThePairOnceWithNoFailure() async throws {
    let vault = try TemporaryVault()
    try seedPair(stem: stem, in: folder, vault: vault)
    try FileManager.default.createDirectory(at: vault.root.appending(path: "Altrove"), withIntermediateDirectories: true)
    let session = await openSession(vault)

    let outcome = await session.moveItems(
        [VaultItemRef(path: scheda, kind: .note), VaultItemRef(path: pdf, kind: .note)], into: "Altrove"
    )

    #expect(outcome.failures.isEmpty)
    #expect(outcome.moves.map(\.item.path) == [scheda])
    #expect(session.exists("Altrove/\(stem).md"))
    #expect(session.exists("Altrove/\(stem).pdf"))
    #expect(!session.exists(pdf))
}

// MARK: - Adopt and return (§D4 steps 6 and 8)

@MainActor
@Test func adoptingAFileCreatesItsFoldersAndIndexesNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(plainNote("Corpo."), to: "Nota.md")
    let outside = vault.stateBase.appending(path: "scansione.pdf")
    try pdfBytes.write(to: outside)
    let session = await openSession(vault)
    let notesBefore = session.index.allNotes.map(\.relativePath)

    try await session.adoptFromOutside(outside, to: "Contenitore/2026/\(stem).pdf")

    #expect(session.exists("Contenitore/2026/\(stem).pdf"))
    #expect(!FileManager.default.fileExists(atPath: outside.path(percentEncoded: false)))
    #expect(session.index.allNotes.map(\.relativePath) == notesBefore)
}

@MainActor
@Test func adoptingOntoATakenPathRefusesAndOverwritesNothing() async throws {
    let vault = try TemporaryVault()
    try writeBytes(Data("vecchio".utf8), to: "Contenitore/2026/\(stem).pdf", in: vault.root)
    let outside = vault.stateBase.appending(path: "scansione.pdf")
    try pdfBytes.write(to: outside)
    let session = await openSession(vault)

    await #expect(throws: FileOperationError.self) {
        try await session.adoptFromOutside(outside, to: "Contenitore/2026/\(stem).pdf")
    }
    let kept = try Data(contentsOf: vault.root.appending(path: "Contenitore/2026/\(stem).pdf"))
    #expect(kept == Data("vecchio".utf8))
    #expect(FileManager.default.fileExists(atPath: outside.path(percentEncoded: false)))
}

@MainActor
@Test func returningAFilePutsItBackOutsideTheVault() async throws {
    let vault = try TemporaryVault()
    let outside = vault.stateBase.appending(path: "scansione.pdf")
    try pdfBytes.write(to: outside)
    let session = await openSession(vault)
    try await session.adoptFromOutside(outside, to: "Contenitore/2026/\(stem).pdf")

    try await session.returnToOutside("Contenitore/2026/\(stem).pdf", to: outside)

    #expect(!session.exists("Contenitore/2026/\(stem).pdf"))
    #expect(try Data(contentsOf: outside) == pdfBytes)
}
