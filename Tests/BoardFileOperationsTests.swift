import Foundation
import Testing
@testable import Pergamenum

// ADR-0025: A folder is a container, a board is a file, and neither is named after the
// other. §D6 - board rename and board delete are file operations in the folder-verb
// layer, and ADR-0022 §D4's ambiguity guard moves here from folder rename.
// Plan: docs/superpowers/plans/2026-08-27-workspace-folder-board-separation.md, Task 7.
//
// `BoardFileOperations` is `FolderFileOperations`'s shape for a `.canvas` file instead
// of a directory: a rename plan computed off disk, then performed in one pass - rename
// on disk, delete to the Trash. RED: every body currently throws
// `FileOperationError.notImplementedYet`, so every test below fails on
// its assertions (or on the uncaught throw), not on a missing symbol.
//
// ADR-0026: A row is dragged into a folder, and several rows are chosen first. §D1/§D7 -
// a board move keeps its file name and changes only its folder, and repoints `.canvas`
// node paths vault-wide through the same `repointBoardsPlan` loop a rename already runs.
// Plan: docs/superpowers/plans/2026-08-27-drag-and-drop-board-files-into-workspace.md,
// Task 2.
//
// RED (ADR-0026 section below): `movePlan`/`moveBoard` are placeholders returning the
// unchanged path and writing nothing, so every test in that section fails on its
// assertions, not on a missing symbol.

// MARK: - Fixtures and helpers

private struct BoardOpsVault: ~Copyable {
    private let base: TemporaryVault
    let store: NoteStore
    let operations: BoardFileOperations
    var root: URL { base.root }

    init() throws {
        let base = try TemporaryVault()
        store = NoteStore(root: base.root)
        operations = BoardFileOperations(store: store)
        self.base = base
    }

    func write(_ contents: String, to relativePath: String) throws {
        try base.write(contents, to: relativePath)
    }

    func text(at relativePath: String) throws -> String {
        try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
    }
}

/// Free functions rather than methods on `BoardOpsVault`: `#expect` captures the whole
/// expression, and capturing a call on a non-copyable value does not compile.
private func exists(_ relativePath: String, in root: URL) -> Bool {
    FileManager.default.fileExists(atPath: root.appending(path: relativePath).path(percentEncoded: false))
}

private let header = """
---
date: 2026-08-25
tags:
  - type-note
---


"""

private let sampleBoard = """
{"nodes":[],"edges":[]}
"""

// MARK: - Rename: moves the file, byte-identical, folder untouched (R-08)

@Test func renameBoardMovesTheFileByteIdenticalAndLeavesTheFolderUntouched() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/vecchio.canvas")
    try vault.write(header, to: "A/Nota.md")

    let outcome = try vault.operations.renameBoard(
        at: "A/vecchio.canvas", to: "nuovo", knownPaths: ["A/Nota.md"]
    )

    #expect(outcome.newPath == "A/nuovo.canvas")
    #expect(!exists("A/vecchio.canvas", in: vault.root))
    #expect(exists("A/nuovo.canvas", in: vault.root))
    #expect(try vault.text(at: "A/nuovo.canvas") == sampleBoard)
    // The folder itself - and everything else in it - is untouched.
    #expect(exists("A/Nota.md", in: vault.root))
}

// MARK: - Rename refuses a collision before writing anything

@Test func renamePlanRefusesANameAnotherBoardInTheSameFolderAlreadyHas() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/vecchio.canvas")
    try vault.write(sampleBoard, to: "A/nuovo.canvas")

    #expect(throws: FileOperationError.self) {
        try vault.operations.renamePlan("A/vecchio.canvas", to: "nuovo", knownPaths: [])
    }
}

@Test func renameBoardWritesNothingWhenTheDestinationNameIsTaken() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/vecchio.canvas")
    try vault.write("{\"nodes\":[],\"edges\":[],\"marker\":true}", to: "A/nuovo.canvas")

    #expect(throws: FileOperationError.self) {
        try vault.operations.renameBoard(at: "A/vecchio.canvas", to: "nuovo", knownPaths: [])
    }
    // Both files are exactly where - and what - they started: the collision is refused
    // before any write happens.
    #expect(exists("A/vecchio.canvas", in: vault.root))
    #expect(try vault.text(at: "A/nuovo.canvas") == "{\"nodes\":[],\"edges\":[],\"marker\":true}")
}

// MARK: - Rename rewrites the task marker and the plain link, through `NoteRename` unchanged

@Test func renamePlanRewritesTheTaskMarkerAndThePlainLinkToTheNewBoardName() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/vecchio.canvas")
    try vault.write(header + "- [ ] Fare ^[[vecchio.canvas]]", to: "Attività.md")
    try vault.write(header + "Vedi [[vecchio.canvas]].", to: "Altra.md")

    let plan = try vault.operations.renamePlan(
        "A/vecchio.canvas", to: "nuovo", knownPaths: ["Attività.md", "Altra.md"]
    )

    let taskChange = try #require(plan.noteChanges.first { $0.path == "Attività.md" })
    #expect(taskChange.after.contains("^[[nuovo.canvas]]"))

    let linkChange = try #require(plan.noteChanges.first { $0.path == "Altra.md" })
    #expect(linkChange.after.contains("[[nuovo.canvas]]"))
}

// MARK: - Rename surfaces the real read error instead of a flat "non leggibile" (PG-063)

@Test func renamePlanReportsTheRealStoreErrorWhenAKnownPathIsNotReadable() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/vecchio.canvas")
    let binaryURL = vault.root.appending(path: "binaria.md")
    try Data([0xFF, 0xFE, 0x00, 0x01]).write(to: binaryURL)

    let plan = try vault.operations.renamePlan(
        "A/vecchio.canvas", to: "nuovo", knownPaths: ["binaria.md"]
    )

    let failure = try #require(plan.failures.first { $0.contains("binaria.md") })
    #expect(failure.contains("not valid UTF-8"))
    #expect(!failure.contains("non leggibile"))
}

// MARK: - Rename repoints a `.canvas` node elsewhere, preserving unknown keys

@Test func renamePlanRepointsACanvasNodeInAnotherBoardPreservingUnknownKeys() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/vecchio.canvas")
    let otherBoard = """
    {"nodes":[\
    {"id":"a","type":"file","file":"A/vecchio.canvas","x":0,"y":0,"width":260,"height":180,\
    "pergamenum-crop":{"x":0,"y":0,"width":1,"height":1}}\
    ],"edges":[],"pergamenum-something":"kept"}
    """
    try vault.write(otherBoard, to: "Labs.canvas")

    let plan = try vault.operations.renamePlan("A/vecchio.canvas", to: "nuovo", knownPaths: [])

    let change = try #require(plan.boardChanges.first { $0.path == "Labs.canvas" })
    #expect(change.after.contains("A/nuovo.canvas"))
    #expect(!change.after.contains("A/vecchio.canvas"))
    // Unknown keys - the app's own crop scalar and a made-up top-level key - survive
    // the decode/re-encode round trip through `CanvasDocument` (ADR-0022 §D2.1's
    // mechanism, reused rather than patching the file as text).
    #expect(change.after.contains("pergamenum-crop"))
    #expect(change.after.contains("pergamenum-something"))
}

// MARK: - The relocated ADR-0022 §D4 guard, now on board rename (ADR-0025 §D6)

@Test func renamePlanSkipsTheMarkerRewriteAndReportsAFailureNamingTheCountWhenTheOldNameIsAmbiguous() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/vecchio.canvas")
    try vault.write(sampleBoard, to: "B/vecchio.canvas")
    try vault.write(header + "- [ ] Fare ^[[vecchio.canvas]]", to: "Attività.md")
    let otherBoard = """
    {"nodes":[{"id":"a","type":"file","file":"A/vecchio.canvas","x":0,"y":0,"width":260,"height":180}],"edges":[]}
    """
    try vault.write(otherBoard, to: "Labs.canvas")

    let plan = try vault.operations.renamePlan(
        "A/vecchio.canvas", to: "nuovo", knownPaths: ["Attività.md"]
    )

    // Every `^[[vecchio.canvas]]` marker is left untouched - it still might mean
    // `B/vecchio.canvas` - and the failure names the count of boards sharing the name.
    #expect(plan.noteChanges.isEmpty)
    #expect(plan.failures.contains { $0.contains("vecchio.canvas") && $0.contains("2") })
    // The path-level repoint is unambiguous by construction (it names a full vault path,
    // not a bare file name) and still runs.
    #expect(plan.boardChanges.contains { $0.path == "Labs.canvas" })
}

// MARK: - An ordinary wikilink is untouched (regression, ADR-0022 §D2/§D3 restated)

// A wikilink names a note by title, not by path, so a board rename - which changes a
// file name, never a note title - rewrites no ordinary `[[Nota]]` link. Do not "fix"
// this test to expect a rewrite.
@Test func regressionAnOrdinaryWikilinkToANoteIsByteIdenticalAfterABoardRename() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/vecchio.canvas")
    let noteText = header + "Vedi [[Nota interna]]."
    try vault.write(noteText, to: "Altra.md")

    let plan = try vault.operations.renamePlan(
        "A/vecchio.canvas", to: "nuovo", knownPaths: ["Altra.md"]
    )

    #expect(!plan.noteChanges.contains { $0.path == "Altra.md" })
}

// MARK: - Delete: Trash URL, no marker rewrite, folder left in place (ADR-0022 §D7, F9)

@Test func trashBoardMovesTheFileToTheTrashReturnsTheResultingURLAndLeavesTheFolderInPlace() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/x.canvas")
    try vault.write(header, to: "A/Nota.md")
    try vault.write(header + "- [ ] Fare ^[[x.canvas]]", to: "Attività.md")

    let trashURL = try vault.operations.trashBoard(at: "A/x.canvas")

    // `removeItem` could not have produced a resulting URL - this is what proves
    // `trashItem` was used (ADR-0022 §D7).
    let url = try #require(trashURL)
    #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    #expect(!exists("A/x.canvas", in: vault.root))
    #expect(exists("A/Nota.md", in: vault.root))
    // No marker rewrite on delete.
    #expect(try vault.text(at: "Attività.md").contains("^[[x.canvas]]"))

    // The orphaned marker is a first-class outcome, not a dangling reference nobody
    // models (ADR-0025 F9).
    let remainingBoards = CanvasStore(root: vault.root).allBoards()
    #expect(WorkspaceBoardResolver.resolve("x.canvas", in: remainingBoards) == .notFound)
}

@Test func trashBoardThrowsForABoardThatIsNotThere() throws {
    let vault = try BoardOpsVault()

    #expect(throws: FileOperationError.self) {
        try vault.operations.trashBoard(at: "A/mai-esistito.canvas")
    }
}

// MARK: - ADR-0026: Move keeps the file name and repoints cards (R-01, R-05, R-06, R-07, R-08, §D7)

/// True only for `.unique(_)`, whatever path it carries - the payload legitimately
/// differs before and after a move (`A/x.canvas` vs `B/x.canvas`); it is the *case* that
/// must stay stable across the move (R-08), not the associated value.
private func isUnique(_ resolution: WorkspaceBoardResolution) -> Bool {
    if case .unique = resolution { return true }
    return false
}

@Test func moveBoardMovesTheFileToTheDestinationFolderKeepingItsFileName() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/x.canvas")

    let outcome = try vault.operations.moveBoard(at: "A/x.canvas", toFolder: "B")

    #expect(outcome.newPath == "B/x.canvas")
    #expect(!exists("A/x.canvas", in: vault.root))
    #expect(exists("B/x.canvas", in: vault.root))
    #expect(try vault.text(at: "B/x.canvas") == sampleBoard)
}

@Test func moveBoardLeavesTheTaskMarkerByteIdenticalAndKeepsWorkspaceBoardResolverUnique() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/x.canvas")
    let markerNote = header + "- [ ] Fare ^[[x.canvas]]"
    try vault.write(markerNote, to: "Attività.md")

    let resolutionBefore = WorkspaceBoardResolver.resolve(
        "x.canvas", in: CanvasStore(root: vault.root).allBoards()
    )

    _ = try vault.operations.moveBoard(at: "A/x.canvas", toFolder: "B")

    // The marker text itself is never touched by a move (ADR-0026 §D7) - it names a
    // bare file name, and the move changes no file name.
    #expect(try vault.text(at: "Attività.md") == markerNote)
    let resolutionAfter = WorkspaceBoardResolver.resolve(
        "x.canvas", in: CanvasStore(root: vault.root).allBoards()
    )
    #expect(isUnique(resolutionBefore))
    #expect(isUnique(resolutionAfter))
    #expect(resolutionAfter == .unique(BoardPath(value: "B/x.canvas")))
}

@Test func moveBoardRepointsACardOnAnotherBoardThatPointedAtItsOldPath() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/x.canvas")
    let rootBoard = """
    {"nodes":[\
    {"id":"a","type":"file","file":"A/x.canvas","x":0,"y":0,"width":260,"height":180}\
    ],"edges":[]}
    """
    try vault.write(rootBoard, to: "Labs.canvas")

    _ = try vault.operations.moveBoard(at: "A/x.canvas", toFolder: "B")

    let labsText = try vault.text(at: "Labs.canvas")
    #expect(labsText.contains("B/x.canvas"))
    #expect(!labsText.contains("\"A/x.canvas\""))
}

@Test func moveBoardThrowsAlreadyExistsForACollisionAndWritesNothing() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/x.canvas")
    try vault.write("{\"nodes\":[],\"edges\":[],\"marker\":true}", to: "B/x.canvas")

    do {
        _ = try vault.operations.moveBoard(at: "A/x.canvas", toFolder: "B")
        Issue.record("expected moveBoard to throw for a name collision at the destination")
    } catch FileOperationError.alreadyExists(let path) {
        #expect(path.contains("x.canvas"))
    } catch {
        Issue.record("expected FileOperationError.alreadyExists, got \(error)")
    }
    // Nothing moved, nothing was overwritten.
    #expect(exists("A/x.canvas", in: vault.root))
    #expect(try vault.text(at: "B/x.canvas") == "{\"nodes\":[],\"edges\":[],\"marker\":true}")
}

@Test func moveBoardToItsCurrentFolderIsANoOpAndWritesNothing() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/x.canvas")

    let outcome = try vault.operations.moveBoard(at: "A/x.canvas", toFolder: "A")

    #expect(outcome.newPath == "A/x.canvas")
    #expect(exists("A/x.canvas", in: vault.root))
    #expect(try vault.text(at: "A/x.canvas") == sampleBoard)
}

@Test func moveBoardToTheVaultRootWorks() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/x.canvas")

    let outcome = try vault.operations.moveBoard(at: "A/x.canvas", toFolder: "")

    #expect(outcome.newPath == "x.canvas")
    #expect(!exists("A/x.canvas", in: vault.root))
    #expect(exists("x.canvas", in: vault.root))
}

@Test func boardMovePlanWritesNothing() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/x.canvas")

    _ = try vault.operations.movePlan("A/x.canvas", toFolder: "B")

    #expect(exists("A/x.canvas", in: vault.root))
    #expect(!exists("B/x.canvas", in: vault.root))
}

// MARK: - ADR-0054 §D6: the board repoint write is guarded, a stale sibling refuses
//
// `renamePlan`'s/`movePlan`'s own read is synchronous and immediately followed by the
// write with no controllable in-process window, so a refusal is forced the way
// ADR-0046 §D11 prescribes: at the writer seam, by driving `CanvasStore.writeRepoint`
// directly with a hand-built `VaultFileChange` whose `before` disagrees with what is
// really on disk - not a re-spelling of `renameBoard`/`moveBoard`, the production writer
// under test (`Tests/VaultSessionFileOperationsTests.swift`'s precedent for the note door).

@Test func aSiblingBoardWhoseBytesMovedOnIsRefusedThroughWriteRepointOnRename() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/vecchio.canvas")
    let sibling = """
    {"nodes":[{"id":"a","type":"file","file":"A/vecchio.canvas","x":0,"y":0,"width":260,"height":180}],"edges":[]}
    """
    try vault.write(sibling, to: "Labs.canvas")

    let plan = try vault.operations.renamePlan("A/vecchio.canvas", to: "nuovo", knownPaths: [])
    let staleChanges = plan.boardChanges.map {
        VaultFileChange(path: $0.path, before: "{\"nodes\":[],\"stale\":true}", after: $0.after)
    }
    let originalBoard = try vault.text(at: "Labs.canvas")

    let canvas = CanvasStore(root: vault.root)
    let result = VaultPlanApplication.apply(staleChanges, writing: canvas.writeRepoint)

    #expect(result.refusals == ["Labs.canvas"])
    #expect(result.rewrittenPaths.isEmpty)
    #expect(try vault.text(at: "Labs.canvas") == originalBoard)
}

@Test func theRepointLoopOnAMoveReportsARefusalAndStillRepointsTheOtherSiblings() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/x.canvas")
    let stale = """
    {"nodes":[{"id":"a","type":"file","file":"A/x.canvas","x":0,"y":0,"width":260,"height":180}],"edges":[]}
    """
    let fine = """
    {"nodes":[{"id":"b","type":"file","file":"A/x.canvas","x":0,"y":0,"width":260,"height":180}],"edges":[]}
    """
    try vault.write(stale, to: "Stale.canvas")
    try vault.write(fine, to: "Fine.canvas")

    let plan = try vault.operations.movePlan("A/x.canvas", toFolder: "B")
    let changes = plan.boardChanges.map { change in
        change.path == "Stale.canvas"
            ? VaultFileChange(path: change.path, before: "{\"nodes\":[],\"stale\":true}", after: change.after)
            : change
    }
    let originalStale = try vault.text(at: "Stale.canvas")

    let canvas = CanvasStore(root: vault.root)
    let result = VaultPlanApplication.apply(changes, writing: canvas.writeRepoint)

    #expect(result.refusals == ["Stale.canvas"])
    #expect(result.rewrittenPaths == ["Fine.canvas"])
    #expect(try vault.text(at: "Stale.canvas") == originalStale)
    #expect(try vault.text(at: "Fine.canvas").contains("B/x.canvas"))
}
