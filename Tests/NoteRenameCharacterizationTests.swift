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

// MARK: - ADR-0064 §D9.4 (R-19): an emphasised wikilink follows the rename, inside its markers

@Test func renameRewritesABoldWikilinkInsideItsMarkers() {
    let cases: [(String, String)] = [
        ("Vedi [[**Forno tunnel**]].", "Vedi [[**Nuovo nome**]]."),
        ("Vedi [[~~Forno tunnel~~]].", "Vedi [[~~Nuovo nome~~]]."),
        ("Vedi [[*Forno tunnel*]].", "Vedi [[*Nuovo nome*]]."),
        ("Vedi [[**Forno tunnel**#Sez|alias]].", "Vedi [[**Nuovo nome**#Sez|alias]]."),
    ]
    for (before, after) in cases {
        #expect(NoteRename.rewritingLinks(in: before, from: "Forno tunnel", to: "Nuovo nome") == after)
    }
}

@Test func renameCountsTheBoldLink() throws {
    let vault = try CharacterizationVault()
    try vault.write(header, to: "Forno tunnel.md")
    try vault.write(header + "Vedi [[**Forno tunnel**]].\n", to: "Riunione.md")

    let plan = try vault.operations.renamePlan(
        "Forno tunnel.md", to: "Nuovo nome", knownPaths: ["Forno tunnel.md", "Riunione.md"]
    )

    let change = try #require(plan.noteChanges.first { $0.path == "Riunione.md" })
    #expect(change.after.hasSuffix("Vedi [[**Nuovo nome**]].\n"))
}

@Test func aTitleThatOnlyContainsEmphasisIsUntouched() {
    #expect(NoteRename.rewritingLinks(
        in: "Vedi [[**Forno tunnel** vecchio]].", from: "Forno tunnel", to: "Nuovo nome", includeQuotedRelated: false
    ) == nil)
}

// MARK: - R-01/R-20-adjacent: a quoted `related:` entry on a CRLF note

/// `rewritingQuotedRelated` splits on `"\n"`, so on a CRLF document every line still carries a
/// trailing `\r` after the split, and `trimmingCharacters(in: .whitespaces)` does not remove it.
/// Before the fix `trimmed.hasSuffix("\"")` was false on every quoted-related line of a CRLF note
/// and the rewrite was silently skipped. The pass now compares through
/// `FrontmatterSource.interpreted(_:)` and re-emits the document's own line break, so the CRLF
/// note's quoted `related:` entry follows the rename, same as the LF form.
@Test func renameRewritesAQuotedRelatedEntryOnACRLFNote() {
    let before = "---\r\nrelated:\r\n  - \"Forno tunnel\"\r\n---\r\nCorpo.\r\n"
    let after = "---\r\nrelated:\r\n  - \"Nuovo nome\"\r\n---\r\nCorpo.\r\n"
    #expect(NoteRename.rewritingLinks(in: before, from: "Forno tunnel", to: "Nuovo nome") == after)
}
