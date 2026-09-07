import Foundation
import Testing
@testable import Pergamenum

// MARK: - Link rewriting (wikilink.md W-08)

@Test func renamingCarriesAPlainLinkWithIt() {
    let text = "Vedi [[Curva di trasmissibilità]] per il dettaglio."
    let updated = NoteRename.rewritingLinks(
        in: text, from: "Curva di trasmissibilità", to: "Curva di trasmissibilità AV-45"
    )
    #expect(updated == "Vedi [[Curva di trasmissibilità AV-45]] per il dettaglio.")
}

@Test func theSectionAndTheLabelBelongToTheReaderAndAreKept() {
    let text = "[[Vecchio#Metodo|come spiegato qui]]"
    let updated = NoteRename.rewritingLinks(in: text, from: "Vecchio", to: "Nuovo")
    #expect(updated == "[[Nuovo#Metodo|come spiegato qui]]")
}

@Test func everyOccurrenceIsRewrittenNotJustTheFirst() {
    let text = "[[Vecchio]] e ancora [[Vecchio]] e [[Vecchio|alias]]"
    let updated = NoteRename.rewritingLinks(in: text, from: "Vecchio", to: "Nuovo")
    #expect(updated == "[[Nuovo]] e ancora [[Nuovo]] e [[Nuovo|alias]]")
}

@Test func aLinkToAnotherNoteIsLeftAlone() {
    let text = "[[Altra nota]] e [[Vecchio]]"
    let updated = NoteRename.rewritingLinks(in: text, from: "Vecchio", to: "Nuovo")
    #expect(updated == "[[Altra nota]] e [[Nuovo]]")
}

@Test func aNoteThatDoesNotLinkHereIsNotRewrittenAtAll() {
    // nil rather than an unchanged copy, so the caller does not write a file it did
    // not change and wake the watcher for nothing.
    #expect(NoteRename.rewritingLinks(in: "Nessun link.", from: "Vecchio", to: "Nuovo") == nil)
}

@Test func aLinkTypedWithADifferentCaseStillFollowsTheRename() {
    let updated = NoteRename.rewritingLinks(in: "[[vecchio]]", from: "Vecchio", to: "Nuovo")
    #expect(updated == "[[Nuovo]]")
}

@Test func theQuotedRelatedFormIsRewrittenToo() {
    let text = """
    ---
    related:
      - "Vecchio"
      - "[[Vecchio]]"
      - "Altra"
    ---
    """
    let updated = NoteRename.rewritingLinks(in: text, from: "Vecchio", to: "Nuovo")
    // Both spellings F-06 allows, or the frontmatter would point at a note that no
    // longer exists while the body was correct.
    #expect(updated?.contains("- \"Nuovo\"") == true)
    #expect(updated?.contains("- \"[[Nuovo]]\"") == true)
    #expect(updated?.contains("Altra") == true)
    #expect(updated?.contains("Vecchio") == false)
}

@Test func renamingToTheSameTitleChangesNothing() {
    #expect(NoteRename.rewritingLinks(in: "[[Uguale]]", from: "Uguale", to: "Uguale") == nil)
}

@Test func aLinkInsideCodeIsNotARenameTarget() {
    // The same rule the indexer uses: `[[ ]]` in a shell snippet is not a link.
    let text = "```bash\nif [[ Vecchio ]]; then :; fi\n```\n\n[[Vecchio]]"
    let updated = NoteRename.rewritingLinks(in: text, from: "Vecchio", to: "Nuovo")
    #expect(updated?.contains("if [[ Vecchio ]]") == true)
    #expect(updated?.contains("[[Nuovo]]") == true)
}

// MARK: - The `^[[…]].canvas` Workspace marker survives a rename (ADR-0021 §D3, R-13)
//
// Plan `docs/superpowers/plans/2026-08-24-workspace-tasks-notes-integration.md`, Task 4:
// `NoteRename.rewritingLinks` replaces `link.range`, which for a non-embed link starts at
// `[[` - the caret sits outside that range and is expected to survive untouched with no new
// code. These three tests are that claim, checked rather than assumed.

@Test func caretWorkspaceMarkerSurvivesARenameIntact() {
    let text = "- [ ] Testo ^[[Vecchio.canvas]] >2026-09-01"
    let updated = NoteRename.rewritingLinks(in: text, from: "Vecchio.canvas", to: "Nuovo.canvas")
    #expect(updated == "- [ ] Testo ^[[Nuovo.canvas]] >2026-09-01")
}

@Test func onlyTheCanvasTargetMovesWhenALineAlsoCarriesAPlainLink() {
    let text = "- [ ] Testo [[Nota]] ^[[Vecchio.canvas]]"
    let updated = NoteRename.rewritingLinks(in: text, from: "Vecchio.canvas", to: "Nuovo.canvas")
    #expect(updated == "- [ ] Testo [[Nota]] ^[[Nuovo.canvas]]")
}

@Test func theRewrittenLineStillParsesAsAssignedToTheNewWorkspace() {
    let text = "- [ ] Testo ^[[Vecchio.canvas]] >2026-09-01"
    let updated = NoteRename.rewritingLinks(in: text, from: "Vecchio.canvas", to: "Nuovo.canvas")
    let task = updated.flatMap { TaskParser.parse(line: $0, sourcePath: "Nota.md", lineIndex: 0) }
    #expect(task?.workspacePath == "Nuovo.canvas")
}

// MARK: - The operations on disk

private struct OpsVault: ~Copyable {
    let root: URL
    let store: NoteStore
    let operations: NoteFileOperations

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-ops-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    func text(at relativePath: String) throws -> String {
        try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
    }

}

/// Free function rather than a method on `OpsVault`: `#expect` captures the whole
/// expression, and capturing a call on a non-copyable value does not compile.
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

@Test func renamingMovesTheFileAndFixesTheNotesPointingAtIt() throws {
    let vault = try OpsVault()
    let root = vault.root
    try vault.write(header + "Contenuto.", to: "03 Risorse/Vecchio titolo.md")
    try vault.write(header + "Vedi [[Vecchio titolo]].", to: "01 Progetti/Altra.md")

    let outcome = try vault.operations.rename(
        "03 Risorse/Vecchio titolo.md", to: "Nuovo titolo",
        knownPaths: ["03 Risorse/Vecchio titolo.md", "01 Progetti/Altra.md"]
    )

    #expect(outcome.newPath == "03 Risorse/Nuovo titolo.md")
    #expect(exists("03 Risorse/Nuovo titolo.md", in: root))
    #expect(!exists("03 Risorse/Vecchio titolo.md", in: root))
    #expect(try vault.text(at: "01 Progetti/Altra.md").contains("[[Nuovo titolo]]"))
    #expect(outcome.rewrittenPaths == ["01 Progetti/Altra.md"])
    #expect(outcome.failures.isEmpty)
}

@Test func renamingStaysInTheSameFolder() throws {
    let vault = try OpsVault()
    try vault.write(header, to: "02 Aree/coding/Nota.md")
    let outcome = try vault.operations.rename(
        "02 Aree/coding/Nota.md", to: "Nota rinominata", knownPaths: ["02 Aree/coding/Nota.md"]
    )
    #expect(outcome.newPath == "02 Aree/coding/Nota rinominata.md")
}

@Test func renamingOntoAnExistingNoteIsRefused() throws {
    let vault = try OpsVault()
    let root = vault.root
    try vault.write(header, to: "Uno.md")
    try vault.write(header, to: "Due.md")

    #expect(throws: FileOperationError.self) {
        try vault.operations.rename("Uno.md", to: "Due", knownPaths: ["Uno.md", "Due.md"])
    }
    // Both are still there: a refused rename must not have moved anything.
    #expect(exists("Uno.md", in: root))
    #expect(exists("Due.md", in: root))
}

@Test func renamingToANonConformantTitleIsRefusedBeforeAnythingMoves() throws {
    let vault = try OpsVault()
    let root = vault.root
    try vault.write(header, to: "Nota.md")

    #expect(throws: FileOperationError.self) {
        try vault.operations.rename("Nota.md", to: "Titolo/con slash", knownPaths: ["Nota.md"])
    }
    #expect(exists("Nota.md", in: root))
}

@Test func movingANoteDoesNotTouchTheLinksPointingAtIt() throws {
    let vault = try OpsVault()
    let root = vault.root
    try vault.write(header, to: "00 Inbox/Nota.md")
    try vault.write(header + "Vedi [[Nota]].", to: "Altra.md")

    let outcome = try vault.operations.move("00 Inbox/Nota.md", toFolder: "01 Progetti/vibrofer-emea")

    #expect(outcome.newPath == "01 Progetti/vibrofer-emea/Nota.md")
    #expect(exists("01 Progetti/vibrofer-emea/Nota.md", in: root))
    // A wikilink names a note by title, not by path: rewriting here would be wrong.
    #expect(try vault.text(at: "Altra.md").contains("[[Nota]]"))
}

@Test func movingOntoAnExistingFileIsRefused() throws {
    let vault = try OpsVault()
    let root = vault.root
    try vault.write(header, to: "Nota.md")
    try vault.write(header, to: "01 Progetti/Nota.md")

    #expect(throws: FileOperationError.self) {
        try vault.operations.move("Nota.md", toFolder: "01 Progetti")
    }
    #expect(exists("Nota.md", in: root))
}

@Test func deletingReportsWhatNowLinksToNothing() throws {
    let vault = try OpsVault()
    let root = vault.root
    try vault.write(header, to: "Sparita.md")
    try vault.write(header + "Vedi [[Sparita]].", to: "Rimasta.md")
    try vault.write(header + "Niente.", to: "Estranea.md")

    let dangling = try vault.operations.trash(
        "Sparita.md", knownPaths: ["Sparita.md", "Rimasta.md", "Estranea.md"]
    )

    #expect(!exists("Sparita.md", in: root))
    #expect(dangling == ["Rimasta.md"])
}

@Test func deletingSomethingThatIsNotThereIsAnError() throws {
    let vault = try OpsVault()
    #expect(throws: FileOperationError.self) {
        try vault.operations.trash("Mai esistita.md", knownPaths: [])
    }
}

// MARK: - Boards follow the file (SPEC §6.2)

private let board = """
{"nodes":[{"id":"a","type":"file","file":"01 Progetti/Nota.md","x":0,"y":0,"width":260,"height":180},\
{"id":"b","type":"file","file":"03 Risorse/Altro.pdf","x":300,"y":0,"width":260,"height":180}],"edges":[]}
"""

@Test func renamingRepointsTheCardsOnEveryBoard() throws {
    let vault = try OpsVault()
    let root = vault.root
    try vault.write(header, to: "01 Progetti/Nota.md")
    try vault.write(board, to: "Labs.canvas")

    let outcome = try vault.operations.rename(
        "01 Progetti/Nota.md", to: "Nota rinominata", knownPaths: ["01 Progetti/Nota.md"]
    )

    let updated = try vault.text(at: "Labs.canvas")
    // Otherwise the card points at a file that no longer exists, and nothing says why.
    #expect(updated.contains("01 Progetti/Nota rinominata.md"))
    #expect(!updated.contains("01 Progetti/Nota.md\""))
    #expect(updated.contains("03 Risorse/Altro.pdf"))
    #expect(outcome.rewrittenPaths.contains("Labs.canvas"))
    #expect(exists("01 Progetti/Nota rinominata.md", in: root))
}

@Test func movingRepointsTheCardsToo() throws {
    let vault = try OpsVault()
    try vault.write(header, to: "01 Progetti/Nota.md")
    try vault.write(board, to: "Labs.canvas")

    _ = try vault.operations.move("01 Progetti/Nota.md", toFolder: "02 Aree")

    #expect(try vault.text(at: "Labs.canvas").contains("02 Aree/Nota.md"))
}

@Test func aBoardThatDoesNotShowTheNoteIsLeftUntouched() throws {
    let vault = try OpsVault()
    try vault.write(header, to: "Sola.md")
    try vault.write(board, to: "Labs.canvas")
    let before = try vault.text(at: "Labs.canvas")

    _ = try vault.operations.rename("Sola.md", to: "Sola rinominata", knownPaths: ["Sola.md"])

    #expect(try vault.text(at: "Labs.canvas") == before)
}

// MARK: - Boards' own text cards follow a rename too

private let boardWithTextCard = """
{"nodes":[{"id":"a","type":"file","file":"01 Progetti/Nota.md","x":0,"y":0,"width":260,"height":180},\
{"id":"b","type":"text","text":"- [ ] vedi [[Nota]] per il dettaglio","x":300,"y":0,"width":260,"height":180}],"edges":[]}
"""

@Test func renamingRewritesWikilinksInsideATextCardOnEveryBoard() throws {
    let vault = try OpsVault()
    try vault.write(header, to: "01 Progetti/Nota.md")
    try vault.write(boardWithTextCard, to: "Labs.canvas")

    _ = try vault.operations.rename(
        "01 Progetti/Nota.md", to: "Nota rinominata", knownPaths: ["01 Progetti/Nota.md"]
    )

    let updated = try vault.text(at: "Labs.canvas")
    #expect(updated.contains("[[Nota rinominata]]"))
    #expect(!updated.contains("[[Nota]]"))
    #expect(updated.contains("01 Progetti/Nota rinominata.md"))
}

@Test func aTextCardWithNoMatchingWikilinkIsLeftByteIdentical() throws {
    let vault = try OpsVault()
    try vault.write(header, to: "Sola.md")
    try vault.write(boardWithTextCard, to: "Labs.canvas")
    let before = try vault.text(at: "Labs.canvas")

    _ = try vault.operations.rename("Sola.md", to: "Sola rinominata", knownPaths: ["Sola.md"])

    #expect(try vault.text(at: "Labs.canvas") == before)
}

@Test func movingDoesNotTouchATextCardsWikilink() throws {
    let vault = try OpsVault()
    try vault.write(header, to: "01 Progetti/Nota.md")
    try vault.write(boardWithTextCard, to: "Labs.canvas")

    _ = try vault.operations.move("01 Progetti/Nota.md", toFolder: "02 Aree")

    let updated = try vault.text(at: "Labs.canvas")
    // A move never changes the note's title, so the wikilink (which names by title,
    // not by path - wikilink.md W-01) has nothing to rewrite.
    #expect(updated.contains("[[Nota]]"))
    #expect(updated.contains("02 Aree/Nota.md"))
}

private let boardWithUnrelatedQuotedBullet = """
{"nodes":[{"id":"a","type":"file","file":"01 Progetti/Capture.md","x":0,"y":0,"width":260,"height":180},\
{"id":"b","type":"text","text":"idee sparse:\\n- \\"Capture\\"\\n- altro punto","x":300,"y":0,"width":260,"height":180}],"edges":[]}
"""

@Test func renamingDoesNotRewriteAnUnrelatedQuotedBulletInATextCard() throws {
    // A `.text` card has no `related:` frontmatter, so NoteRename's quoted-related
    // fallback must not run for it - otherwise a plain bullet line that happens to
    // fold-match the old title (`- "Capture"`) would be silently corrupted even
    // though it names nothing and links to nothing.
    let vault = try OpsVault()
    try vault.write(header, to: "01 Progetti/Capture.md")
    try vault.write(boardWithUnrelatedQuotedBullet, to: "Labs.canvas")

    _ = try vault.operations.rename(
        "01 Progetti/Capture.md", to: "Piano editoriale", knownPaths: ["01 Progetti/Capture.md"]
    )

    let updated = try vault.text(at: "Labs.canvas")
    #expect(updated.contains("- \\\"Capture\\\""))
    #expect(!updated.contains("Piano editoriale\\\"\\n- altro"))
    #expect(updated.contains("01 Progetti/Piano editoriale.md"))
}
