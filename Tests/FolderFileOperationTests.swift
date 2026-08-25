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

    #expect(throws: FolderFileOperations.OperationError.self) {
        try vault.operations.renamePlan("01 Progetti/vecchio", to: "nuovo/con slash", knownPaths: [])
    }
}

@Test func renamePlanThrowsWhenTheDestinationAlreadyExists() throws {
    let vault = try FolderOpsVault()
    try vault.createDirectory("01 Progetti/vecchio")
    try vault.createDirectory("01 Progetti/nuovo")

    #expect(throws: FolderFileOperations.OperationError.self) {
        try vault.operations.renamePlan("01 Progetti/vecchio", to: "nuovo", knownPaths: [])
    }
}

@Test func renamePlanThrowsWhenTheSourceFolderDoesNotExist() throws {
    let vault = try FolderOpsVault()

    #expect(throws: FolderFileOperations.OperationError.self) {
        try vault.operations.renamePlan("01 Progetti/mai-esistita", to: "nuovo", knownPaths: [])
    }
}

@Test func renamePlanCarriesTheBoardRenameAtPostMovePathsWhenABoardExists() throws {
    let vault = try FolderOpsVault()
    try vault.write(sampleBoard, to: "01 Progetti/vecchio/vecchio.canvas")

    let plan = try vault.operations.renamePlan("01 Progetti/vecchio", to: "nuovo", knownPaths: [])

    #expect(plan.boardRename?.from == "01 Progetti/nuovo/vecchio.canvas")
    #expect(plan.boardRename?.to == "01 Progetti/nuovo/nuovo.canvas")
}

@Test func renamePlanCarriesNoBoardRenameWhenTheFolderHasNoBoard() throws {
    let vault = try FolderOpsVault()
    try vault.write(header, to: "01 Progetti/vecchio/Nota.md")

    let plan = try vault.operations.renamePlan(
        "01 Progetti/vecchio", to: "nuovo", knownPaths: ["01 Progetti/vecchio/Nota.md"]
    )

    #expect(plan.boardRename == nil)
}

@Test func renamePlanRewritesTheTaskMarkerAndThePlainLinkToTheBoardFileName() throws {
    let vault = try FolderOpsVault()
    try vault.write(sampleBoard, to: "01 Progetti/vecchio/vecchio.canvas")
    try vault.write(header + "- [ ] Fare ^[[vecchio.canvas]]", to: "Attività.md")
    try vault.write(header + "Vedi [[vecchio.canvas]].", to: "Altra.md")

    let plan = try vault.operations.renamePlan(
        "01 Progetti/vecchio", to: "nuovo", knownPaths: ["Attività.md", "Altra.md"]
    )

    let taskChange = try #require(plan.noteChanges.first { $0.path == "Attività.md" })
    #expect(taskChange.after.contains("^[[nuovo.canvas]]"))

    let linkChange = try #require(plan.noteChanges.first { $0.path == "Altra.md" })
    #expect(linkChange.after.contains("[[nuovo.canvas]]"))
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

@Test func renamePlanUsesThePostMovePathForANoteThatLivesInsideTheRenamedFolder() throws {
    let vault = try FolderOpsVault()
    try vault.write(sampleBoard, to: "01 Progetti/vecchio/vecchio.canvas")
    try vault.write(header + "- [ ] Fare ^[[vecchio.canvas]]", to: "01 Progetti/vecchio/Interna.md")

    let plan = try vault.operations.renamePlan(
        "01 Progetti/vecchio", to: "nuovo", knownPaths: ["01 Progetti/vecchio/Interna.md"]
    )

    let change = try #require(plan.noteChanges.first)
    #expect(change.path == "01 Progetti/nuovo/Interna.md")
    #expect(change.after.contains("^[[nuovo.canvas]]"))
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

@Test func renamePlanSkipsTheMarkerRewriteAndReportsAFailureWhenTheBoardNameIsAmbiguous() throws {
    let vault = try FolderOpsVault()
    try vault.write(sampleBoard, to: "A/x/x.canvas")
    try vault.write(sampleBoard, to: "B/x/x.canvas")
    try vault.write(header + "- [ ] Fare ^[[x.canvas]]", to: "Attività.md")
    let rootBoard = """
    {"nodes":[{"id":"a","type":"file","file":"A/x/Nota.md","x":0,"y":0,"width":260,"height":180}],"edges":[]}
    """
    try vault.write(rootBoard, to: "Labs.canvas")

    let plan = try vault.operations.renamePlan("A/x", to: "y", knownPaths: ["Attività.md"])

    #expect(plan.noteChanges.isEmpty)
    #expect(plan.failures.contains { $0.contains("x.canvas") })
    // The path-level repoint is unambiguous by construction and still runs.
    #expect(plan.boardChanges.contains { $0.path == "Labs.canvas" })
}

// MARK: - Task 3: performing it - rename on disk, delete to the Trash (R-05, R-06, R-07, R-11, R-13)

@Test func renameFolderMovesRenamesTheBoardAndRewritesEverythingPlanned() throws {
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
    #expect(exists("01 Progetti/nuovo/nuovo.canvas", in: vault.root))
    #expect(exists("01 Progetti/nuovo/Nota.md", in: vault.root))

    // The old board's nodes survived the move-and-rename, decoded and re-encoded.
    let newBoardText = try vault.text(at: "01 Progetti/nuovo/nuovo.canvas")
    #expect(newBoardText.contains("03 Risorse/Altro.pdf"))

    #expect(try vault.text(at: "Attività.md").contains("^[[nuovo.canvas]]"))
    #expect(try vault.text(at: "Labs.canvas").contains("01 Progetti/nuovo/Nota.md"))

    #expect(outcome.movedNotes.contains {
        $0.old == "01 Progetti/vecchio/Nota.md" && $0.new == "01 Progetti/nuovo/Nota.md"
    })
}

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

    #expect(throws: FolderFileOperations.OperationError.self) {
        try vault.operations.trashFolder(at: "01 Progetti/mai-esistita")
    }
}
