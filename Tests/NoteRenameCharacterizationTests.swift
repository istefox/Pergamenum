import Foundation
import Testing
@testable import Pergamenum

// MARK: - Task 5 (R-03): baseline behavior of `NoteFileOperations.rename`, pinned down first
//
// ADR-0041 §D4/§D5 replaces `rename`'s own hand-rolled loop with `renamePlan` + move + two
// `VaultPlanApplication.apply` calls. §D5 names the one behavioral difference to watch: today's
// `rename` reads each note *after* the move, substituting `readPath` (`:235`); `renamePlan` reads
// *before*, substituting `writePath` (`:106-118`). "The bytes should be identical" is exactly how
// the two copies drifted in the first place - this file is the baseline that a later run (after
// the coder's refactor lands) can be re-run against unedited to confirm nothing moved.
//
// Written and confirmed green against the CURRENT, unmodified `rename` implementation, before a
// single line of `rename`/`renamePlan` changed.

private struct CharacterizationVault: ~Copyable {
    let root: URL
    let store: NoteStore
    let operations: NoteFileOperations

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-characterization-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = NoteStore(root: root)
        operations = NoteFileOperations(store: store)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    func write(_ contents: String, to relativePath: String) throws {
        let url = root.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    func writeBytes(_ data: Data, to relativePath: String) throws {
        let url = root.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    func text(at relativePath: String) throws -> String {
        try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
    }

    func bytes(at relativePath: String) throws -> Data {
        try Data(contentsOf: root.appending(path: relativePath))
    }
}

/// Free function rather than a method on `CharacterizationVault`: `#expect` captures the whole
/// expression, and capturing a call on a non-copyable value does not compile (mirrors
/// `NoteFileOperationTests.swift`'s own `exists(_:in:)`).
private func exists(_ relativePath: String, in root: URL) -> Bool {
    FileManager.default.fileExists(
        atPath: root.appending(path: relativePath).path(percentEncoded: false)
    )
}

private let header = """
---
date: 2026-08-12
tags:
  - type-note
---


"""

// MARK: - The three-note vault: A links to B, B links to itself, C is unreadable

@Test func renameCharacterization_completeOutcomeAndFinalBytesOfAllThreeNotes() throws {
    let vault = try CharacterizationVault()

    // A links to B by title.
    try vault.write(header + "Vedi [[Nota B]] per il dettaglio.", to: "A.md")
    // B links to itself.
    try vault.write(header + "Questa è [[Nota B]], vedi anche [[Nota B]] più sotto.", to: "Nota B.md")
    // C is unreadable: not valid UTF-8, so `store.read` throws before this rename ever runs, and
    // stays that way regardless of what the rename does elsewhere in the vault.
    let invalidUTF8 = Data([0xFF, 0xFE, 0xFD, 0x00, 0x01])
    try vault.writeBytes(invalidUTF8, to: "C.md")
    let cBefore = try vault.bytes(at: "C.md")

    let outcome = try vault.operations.rename(
        "Nota B.md", to: "Nota B rinominata",
        knownPaths: ["A.md", "Nota B.md", "C.md"]
    )

    #expect(outcome.newPath == "Nota B rinominata.md")
    // Order follows `knownPaths`: A first, then B (found at its new path, since B is the note
    // being renamed), then C - which fails and contributes nothing to `rewrittenPaths`.
    #expect(outcome.rewrittenPaths == ["A.md", "Nota B rinominata.md"])
    #expect(outcome.failures == ["C.md: non leggibile"])

    #expect(exists("Nota B rinominata.md", in: vault.root))
    #expect(!exists("Nota B.md", in: vault.root))

    #expect(try vault.text(at: "A.md") == header + "Vedi [[Nota B rinominata]] per il dettaglio.")
    #expect(
        try vault.text(at: "Nota B rinominata.md")
            == header + "Questa è [[Nota B rinominata]], vedi anche [[Nota B rinominata]] più sotto."
    )
    // C was never touched: still unreadable, still exactly the same bytes.
    #expect(try vault.bytes(at: "C.md") == cBefore)
}

// MARK: - Collision and canvas-node coverage the refactor must not disturb

@Test func renameCharacterization_targetTitleCollisionThrowsAndWritesNothing() throws {
    let vault = try CharacterizationVault()
    try vault.write(header, to: "Uno.md")
    try vault.write(header, to: "Due.md")

    #expect(throws: FileOperationError.self) {
        try vault.operations.rename("Uno.md", to: "Due", knownPaths: ["Uno.md", "Due.md"])
    }
    // Both are still there under their original names: a refused rename must not have moved
    // or written anything, before or after the refactor.
    #expect(exists("Uno.md", in: vault.root))
    #expect(exists("Due.md", in: vault.root))
}

@Test func renameCharacterization_repointsACanvasNodeReferencingTheRenamedNoteExactlyAsBefore() throws {
    let vault = try CharacterizationVault()
    try vault.write(header, to: "01 Progetti/Nota.md")
    let board = """
    {"nodes":[{"id":"a","type":"file","file":"01 Progetti/Nota.md","x":0,"y":0,"width":260,"height":180}],"edges":[]}
    """
    try vault.write(board, to: "Labs.canvas")

    let outcome = try vault.operations.rename(
        "01 Progetti/Nota.md", to: "Nota rinominata", knownPaths: ["01 Progetti/Nota.md"]
    )

    let updated = try vault.text(at: "Labs.canvas")
    #expect(updated.contains("01 Progetti/Nota rinominata.md"))
    #expect(!updated.contains("01 Progetti/Nota.md\""))
    #expect(outcome.rewrittenPaths.contains("Labs.canvas"))
}
