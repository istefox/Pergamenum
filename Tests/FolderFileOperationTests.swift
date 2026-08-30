import Foundation
import Testing
@testable import Pergamenum

// ADR-0022: Creating, renaming and deleting a workspace is a folder operation,
// performed outside the journal.
// Plan: docs/superpowers/plans/2026-08-25-workspace-ui-creazione-board-toolbar-e-r.md,
// Tasks 1-3.
//
// `FolderFileOperations` is `NoteFileOperations`'s direct-write half, re-shaped for a
// folder: validation and collision (Task 1), a rename plan computed off disk (Task 2),
// and performing it - rename on disk, delete to the Trash (Task 3). All three tasks are
// RED here: the type exists so the target builds, but every body currently throws or
// returns a placeholder, so every test below fails on its assertions.
//
// ADR-0025 §D6, Task 7 (R-09): a folder rename stops touching boards at all - no board
// file it holds is renamed, no marker is rewritten, and the ADR-0022 §D4 ambiguity
// guard is gone from here (relocated to board rename,
// `Tests/BoardFileOperationsTests.swift`). The tests below that pinned the old
// behaviour (`FolderRenamePlan.boardRename`, the name-level marker rewrite on a folder
// rename) are replaced by the ones in the new "ADR-0025 Task 7" section below; the
// vault-wide `.canvas` node repoint by prefix is unchanged and its tests are untouched.
//
// ADR-0026: A row is dragged into a folder, and several rows are chosen first. §D1/§D7 -
// a folder move keeps its own name and changes only its parent, carrying everything
// inside it, and repoints `.canvas` node paths vault-wide through the same
// `repointBoardsPlan` loop a rename already runs. `FileOperationError.wouldNest` refuses a
// folder dropped onto itself or one of its own descendants (§D5, R-06).
// Plan: docs/superpowers/plans/2026-08-27-drag-and-drop-board-files-into-workspace.md,
// Task 2.
//
// RED (ADR-0026 section below): `movePlan`/`moveFolder` are placeholders returning the
// unchanged path, moving nothing and writing nothing, so every test in that section
// fails on its assertions, not on a missing symbol.

// MARK: - Fixtures and helpers

private struct FolderOpsVault: ~Copyable {
    let root: URL
    let store: NoteStore
    let operations: FolderFileOperations

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-folder-ops-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = NoteStore(root: root)
        operations = FolderFileOperations(store: store)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    func write(_ contents: String, to relativePath: String) throws {
        let url = root.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    func createDirectory(_ relativePath: String) throws {
        try FileManager.default.createDirectory(
            at: root.appending(path: relativePath, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }

    func text(at relativePath: String) throws -> String {
        try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
    }
}

/// Free functions rather than methods on `FolderOpsVault`: `#expect` captures the whole
/// expression, and capturing a call on a non-copyable value does not compile.
private func exists(_ relativePath: String, in root: URL) -> Bool {
    FileManager.default.fileExists(atPath: root.appending(path: relativePath).path(percentEncoded: false))
}

private func isDirectory(_ relativePath: String, in root: URL) -> Bool {
    var flag: ObjCBool = false
    let found = FileManager.default.fileExists(
        atPath: root.appending(path: relativePath).path(percentEncoded: false), isDirectory: &flag
    )
    return found && flag.boolValue
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

// MARK: - Task 1: validation, collision, content counts (R-03, R-04, R-10, R-13)

@Test func validateDelegatesToNoteNameValidate() {
    #expect(!FolderFileOperations.validate("Progetto/uno").isEmpty)
    #expect(FolderFileOperations.validate("Ricerca 2026").isEmpty)
}

@Test func nameIsAvailableIsFalseWhenADirectoryAlreadyExists() throws {
    let vault = try FolderOpsVault()
    try vault.createDirectory("01 Progetti/Nuova")

    #expect(!vault.operations.nameIsAvailable("Nuova", in: "01 Progetti"))
}

@Test func nameIsAvailableIsFalseWhenAPlainFileAlreadyExists() throws {
    let vault = try FolderOpsVault()
    try vault.write("qualcosa", to: "01 Progetti/Nuova")

    #expect(!vault.operations.nameIsAvailable("Nuova", in: "01 Progetti"))
}

@Test func nameIsAvailableIsTrueOtherwise() throws {
    let vault = try FolderOpsVault()

    #expect(vault.operations.nameIsAvailable("Nuova", in: "01 Progetti"))
}

@Test func nameIsAvailableComparesCaseTheWayTheFilesystemDoesRatherThanLowercasing() throws {
    let vault = try FolderOpsVault()
    try vault.createDirectory("01 Progetti/Nuova")

    // This machine's volume is case-insensitive: creating "Nuova" must make "nuova"
    // unavailable too, without the check lowercasing either string itself.
    #expect(!vault.operations.nameIsAvailable("nuova", in: "01 Progetti"))
    #expect(!vault.operations.nameIsAvailable("Nuova", in: "01 Progetti"))
}

@Test func contentCountsCountsNotesAndSubfoldersRecursivelySkippingTheBoardAndOtherFiles() throws {
    let vault = try FolderOpsVault()
    try vault.write(header, to: "01 Progetti/vibrofer/a.md")
    try vault.write(header, to: "01 Progetti/vibrofer/b.md")
    try vault.write(sampleBoard, to: "01 Progetti/vibrofer/vibrofer.canvas")
    try vault.write("report", to: "01 Progetti/vibrofer/report.pdf")
    try vault.write(header, to: "01 Progetti/vibrofer/sub1/c.md")
    try vault.write(header, to: "01 Progetti/vibrofer/sub2/d.md")

    let counts = vault.operations.contentCounts(at: "01 Progetti/vibrofer")

    #expect(counts.notes == 4)
    #expect(counts.subfolders == 2)
}

@Test func contentCountsSkipsDotDirectoriesAndTheirDescendants() throws {
    let vault = try FolderOpsVault()
    try vault.write(header, to: "01 Progetti/vibrofer/a.md")
    try vault.write(header, to: "01 Progetti/vibrofer/.trash/nascosta.md")

    let counts = vault.operations.contentCounts(at: "01 Progetti/vibrofer")

    #expect(counts.notes == 1)
    #expect(counts.subfolders == 0)
}

// MARK: - Task 2: the rename plan, computed off disk (R-06, R-07, R-13)

@Test func renamePlanComputesTheSiblingDestinationPath() throws {
    let vault = try FolderOpsVault()
    try vault.createDirectory("01 Progetti/vecchio")

    let plan = try vault.operations.renamePlan("01 Progetti/vecchio", to: "nuovo", knownPaths: [])

    #expect(plan.newPath == "01 Progetti/nuovo")
}

@Test func renamePlanThrowsForANonConformantNewName() throws {
    let vault = try FolderOpsVault()
    try vault.createDirectory("01 Progetti/vecchio")

    #expect(throws: FileOperationError.self) {
        try vault.operations.renamePlan("01 Progetti/vecchio", to: "nuovo/con slash", knownPaths: [])
    }
}

@Test func renamePlanThrowsWhenTheDestinationAlreadyExists() throws {
    let vault = try FolderOpsVault()
    try vault.createDirectory("01 Progetti/vecchio")
    try vault.createDirectory("01 Progetti/nuovo")

    #expect(throws: FileOperationError.self) {
        try vault.operations.renamePlan("01 Progetti/vecchio", to: "nuovo", knownPaths: [])
    }
}

@Test func renamePlanThrowsWhenTheSourceFolderDoesNotExist() throws {
    let vault = try FolderOpsVault()

    #expect(throws: FileOperationError.self) {
        try vault.operations.renamePlan("01 Progetti/mai-esistita", to: "nuovo", knownPaths: [])
    }
}

// The regression that pins the SPEC correction (ADR-0022 F3, D2): a wikilink names a
// note by title, not by path, so a folder rename rewrites no ordinary `[[Nota]]` link -
// whatever SPEC R-06's wording says. Do not "fix" this test to expect a rewrite.
@Test func regressionAnOrdinaryWikilinkToANoteInsideTheRenamedFolderProducesNoFileChange() throws {
    let vault = try FolderOpsVault()
    try vault.write(header, to: "01 Progetti/vecchio/Nota interna.md")
    try vault.write(header + "Vedi [[Nota interna]].", to: "Altra.md")

    let plan = try vault.operations.renamePlan(
        "01 Progetti/vecchio", to: "nuovo",
        knownPaths: ["01 Progetti/vecchio/Nota interna.md", "Altra.md"]
    )

    #expect(plan.noteChanges.isEmpty)
}

@Test func renamePlanRepointsCanvasNodesByPrefixIncludingABoardOutsideTheRenamedFolder() throws {
    let vault = try FolderOpsVault()
    try vault.createDirectory("01 Progetti/vecchio")
    let rootBoard = """
    {"nodes":[\
    {"id":"a","type":"file","file":"01 Progetti/vecchio/Nota.md","x":0,"y":0,"width":260,"height":180},\
    {"id":"b","type":"file","file":"01 Progetti/vecchio-altro/x.md","x":300,"y":0,"width":260,"height":180}\
    ],"edges":[]}
    """
    try vault.write(rootBoard, to: "Labs.canvas")

    let plan = try vault.operations.renamePlan("01 Progetti/vecchio", to: "nuovo", knownPaths: [])

    let change = try #require(plan.boardChanges.first { $0.path == "Labs.canvas" })
    #expect(change.after.contains("01 Progetti/nuovo/Nota.md"))
    // Prefix match must be on "<old>/", not on "<old>": a sibling folder that merely
    // starts with the same characters must not be touched.
    #expect(change.after.contains("01 Progetti/vecchio-altro/x.md"))
}

@Test func renamePlanRepointsAFolderCardThatPointsAtTheRenamedFolderItselfNotJustAFileInsideIt() throws {
    let vault = try FolderOpsVault()
    try vault.createDirectory("01 Progetti/vecchio")
    // A "Cartella" tool card (WorkspaceController.createFolder) points at the folder's
    // own path with no trailing component - the same shape `path == oldFolder`, distinct
    // from the file-inside-folder shape the prefix test above covers.
    let rootBoard = """
    {"nodes":[\
    {"id":"a","type":"file","file":"01 Progetti/vecchio","x":0,"y":0,"width":260,"height":180}\
    ],"edges":[]}
    """
    try vault.write(rootBoard, to: "Labs.canvas")

    let plan = try vault.operations.renamePlan("01 Progetti/vecchio", to: "nuovo", knownPaths: [])

    let change = try #require(plan.boardChanges.first { $0.path == "Labs.canvas" })
    #expect(change.after.contains("01 Progetti/nuovo"))
    #expect(!change.after.contains("01 Progetti/vecchio"))
}

// MARK: - Task 3: performing it - rename on disk, delete to the Trash (R-05, R-06, R-07, R-11, R-13)

@Test func renameFolderWithNoBoardFileSucceedsAndRewritesNoMarker() throws {
    let vault = try FolderOpsVault()
    try vault.write(header, to: "01 Progetti/vecchio/Nota.md")

    let outcome = try vault.operations.renameFolder(
        at: "01 Progetti/vecchio", to: "nuovo", knownPaths: ["01 Progetti/vecchio/Nota.md"]
    )

    #expect(outcome.newPath == "01 Progetti/nuovo")
    #expect(!exists("01 Progetti/vecchio", in: vault.root))
    #expect(exists("01 Progetti/nuovo/Nota.md", in: vault.root))
    #expect(!exists("01 Progetti/nuovo/nuovo.canvas", in: vault.root))
}

@Test func trashFolderMovesTheDirectoryToTheTrashAndReturnsTheResultingURL() throws {
    let vault = try FolderOpsVault()
    try vault.write(header, to: "01 Progetti/vecchio/Nota.md")

    let result = try vault.operations.trashFolder(at: "01 Progetti/vecchio")

    // `removeItem` could not have produced a resulting URL - this is what proves
    // `trashItem` was used (ADR-0022 §D7).
    let trashURL = try #require(result.url)
    #expect(FileManager.default.fileExists(atPath: trashURL.path(percentEncoded: false)))
    #expect(!exists("01 Progetti/vecchio", in: vault.root))
}

@Test func trashFolderReturnsTheTrashedNotePaths() throws {
    let vault = try FolderOpsVault()
    try vault.write(header, to: "01 Progetti/vecchio/Uno.md")
    try vault.write(header, to: "01 Progetti/vecchio/Due.md")

    let result = try vault.operations.trashFolder(at: "01 Progetti/vecchio")

    #expect(Set(result.trashedNotePaths) == ["01 Progetti/vecchio/Uno.md", "01 Progetti/vecchio/Due.md"])
}

@Test func trashFolderThrowsForAFolderThatIsNotThere() throws {
    let vault = try FolderOpsVault()

    #expect(throws: FileOperationError.self) {
        try vault.operations.trashFolder(at: "01 Progetti/mai-esistita")
    }
}

// MARK: - ADR-0025 Task 7: a folder rename stops touching boards (R-09)
//
// The name-level pass above (board rename, marker rewrite, the ADR-0022 §D4 ambiguity
// guard) is deleted from `FolderFileOperations` in this task's GREEN and relocated to
// `BoardFileOperations` (`Tests/BoardFileOperationsTests.swift`). A folder rename now
// does exactly one thing to boards: the vault-wide `.canvas` node repoint by prefix
// (already pinned above, unchanged).

@Test func renamePlanRewritesNoMarkerAnywhereEvenWhenTheFolderHasAnUnambiguousBoard() throws {
    let vault = try FolderOpsVault()
    try vault.write(sampleBoard, to: "01 Progetti/vecchio/vecchio.canvas")
    try vault.write(header + "- [ ] Fare ^[[vecchio.canvas]]", to: "Attività.md")
    try vault.write(header + "- [ ] Interna ^[[vecchio.canvas]]", to: "01 Progetti/vecchio/Interna.md")

    let plan = try vault.operations.renamePlan(
        "01 Progetti/vecchio", to: "nuovo",
        knownPaths: ["Attività.md", "01 Progetti/vecchio/Interna.md"]
    )

    // A folder rename renames no `.canvas` file, so there is no stale file name for any
    // marker or link to point at - the whole name-level rewrite pass is gone, not just
    // its ambiguous case.
    #expect(plan.noteChanges.isEmpty)
}

@Test func renamePlanProducesNoAmbiguityFailureEvenWhenTheBoardNameIsAmbiguous() throws {
    let vault = try FolderOpsVault()
    try vault.write(sampleBoard, to: "A/x/x.canvas")
    try vault.write(sampleBoard, to: "B/x/x.canvas")
    try vault.write(header + "- [ ] Fare ^[[x.canvas]]", to: "Attività.md")

    let plan = try vault.operations.renamePlan("A/x", to: "y", knownPaths: ["Attività.md"])

    // The relocated guard (ADR-0022 §D4) belongs to board rename now, not folder
    // rename - a folder rename never touches a board's file name, so there is nothing
    // here for it to guard. No failure line about ambiguity is produced by a folder
    // rename at all.
    #expect(plan.failures.isEmpty)
}

@Test func renameFolderLeavesAnUnrelatedCanvasFileBesideItByteIdentical() throws {
    let vault = try FolderOpsVault()
    try vault.createDirectory("01 Progetti/A")
    try vault.write(sampleBoard, to: "01 Progetti/A.canvas")

    let outcome = try vault.operations.renameFolder(
        at: "01 Progetti/A", to: "B", knownPaths: []
    )

    #expect(outcome.newPath == "01 Progetti/B")
    // "01 Progetti/A.canvas" is a *sibling* of the renamed folder, not a file inside
    // it - a coincidence of naming, not a relationship this rename should notice.
    #expect(exists("01 Progetti/A.canvas", in: vault.root))
    #expect(try vault.text(at: "01 Progetti/A.canvas") == sampleBoard)
}

@Test func renameFolderMovesABoardInsideItWithoutRenamingItsFileName() throws {
    let vault = try FolderOpsVault()
    try vault.write(sampleBoard, to: "01 Progetti/A/A.canvas")
    try vault.write(header, to: "01 Progetti/A/Nota.md")

    let outcome = try vault.operations.renameFolder(
        at: "01 Progetti/A", to: "B", knownPaths: ["01 Progetti/A/Nota.md"]
    )

    #expect(outcome.newPath == "01 Progetti/B")
    #expect(!isDirectory("01 Progetti/A", in: vault.root))
    // The board moves with the directory and keeps its own file name - it does not
    // become "B.canvas" just because the folder became "B" (ADR-0025 §D6, R-09).
    #expect(exists("01 Progetti/B/A.canvas", in: vault.root))
    #expect(!exists("01 Progetti/B/B.canvas", in: vault.root))
    #expect(try vault.text(at: "01 Progetti/B/A.canvas") == sampleBoard)
}

@Test func renameFolderMovesTheDirectoryAndRepointsCanvasNodesButRenamesNoBoardAndRewritesNoMarker() throws {
    let vault = try FolderOpsVault()
    let ownBoard = """
    {"nodes":[{"id":"a","type":"file","file":"03 Risorse/Altro.pdf","x":0,"y":0,"width":260,"height":180}],"edges":[]}
    """
    try vault.write(ownBoard, to: "01 Progetti/vecchio/vecchio.canvas")
    try vault.write(header, to: "01 Progetti/vecchio/Nota.md")
    try vault.write(header + "- [ ] Fare ^[[vecchio.canvas]]", to: "Attività.md")
    let rootBoard = """
    {"nodes":[{"id":"b","type":"file","file":"01 Progetti/vecchio/Nota.md","x":0,"y":0,"width":260,"height":180}],"edges":[]}
    """
    try vault.write(rootBoard, to: "Labs.canvas")

    let outcome = try vault.operations.renameFolder(
        at: "01 Progetti/vecchio", to: "nuovo",
        knownPaths: ["01 Progetti/vecchio/Nota.md", "Attività.md"]
    )

    #expect(outcome.newPath == "01 Progetti/nuovo")
    #expect(outcome.failures.isEmpty)
    #expect(!isDirectory("01 Progetti/vecchio", in: vault.root))
    #expect(exists("01 Progetti/nuovo/Nota.md", in: vault.root))

    // The board moved with the directory and kept its own name - a folder rename
    // renames no `.canvas` file any more (ADR-0025 §D6, R-09).
    #expect(exists("01 Progetti/nuovo/vecchio.canvas", in: vault.root))
    #expect(!exists("01 Progetti/nuovo/nuovo.canvas", in: vault.root))
    #expect(try vault.text(at: "01 Progetti/nuovo/vecchio.canvas") == ownBoard)

    // No marker rewrite: the board's file name did not change, so nothing points at a
    // stale name that needs fixing.
    #expect(try vault.text(at: "Attività.md").contains("^[[vecchio.canvas]]"))

    // The vault-wide node repoint by prefix is unchanged (ADR-0022 §D2.1).
    #expect(try vault.text(at: "Labs.canvas").contains("01 Progetti/nuovo/Nota.md"))

    #expect(outcome.movedNotes.contains {
        $0.old == "01 Progetti/vecchio/Nota.md" && $0.new == "01 Progetti/nuovo/Nota.md"
    })
}

// MARK: - ADR-0026: A folder moves with everything inside it (R-02, R-05, R-06, R-07, §D7)

@Test func moveFolderMovesEverythingInsideItAndReportsMovedNotesAndRepointsCardsByPrefix() throws {
    let vault = try FolderOpsVault()
    try vault.write(header, to: "A/n.md")
    try vault.write(sampleBoard, to: "A/x.canvas")
    try vault.write(sampleBoard, to: "A/sub/y.canvas")
    let labsBoard = """
    {"nodes":[\
    {"id":"a","type":"file","file":"A/n.md","x":0,"y":0,"width":260,"height":180},\
    {"id":"b","type":"file","file":"A/sub/y.canvas","x":300,"y":0,"width":260,"height":180}\
    ],"edges":[]}
    """
    try vault.write(labsBoard, to: "Labs.canvas")

    let outcome = try vault.operations.moveFolder(at: "A", toParent: "B")

    #expect(outcome.newPath == "B/A")
    #expect(!isDirectory("A", in: vault.root))
    #expect(exists("B/A/n.md", in: vault.root))
    #expect(exists("B/A/x.canvas", in: vault.root))
    #expect(exists("B/A/sub/y.canvas", in: vault.root))
    #expect(outcome.movedNotes.count == 1)
    #expect(outcome.movedNotes.contains { $0.old == "A/n.md" && $0.new == "B/A/n.md" })

    // Both cards repointed by prefix: the one naming a note inside the moved folder and
    // the one naming a board inside a subfolder of it (R-02).
    let labsText = try vault.text(at: "Labs.canvas")
    #expect(labsText.contains("B/A/n.md"))
    #expect(labsText.contains("B/A/sub/y.canvas"))
}

@Test func moveFolderRepointsABoardInsideItThatIsItselfACardOnAnotherBoardAndWritesAtItsNewPath() throws {
    let vault = try FolderOpsVault()
    try vault.write(header, to: "A/n.md")
    // "A/x.canvas" is itself a board *inside* the moved folder, and it holds a card
    // pointing at another file inside the same folder - so its own content must be
    // rewritten, and rewritten at its NEW path ("B/A/x.canvas"), because by the time
    // this change is written the folder move has already carried it there and nothing
    // is left at "A/x.canvas" to write to (`repointBoardsPlan`'s `writePath`, ADR-0026 §D7).
    let innerBoard = """
    {"nodes":[{"id":"a","type":"file","file":"A/n.md","x":0,"y":0,"width":260,"height":180}],"edges":[]}
    """
    try vault.write(innerBoard, to: "A/x.canvas")

    let outcome = try vault.operations.moveFolder(at: "A", toParent: "B")

    #expect(outcome.newPath == "B/A")
    #expect(!exists("A/x.canvas", in: vault.root))
    #expect(exists("B/A/x.canvas", in: vault.root))
    let rewritten = try vault.text(at: "B/A/x.canvas")
    #expect(rewritten.contains("B/A/n.md"))
    #expect(!rewritten.contains("\"A/n.md\""))
    #expect(outcome.rewrittenPaths.contains("B/A/x.canvas"))
}

@Test func moveFolderThrowsAlreadyExistsForACollisionAndWritesNothing() throws {
    let vault = try FolderOpsVault()
    try vault.write(header, to: "A/n.md")
    try vault.createDirectory("B/A")

    do {
        _ = try vault.operations.moveFolder(at: "A", toParent: "B")
        Issue.record("expected moveFolder to throw for a name collision at the destination")
    } catch FileOperationError.alreadyExists(let path) {
        #expect(path.contains("A"))
    } catch {
        Issue.record("expected FileOperationError.alreadyExists, got \(error)")
    }
    #expect(isDirectory("A", in: vault.root))
    #expect(exists("A/n.md", in: vault.root))
}

@Test func moveFolderIntoItselfThrowsWouldNest() throws {
    let vault = try FolderOpsVault()
    try vault.createDirectory("A")

    do {
        _ = try vault.operations.moveFolder(at: "A", toParent: "A")
        Issue.record("expected moveFolder to throw for a destination that is the folder itself")
    } catch FileOperationError.wouldNest(let path) {
        #expect(path.contains("A"))
    } catch {
        Issue.record("expected FileOperationError.wouldNest, got \(error)")
    }
    #expect(isDirectory("A", in: vault.root))
}

@Test func moveFolderIntoItsOwnDescendantThrowsWouldNest() throws {
    let vault = try FolderOpsVault()
    try vault.createDirectory("A/sub")

    do {
        _ = try vault.operations.moveFolder(at: "A", toParent: "A/sub")
        Issue.record("expected moveFolder to throw for a destination that is a descendant")
    } catch FileOperationError.wouldNest(let path) {
        #expect(path.contains("A"))
    } catch {
        Issue.record("expected FileOperationError.wouldNest, got \(error)")
    }
    #expect(isDirectory("A", in: vault.root))
    #expect(isDirectory("A/sub", in: vault.root))
}

@Test func moveFolderToItsCurrentParentIsANoOpAndWritesNothing() throws {
    let vault = try FolderOpsVault()
    try vault.write(header, to: "01 Progetti/A/n.md")

    let outcome = try vault.operations.moveFolder(at: "01 Progetti/A", toParent: "01 Progetti")

    #expect(outcome.newPath == "01 Progetti/A")
    #expect(isDirectory("01 Progetti/A", in: vault.root))
    #expect(exists("01 Progetti/A/n.md", in: vault.root))
}

@Test func moveFolderToTheVaultRootWorks() throws {
    let vault = try FolderOpsVault()
    try vault.write(header, to: "01 Progetti/A/n.md")

    let outcome = try vault.operations.moveFolder(at: "01 Progetti/A", toParent: "")

    #expect(outcome.newPath == "A")
    #expect(!isDirectory("01 Progetti/A", in: vault.root))
    #expect(isDirectory("A", in: vault.root))
    #expect(exists("A/n.md", in: vault.root))
}

@Test func folderMovePlanWritesNothing() throws {
    let vault = try FolderOpsVault()
    try vault.write(header, to: "A/n.md")

    _ = try vault.operations.movePlan("A", toParent: "B")

    #expect(isDirectory("A", in: vault.root))
    #expect(!isDirectory("B/A", in: vault.root))
}
