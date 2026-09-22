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

// MARK: - The operations, re-pointed at the plan half after ADR-0055 §D6
//
// `NoteFileOperations.rename`/`move`/`trash` are deleted (ADR-0055 §D6): the app's one note
// performer is `VaultSession.renameNote`/`moveNote`/`trashNote`
// (`Tests/VaultSessionFileOperationsTests.swift`), and what these tests pinned - the bytes a
// rename or a move computes - is exactly what `renamePlan`/`movePlan` compute, without writing
// a byte. Every assertion below is re-pointed per the rule the ADR states: computed bytes move
// onto `renamePlan`/`movePlan`, validation-before-anything-moves throws out of the same plan
// (true by construction, since a plan never touches disk), and "what ends up on disk and what
// moved" is proven where a real performer exists.

private struct OpsVault: ~Copyable {
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

@Test func renamePlanComputesTheRewrittenLinkAndTheDestinationPath() throws {
    let vault = try OpsVault()
    try vault.write(header + "Contenuto.", to: "03 Risorse/Vecchio titolo.md")
    try vault.write(header + "Vedi [[Vecchio titolo]].", to: "01 Progetti/Altra.md")

    let plan = try vault.operations.renamePlan(
        "03 Risorse/Vecchio titolo.md", to: "Nuovo titolo",
        knownPaths: ["03 Risorse/Vecchio titolo.md", "01 Progetti/Altra.md"]
    )

    #expect(plan.newPath == "03 Risorse/Nuovo titolo.md")
    let change = try #require(plan.noteChanges.first { $0.path == "01 Progetti/Altra.md" })
    #expect(change.after.contains("[[Nuovo titolo]]"))
    #expect(plan.failures.isEmpty)
    // What actually ends up on disk - the file moved, the link rewritten there too, as one
    // gesture - is `Tests/VaultSessionFileOperationsTests.swift`'s
    // `renamingANoteMovesItRewritesALinkAndRepointsABoardAsOneGesture`: the same computation,
    // driven through the real production performer (ADR-0055 §D6).
}

@Test func renamePlanReportsAnUnreadableKnownPathAsAFailureRatherThanThrowing() throws {
    let vault = try OpsVault()
    try vault.write(header + "Vedi [[Nota B]] per il dettaglio.", to: "A.md")
    try vault.write(header + "Questa è [[Nota B]].", to: "Nota B.md")
    // Not valid UTF-8: `store.text` throws reading it, which `renamePlan`'s own loop catches
    // and reports rather than letting escape (`NoteRenameCharacterizationTests.swift` no
    // longer carries this case - a real rename derives `knownPaths` from the index, and an
    // unreadable note never joins it, so this scenario only exists at the plan level now).
    try Data([0xFF, 0xFE, 0xFD, 0x00, 0x01]).write(to: vault.root.appending(path: "C.md"))

    let plan = try vault.operations.renamePlan(
        "Nota B.md", to: "Nota B rinominata", knownPaths: ["A.md", "Nota B.md", "C.md"]
    )

    #expect(plan.failures == ["C.md: non leggibile"])
}

@Test func renamePlanKeepsTheDestinationInTheSameFolder() throws {
    let vault = try OpsVault()
    try vault.write(header, to: "02 Aree/coding/Nota.md")
    let plan = try vault.operations.renamePlan(
        "02 Aree/coding/Nota.md", to: "Nota rinominata", knownPaths: ["02 Aree/coding/Nota.md"]
    )
    #expect(plan.newPath == "02 Aree/coding/Nota rinominata.md")
}

@Test func renamePlanRefusesACollisionBeforeAnythingMoves() throws {
    let vault = try OpsVault()
    let root = vault.root
    try vault.write(header, to: "Uno.md")
    try vault.write(header, to: "Due.md")

    #expect(throws: FileOperationError.self) {
        try vault.operations.renamePlan("Uno.md", to: "Due", knownPaths: ["Uno.md", "Due.md"])
    }
    // Both are still there: a plan never touches disk, so "nothing moved" is true by
    // construction rather than something the throw alone proves.
    #expect(exists("Uno.md", in: root))
    #expect(exists("Due.md", in: root))
}

@Test func renamePlanRefusesANonConformantTitleBeforeAnythingMoves() throws {
    let vault = try OpsVault()
    let root = vault.root
    try vault.write(header, to: "Nota.md")

    #expect(throws: FileOperationError.self) {
        try vault.operations.renamePlan("Nota.md", to: "Titolo/con slash", knownPaths: ["Nota.md"])
    }
    #expect(exists("Nota.md", in: root))
}

@Test func movePlanRefusesACollisionBeforeAnythingMoves() throws {
    let vault = try OpsVault()
    let root = vault.root
    try vault.write(header, to: "Nota.md")
    try vault.write(header, to: "01 Progetti/Nota.md")

    #expect(throws: FileOperationError.self) {
        try vault.operations.movePlan("Nota.md", toFolder: "01 Progetti")
    }
    #expect(exists("Nota.md", in: root))
}

@Test func danglingLinksReportsWhatNowLinksToNothing() throws {
    let vault = try OpsVault()
    try vault.write(header, to: "Sparita.md")
    try vault.write(header + "Vedi [[Sparita]].", to: "Rimasta.md")
    try vault.write(header + "Niente.", to: "Estranea.md")

    // Read rather than written (`NoteFileOperations.danglingLinks`'s own doc comment): the
    // note named here need not actually be gone from disk for this to answer correctly, and
    // it is what `VaultSession.trashNote` calls for real once a note is trashed (see
    // `Tests/VaultSessionFileOperationsTests.swift`'s
    // `trashingANoteInsideItsOwnTransactionStillReportsDanglingLinks` for the disk half).
    let dangling = vault.operations.danglingLinks(
        for: "Sparita.md", knownPaths: ["Sparita.md", "Rimasta.md", "Estranea.md"]
    )

    #expect(dangling == ["Rimasta.md"])
}

// MARK: - Boards follow the file (SPEC §6.2)

private let board = """
{"nodes":[{"id":"a","type":"file","file":"01 Progetti/Nota.md","x":0,"y":0,"width":260,"height":180},\
{"id":"b","type":"file","file":"03 Risorse/Altro.pdf","x":300,"y":0,"width":260,"height":180}],"edges":[]}
"""

@Test func renamePlanRepointsTheCardsOnEveryBoard() throws {
    let vault = try OpsVault()
    try vault.write(header, to: "01 Progetti/Nota.md")
    try vault.write(board, to: "Labs.canvas")

    let plan = try vault.operations.renamePlan(
        "01 Progetti/Nota.md", to: "Nota rinominata", knownPaths: ["01 Progetti/Nota.md"]
    )

    let change = try #require(plan.boardChanges.first { $0.path == "Labs.canvas" })
    // Otherwise the card points at a file that no longer exists, and nothing says why.
    #expect(change.after.contains("01 Progetti/Nota rinominata.md"))
    #expect(!change.after.contains("01 Progetti/Nota.md\""))
    #expect(change.after.contains("03 Risorse/Altro.pdf"))
    // What actually ends up on disk is the same production gesture
    // `Tests/VaultSessionFileOperationsTests.swift`'s
    // `renamingANoteMovesItRewritesALinkAndRepointsABoardAsOneGesture` already drives.
}

@Test func movePlanRepointsTheCardsToo() throws {
    let vault = try OpsVault()
    try vault.write(header, to: "01 Progetti/Nota.md")
    try vault.write(board, to: "Labs.canvas")

    let plan = try vault.operations.movePlan("01 Progetti/Nota.md", toFolder: "02 Aree")

    let change = try #require(plan.boardChanges.first { $0.path == "Labs.canvas" })
    #expect(change.after.contains("02 Aree/Nota.md"))
    // What actually ends up on disk is
    // `Tests/VaultSessionFileOperationsTests.swift`'s
    // `movingANoteViaTheSessionLeavesLinksAloneAndRepointsTheBoards`.
}

@Test func renamePlanLeavesAnUnrelatedBoardOutOfBoardChanges() throws {
    let vault = try OpsVault()
    try vault.write(header, to: "Sola.md")
    try vault.write(board, to: "Labs.canvas")

    let plan = try vault.operations.renamePlan("Sola.md", to: "Sola rinominata", knownPaths: ["Sola.md"])

    #expect(plan.boardChanges.isEmpty)
}

// MARK: - Boards' own text cards follow a rename too

private let boardWithTextCard = """
{"nodes":[{"id":"a","type":"file","file":"01 Progetti/Nota.md","x":0,"y":0,"width":260,"height":180},\
{"id":"b","type":"text","text":"- [ ] vedi [[Nota]] per il dettaglio","x":300,"y":0,"width":260,"height":180}],"edges":[]}
"""

@Test func renamePlanRewritesWikilinksInsideATextCardOnEveryBoard() throws {
    let vault = try OpsVault()
    try vault.write(header, to: "01 Progetti/Nota.md")
    try vault.write(boardWithTextCard, to: "Labs.canvas")

    let plan = try vault.operations.renamePlan(
        "01 Progetti/Nota.md", to: "Nota rinominata", knownPaths: ["01 Progetti/Nota.md"]
    )

    let change = try #require(plan.boardChanges.first { $0.path == "Labs.canvas" })
    #expect(change.after.contains("[[Nota rinominata]]"))
    #expect(!change.after.contains("[[Nota]]"))
    #expect(change.after.contains("01 Progetti/Nota rinominata.md"))
}

@Test func renamePlanLeavesATextCardWithNoMatchingWikilinkOutOfBoardChanges() throws {
    let vault = try OpsVault()
    try vault.write(header, to: "Sola.md")
    try vault.write(boardWithTextCard, to: "Labs.canvas")

    let plan = try vault.operations.renamePlan("Sola.md", to: "Sola rinominata", knownPaths: ["Sola.md"])

    #expect(plan.boardChanges.isEmpty)
}

@Test func movePlanDoesNotTouchATextCardsWikilink() throws {
    let vault = try OpsVault()
    try vault.write(header, to: "01 Progetti/Nota.md")
    try vault.write(boardWithTextCard, to: "Labs.canvas")

    let plan = try vault.operations.movePlan("01 Progetti/Nota.md", toFolder: "02 Aree")

    let change = try #require(plan.boardChanges.first { $0.path == "Labs.canvas" })
    // A move never changes the note's title, so the wikilink (which names by title,
    // not by path - wikilink.md W-01) has nothing to rewrite.
    #expect(change.after.contains("[[Nota]]"))
    #expect(change.after.contains("02 Aree/Nota.md"))
}

private let boardWithUnrelatedQuotedBullet = """
{"nodes":[{"id":"a","type":"file","file":"01 Progetti/Capture.md","x":0,"y":0,"width":260,"height":180},\
{"id":"b","type":"text","text":"idee sparse:\\n- \\"Capture\\"\\n- altro punto","x":300,"y":0,"width":260,"height":180}],"edges":[]}
"""

@Test func renamePlanDoesNotRewriteAnUnrelatedQuotedBulletInATextCard() throws {
    // A `.text` card has no `related:` frontmatter, so NoteRename's quoted-related
    // fallback must not run for it - otherwise a plain bullet line that happens to
    // fold-match the old title (`- "Capture"`) would be silently corrupted even
    // though it names nothing and links to nothing.
    let vault = try OpsVault()
    try vault.write(header, to: "01 Progetti/Capture.md")
    try vault.write(boardWithUnrelatedQuotedBullet, to: "Labs.canvas")

    let plan = try vault.operations.renamePlan(
        "01 Progetti/Capture.md", to: "Piano editoriale", knownPaths: ["01 Progetti/Capture.md"]
    )

    let change = try #require(plan.boardChanges.first { $0.path == "Labs.canvas" })
    #expect(change.after.contains("- \\\"Capture\\\""))
    #expect(!change.after.contains("Piano editoriale\\\"\\n- altro"))
    #expect(change.after.contains("01 Progetti/Piano editoriale.md"))
}
