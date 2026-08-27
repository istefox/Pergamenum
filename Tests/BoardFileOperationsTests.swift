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
// `BoardFileOperations.OperationError.notImplementedYet`, so every test below fails on
// its assertions (or on the uncaught throw), not on a missing symbol.

// MARK: - Fixtures and helpers

private struct BoardOpsVault: ~Copyable {
    let root: URL
    let store: NoteStore
    let operations: BoardFileOperations

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-board-ops-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = NoteStore(root: root)
        operations = BoardFileOperations(store: store)
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

    #expect(throws: BoardFileOperations.OperationError.self) {
        try vault.operations.renamePlan("A/vecchio.canvas", to: "nuovo", knownPaths: [])
    }
}

@Test func renameBoardWritesNothingWhenTheDestinationNameIsTaken() throws {
    let vault = try BoardOpsVault()
    try vault.write(sampleBoard, to: "A/vecchio.canvas")
    try vault.write("{\"nodes\":[],\"edges\":[],\"marker\":true}", to: "A/nuovo.canvas")

    #expect(throws: BoardFileOperations.OperationError.self) {
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

    #expect(throws: BoardFileOperations.OperationError.self) {
        try vault.operations.trashBoard(at: "A/mai-esistito.canvas")
    }
}
