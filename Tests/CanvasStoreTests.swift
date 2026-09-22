import Foundation
import Testing
@testable import Pergamenum

// `CanvasStore` path-addressing and `allBoards()` tests (PG-088 — pure code motion
// off `CanvasTests.swift`, which had drifted past `file_length`'s error threshold).
// MARK: - `CanvasStore` path-addressing API (ADR-0025 §D1, "A folder is a container, a
// board is a file, and neither is named after the other").
// Plan `docs/superpowers/plans/2026-08-27-workspace-folder-board-separation.md`, Task 1.
//
// `CanvasStore` is told a board's own path: `url(forBoard:)`, `load(board:)`,
// `save(_:board:)`, `contents(ofBoard:document:)`, `createBoard(named:in:)`,
// `boardNameIsAvailable(_:in:)`, `allFolders()` and `StoreError.missing(String)`. The
// folder-derived API these replace - `boardPath(forFolder:)`, `url(forFolder:)`,
// `load(folder:)`, `save(_:folder:)`, `contents(ofFolder:board:)` - is deleted, not
// deprecated: a rule that still exists is a rule a caller can still ask, and the failure
// it produces is a board that opens the wrong file, silently.

@Test func loadingAMissingBoardThrowsRatherThanReturningEmpty() throws {
    let root = try CanvasTemporaryRoot()
    let store = CanvasStore(root: root.url)

    do {
        _ = try store.load(board: "01 Progetti/assente.canvas")
        Issue.record("expected load(board:) to throw for a file that does not exist")
    } catch CanvasStore.StoreError.missing(let path) {
        #expect(path == "01 Progetti/assente.canvas")
    } catch {
        Issue.record("expected StoreError.missing, got \(error)")
    }
}

@Test func loadRoundTripsADocumentSavedAtAnArbitraryBoardPath() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("A")
    let store = CanvasStore(root: root.url)
    var board = CanvasDocument()
    board.nodes.append(CanvasNode(id: "a", kind: .text("ciao"), x: 10, y: 20, width: 200, height: 100))

    // The board's name carries no relationship to its folder's name (R-06) - the shape
    // this addressing model exists for.
    try store.save(board, board: "A/qualsiasi-nome.canvas")
    do {
        let reloaded = try store.load(board: "A/qualsiasi-nome.canvas")
        #expect(reloaded == board)
    } catch {
        Issue.record("expected load(board:) to round-trip what save(_:board:) just wrote, got \(error)")
    }
}

@Test func createBoardWritesAnEmptyCanvasAtTheChosenNameAndRefusesADuplicate() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("A")
    let store = CanvasStore(root: root.url)

    let path = try store.createBoard(named: "qualsiasi-nome", in: "A")
    #expect(path == "A/qualsiasi-nome.canvas")

    let fileURL = root.url.appending(path: "A/qualsiasi-nome.canvas", directoryHint: .notDirectory)
    #expect(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    if let data = try? Data(contentsOf: fileURL) {
        let written = try CanvasDocument(data: data)
        #expect(written == .empty)
    } else {
        Issue.record("expected createBoard to write an empty .canvas at \(fileURL.path(percentEncoded: false))")
    }

    // createBoard writes the file directly; it does not create a folder named after
    // the board (R-02's "does not create or require a same-named folder").
    let existsAtBareName = FileManager.default.fileExists(
        atPath: root.url.appending(path: "A/qualsiasi-nome").path(percentEncoded: false)
    )
    #expect(!existsAtBareName)

    do {
        _ = try store.createBoard(named: "qualsiasi-nome", in: "A")
        Issue.record("expected createBoard to refuse a name a .canvas in that folder already has")
    } catch CanvasStore.StoreError.alreadyExists(let existing) {
        #expect(existing.hasSuffix("qualsiasi-nome.canvas"))
    } catch {
        Issue.record("expected StoreError.alreadyExists, got \(error)")
    }
}

@Test func createBoardSucceedsBesideALikeNamedFolder() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("prova")
    let store = CanvasStore(root: root.url)

    // A folder and a sibling `.canvas` may share a name in the same parent (R-04) -
    // the pre-existing `prova/prova.canvas` shape, generalised to the vault root.
    let path = try store.createBoard(named: "prova", in: "")
    #expect(path == "prova.canvas")

    var isDirectory: ObjCBool = false
    let folderExists = FileManager.default.fileExists(
        atPath: root.url.appending(path: "prova").path(percentEncoded: false), isDirectory: &isDirectory
    )
    #expect(folderExists)
    #expect(isDirectory.boolValue)

    let boardExists = FileManager.default.fileExists(
        atPath: root.url.appending(path: "prova.canvas").path(percentEncoded: false)
    )
    #expect(boardExists)
}

@Test func boardNameIsAvailableAgreesWithCreateBoardWithoutWriting() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("A")
    let store = CanvasStore(root: root.url)
    _ = try store.createBoard(named: "occupato", in: "A")

    #expect(store.boardNameIsAvailable("occupato", in: "A") == false)
    #expect(store.boardNameIsAvailable("libero", in: "A") == true)

    // Checked live, without writing (the same relationship `FolderFileOperations
    // .nameIsAvailable` has to `createFolder`, ADR-0022 §D11): asking must not create
    // a file.
    #expect(!FileManager.default.fileExists(
        atPath: root.url.appending(path: "A/libero.canvas").path(percentEncoded: false)
    ))
}

@Test func allFoldersListsEveryDirectoryExcludingReservedOnesAndIncludingEmptyOnes() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("01 Progetti/vibrofer-emea")
    try root.makeDirectory("Vuota")
    try root.makeFile(".obsidian/config.json")
    try root.makeFile(".git/HEAD")
    try root.makeFile(".trash/nota.md")
    try root.makeFile(".pergamenum/state.json")
    let store = CanvasStore(root: root.url)

    let folders = store.allFolders()
    #expect(folders.contains("01 Progetti"))
    #expect(folders.contains("01 Progetti/vibrofer-emea"))
    // "Vuota" holds no `.canvas` at all - the assertion that proves the tree is not
    // built from `allBoards()` alone (R-10's precondition, checked here at the store
    // level).
    #expect(folders.contains("Vuota"))
    #expect(!folders.contains(".obsidian"))
    #expect(!folders.contains(".git"))
    #expect(!folders.contains(".trash"))
    #expect(!folders.contains(".pergamenum"))
    #expect(!folders.contains(where: { $0.hasPrefix(".obsidian/") }))
}

@Test func contentsOfBoardDerivesTheContainingFolderAndListsItsEntries() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("A/sotto")
    try root.makeFile("A/nota.md")
    try root.makeFile("A/uno.canvas")
    let store = CanvasStore(root: root.url)

    // A dropped file still lands beside the open board, in its containing folder (R-06).
    let contents = store.contents(ofBoard: "A/uno.canvas", document: .empty)
    #expect(contents.subfolders == ["A/sotto"])
    #expect(contents.unplaced.contains("A/nota.md"))
}

@Test func contentsOfBoardExcludesEveryCanvasFileNotOnlyTheOpenOne() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("A")
    try root.makeFile("A/uno.canvas")
    try root.makeFile("A/due.canvas")
    try root.makeFile("A/nota.md")
    let store = CanvasStore(root: root.url)

    let contents = store.contents(ofBoard: "A/uno.canvas", document: .empty)
    // A real, non-canvas entry proves the exclusion below is meaningful and not a
    // vacuously empty result.
    #expect(contents.unplaced.contains("A/nota.md"))
    // ADR-0025 §D10: the tray shows unplaced items, not a board switcher. Neither the
    // open board's own file nor a sibling `.canvas` belongs in `unplaced` (R-07) -
    // assert the sibling explicitly, since it already reaches the tray today (F5).
    #expect(!contents.unplaced.contains("A/uno.canvas"))
    #expect(!contents.unplaced.contains("A/due.canvas"))
}

@Test func createFolderStillCreatesADirectoryAndNoBoard() throws {
    let root = try CanvasTemporaryRoot()
    let store = CanvasStore(root: root.url)

    let path = try store.createFolder(named: "Nuova", in: "")
    #expect(path == "Nuova")

    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(
        atPath: root.url.appending(path: path).path(percentEncoded: false), isDirectory: &isDirectory
    )
    #expect(exists)
    #expect(isDirectory.boolValue)

    // R-01's store half: creating a folder must not implicitly write a same-named
    // board (the view half - deleting `WorkspaceView+FolderVerbs.swift`'s implicit
    // `save(.empty, folder:)` call - is Task 6).
    #expect(!FileManager.default.fileExists(
        atPath: root.url.appending(path: "Nuova.canvas").path(percentEncoded: false)
    ))
    #expect(!FileManager.default.fileExists(
        atPath: root.url.appending(path: "Nuova/Nuova.canvas").path(percentEncoded: false)
    ))
}

@Test func generatesIdsInTheShapeObsidianWrites() {
    let id = CanvasID.generate()
    #expect(id.count == 16)
    // Hoisted: `allSatisfy` is rethrows, and inside #expect's autoclosure the
    // compiler stops inferring that a key-path predicate cannot throw.
    let isHexadecimal = id.allSatisfy(\.isHexDigit)
    #expect(isHexadecimal)
    #expect(CanvasID.generate() != id)
}

// MARK: - `CanvasStore.allBoards()` (ADR-0021 "A task carries its Workspace and its place in a
// project as caret markers in its own line, and nothing new is stored anywhere else", §D10, R-01).
// Plan `docs/superpowers/plans/2026-08-24-workspace-tasks-notes-integration.md`, Task 6: the
// Workspace folder browser. D10 rejects putting `.canvas` files into `IndexSnapshot` (a version
// bump and a change to what every consumer of "a note" means) and enumerates them on demand
// instead, walking the vault the same way `VaultScanner.scan()` does and skipping the same
// excluded directories through `VaultLayout.isExcludedDirectory`.
//
// `CanvasStore.allBoards()` is a signature-only stub returning `[]` as of this commit: every
// test below is expected to fail red on its assertions, not to fail to compile.

@Test func allBoardsFindsNestedCanvasFilesAsSortedVaultRelativePaths() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeFile("root.canvas")
    try root.makeFile("01 Progetti/vibrofer-emea/vibrofer-emea.canvas")
    try root.makeFile("02 Aree/area.canvas")
    let store = CanvasStore(root: root.url)

    #expect(store.allBoards() == [
        "01 Progetti/vibrofer-emea/vibrofer-emea.canvas",
        "02 Aree/area.canvas",
        "root.canvas",
    ])
}

@Test func allBoardsSkipsExcludedDirectories() throws {
    // Mirrors `VaultLayout.isExcludedDirectory`'s own dot-prefix rule (`.obsidian`, `.git`,
    // `.pergamenum` and any other dot-directory), the same rule `VaultScanner.scan()` applies
    // to notes.
    let root = try CanvasTemporaryRoot()
    try root.makeFile(".obsidian/hidden.canvas")
    try root.makeFile(".git/hidden.canvas")
    try root.makeFile(".pergamenum/hidden.canvas")
    try root.makeFile(".trash/hidden.canvas")
    try root.makeFile("01 Progetti/visibile.canvas")
    let store = CanvasStore(root: root.url)

    #expect(store.allBoards() == ["01 Progetti/visibile.canvas"])
}

@Test func allBoardsIgnoresEverythingThatIsNotACanvasFile() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeFile("Nota.md")
    try root.makeFile("documento.pdf")
    try root.makeFile("immagine.png")
    try root.makeFile("01 Progetti/altra nota.md")
    let store = CanvasStore(root: root.url)

    #expect(store.allBoards().isEmpty)
}

@Test func allBoardsReturnsEmptyForAVaultWithNoBoards() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("01 Progetti")
    try root.makeFile("01 Progetti/nota.md")
    let store = CanvasStore(root: root.url)

    #expect(store.allBoards() == [])
}

// MARK: - `read(board:)`, guarded `save(_:board:expecting:)` and `writeRepoint` (ADR-0054
// §D2/§D3/§D6, plan `docs/plans/pg-213-workspace-autosave-race.md`, Task 2, R-01, R-03, R-07)

@Test func readsHashEqualsNoteStoreHashAndRoundTripsThroughSavesReturnValue() throws {
    let root = try CanvasTemporaryRoot()
    let store = CanvasStore(root: root.url)
    var document = CanvasDocument()
    document.nodes.append(CanvasNode(id: "a", kind: .text("ciao"), x: 0, y: 0, width: 10, height: 10))

    let savedHash = try store.save(document, board: "A.canvas")
    let read = try store.read(board: "A.canvas")

    #expect(read.hash == savedHash)
    let onDisk = try Data(contentsOf: root.url.appending(path: "A.canvas"))
    #expect(read.hash == NoteStore.hash(onDisk))
    #expect(read.document == document)
}

@Test func saveExpectingAMatchingHashWrites() throws {
    let root = try CanvasTemporaryRoot()
    let store = CanvasStore(root: root.url)
    let hash = try store.save(.empty, board: "A.canvas")

    var updated = CanvasDocument()
    updated.nodes.append(CanvasNode(id: "a", kind: .text("nuovo"), x: 0, y: 0, width: 10, height: 10))
    _ = try store.save(updated, board: "A.canvas", expecting: hash)

    #expect(try store.load(board: "A.canvas") == updated)
}

@Test func saveExpectingAStaleHashThrowsAndLeavesTheFileByteIdentical() throws {
    let root = try CanvasTemporaryRoot()
    let store = CanvasStore(root: root.url)
    _ = try store.save(.empty, board: "A.canvas")
    // Somebody else writes in between.
    _ = try store.save(.empty, board: "A.canvas")
    let onDiskBefore = try Data(contentsOf: root.url.appending(path: "A.canvas"))

    var updated = CanvasDocument()
    updated.nodes.append(CanvasNode(id: "a", kind: .text("scartato"), x: 0, y: 0, width: 10, height: 10))
    do {
        _ = try store.save(updated, board: "A.canvas", expecting: "stale-hash")
        Issue.record("expected save(expecting:) to refuse a stale hash")
    } catch VaultWriteRefusal.movedOn(let path) {
        #expect(path == "A.canvas")
    } catch {
        Issue.record("expected VaultWriteRefusal.movedOn, got \(error)")
    }
    let onDiskAfter = try Data(contentsOf: root.url.appending(path: "A.canvas"))
    #expect(onDiskBefore == onDiskAfter)
}

@Test func saveExpectingNilWritesUnconditionallyOverChangedBytes() throws {
    let root = try CanvasTemporaryRoot()
    let store = CanvasStore(root: root.url)
    _ = try store.save(.empty, board: "A.canvas")

    var updated = CanvasDocument()
    updated.nodes.append(CanvasNode(id: "a", kind: .text("sopra"), x: 0, y: 0, width: 10, height: 10))
    _ = try store.save(updated, board: "A.canvas")

    #expect(try store.load(board: "A.canvas") == updated)
}

@Test func saveExpectingAgainstAMissingBoardRefusesRatherThanRecreatingIt() throws {
    let root = try CanvasTemporaryRoot()
    let store = CanvasStore(root: root.url)

    do {
        _ = try store.save(.empty, board: "assente.canvas", expecting: "anything")
        Issue.record("expected save(expecting:) to refuse a board that does not exist")
    } catch VaultWriteRefusal.movedOn(let path) {
        #expect(path == "assente.canvas")
    } catch {
        Issue.record("expected VaultWriteRefusal.movedOn, got \(error)")
    }
    #expect(!FileManager.default.fileExists(
        atPath: root.url.appending(path: "assente.canvas").path(percentEncoded: false)
    ))
}

@Test func writeRepointWritesOnAFreshChangeAndRefusesOnAStaleOne() throws {
    let root = try CanvasTemporaryRoot()
    let store = CanvasStore(root: root.url)
    let before = try CanvasDocument.empty.encoded()
    _ = try store.save(.empty, board: "A.canvas")
    let beforeText = String(decoding: before, as: UTF8.self)

    var repointed = CanvasDocument()
    repointed.nodes.append(CanvasNode(id: "a", kind: .file(path: "new.md", subpath: nil), x: 0, y: 0, width: 10, height: 10))
    let after = String(decoding: try repointed.encoded(), as: UTF8.self)

    try store.writeRepoint(VaultFileChange(path: "A.canvas", before: beforeText, after: after))
    #expect(try store.load(board: "A.canvas") == repointed)

    // A second repoint against the same (now stale) `before` refuses.
    var secondRepoint = CanvasDocument()
    secondRepoint.nodes.append(CanvasNode(id: "b", kind: .file(path: "other.md", subpath: nil), x: 0, y: 0, width: 10, height: 10))
    do {
        try store.writeRepoint(VaultFileChange(
            path: "A.canvas", before: beforeText, after: String(decoding: try secondRepoint.encoded(), as: UTF8.self)
        ))
        Issue.record("expected writeRepoint to refuse a stale before")
    } catch VaultWriteRefusal.movedOn(let path) {
        #expect(path == "A.canvas")
    } catch {
        Issue.record("expected VaultWriteRefusal.movedOn, got \(error)")
    }
    #expect(try store.load(board: "A.canvas") == repointed, "the refused write must leave the file untouched")
}

@Test func writeRepointRefusesAPathEscapingTheVault() throws {
    let root = try CanvasTemporaryRoot()
    let store = CanvasStore(root: root.url)
    let change = VaultFileChange(path: "../../evil.canvas", before: "{}", after: "{}")

    do {
        try store.writeRepoint(change)
        Issue.record("expected writeRepoint to refuse a path escaping the vault")
    } catch {
        // refusal - either a boundary violation or VaultWriteRefusal is acceptable.
    }
}
