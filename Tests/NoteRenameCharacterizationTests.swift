import Foundation
import Testing
@testable import Pergamenum

// MARK: - The bytes a rename produces, pinned against `renamePlan` (ADR-0041 §D5, ADR-0055 §D6)
//
// This file keeps its name and its subject: what a rename produces, byte for byte. Its subject
// was never `NoteFileOperations.rename`'s own loop for its own sake - `rename` is deleted
// (ADR-0055 §D6), and `renamePlan` is where these bytes are computed now, so the two tests below
// are re-aimed at it rather than dropped. The one case that also asserted a real disk write and
// `rewrittenPaths` order - `renameCharacterization_completeOutcomeAndFinalBytesOfAllThreeNotes` -
// moved to `Tests/VaultSessionFileOperationsTests.swift`, where a real performer exists.

private struct CharacterizationVault: ~Copyable {
    private let base: TemporaryVault
    let store: NoteStore
    let operations: NoteFileOperations
    var root: URL { base.root }

    init() throws {
        let base = try TemporaryVault()
        store = NoteStore(root: base.root)
        operations = NoteFileOperations(store: store)
        self.base = base
    }

    func write(_ contents: String, to relativePath: String) throws {
        try base.write(contents, to: relativePath)
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

// MARK: - Collision and canvas-node coverage the refactor must not disturb

@Test func renameCharacterization_targetTitleCollisionThrowsAndWritesNothing() throws {
    let vault = try CharacterizationVault()
    try vault.write(header, to: "Uno.md")
    try vault.write(header, to: "Due.md")

    #expect(throws: FileOperationError.self) {
        try vault.operations.renamePlan("Uno.md", to: "Due", knownPaths: ["Uno.md", "Due.md"])
    }
    // Both are still there under their original names: a plan never touches disk, so "nothing
    // moved or written" is true by construction.
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

    let plan = try vault.operations.renamePlan(
        "01 Progetti/Nota.md", to: "Nota rinominata", knownPaths: ["01 Progetti/Nota.md"]
    )

    let change = try #require(plan.boardChanges.first { $0.path == "Labs.canvas" })
    #expect(change.after.contains("01 Progetti/Nota rinominata.md"))
    #expect(!change.after.contains("01 Progetti/Nota.md\""))
}
