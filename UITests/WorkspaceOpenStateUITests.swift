import XCTest

/// The Workspace pane starts empty - nothing highlighted in the board list, no board on
/// screen - until a board is actually clicked, the same way the note editor starts with
/// nothing open rather than with the last note pinned forever.
///
/// ADR-0024 ("One selection, one row, one meaning"). Plan
/// `docs/superpowers/plans/2026-08-25-workspace-board-tree-single-selection.md`, Task 6
/// (R-14): this file is the rewrite that task asks for. Every row is found by
/// `accessibilityIdentifier`, never by the words on it (`CLAUDE.md`) - the tree stopped
/// being a `Button` per row (ADR-0024 §D1/F5), so the two ported tests below substitute
/// `app.descendants(matching: .any).matching(identifier:)` for the old `app.buttons[...]`
/// lookup, and every new test follows the same rule from the start. No assertion in this
/// file reads `selectedFolder` or `hasOpenBoard` - both were removed from the production
/// code this plan's earlier tasks replaced (ADR-0024 §D4/§D6) and neither is a concept a
/// UI test, which only ever sees rendered rows and labels, could reach even by accident.
final class WorkspaceOpenStateUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var app: XCUIApplication!

    // MARK: Fixture identity, named once so every step and every assertion agrees.

    /// A folder with its own board, directly under the root - the R-01 target: one row,
    /// not two.
    private let boardFolder = "Vibrofer"
    private let boardFile = "Vibrofer/Vibrofer.canvas"
    /// A board nested two levels deep, inside the folder above - the R-02/R-03 target:
    /// selecting it must light exactly its own row, nowhere else in the tree.
    private let nestedBoardFile = "Vibrofer/Dettaglio/Dettaglio.canvas"
    /// A board-less grouping folder whose only content is a subfolder that owns a board
    /// (SPEC Decision 3 / ADR-0024 §D5) - the R-04/R-05 target: its row selects and opens
    /// nothing.
    private let groupingFolder = "Progetti"
    private let groupingChildBoardFile = "Progetti/Cliente/Cliente.canvas"

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory())
            .appending(path: "WorkspaceOpenStateUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try makeFixtureBoards()

        app = XCUIApplication()
        stateBase = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES",
                               "-stateBase", stateBase.path(percentEncoded: false)]
        app.launch()
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
        app.staticTexts["Workspace"].click()
        XCTAssertTrue(app.textFields["workspace-filter"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
    }

    // MARK: Row lookup - every one by identifier, never by the words on it (CLAUDE.md).

    /// The root board's row: named after the vault, exactly as `CanvasStore
    /// .boardPath(forFolder:)` maps an empty folder (SPEC §6.1 - "the root board is named
    /// after the vault").
    private var rootBoardRow: XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "workspace-board-\(vault.lastPathComponent).canvas").firstMatch
    }

    private func row(identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var tree: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "workspace-tree").firstMatch
    }

    /// The rows in `workspace-tree` currently reporting the selected state, counted by
    /// the accessibility-label suffix ADR-0024 §D9 adds (`", aperta"` for an open board,
    /// `", selezionata"` for a selected board-less folder) - not by `isSelected`, per the
    /// plan's SPEC-claims table note on R-13: whether `.accessibilityAddTraits(.isSelected)`
    /// on custom `List` row content reaches XCUITest's trait on macOS is unverified here,
    /// so the label is the one thing an assertion may depend on.
    private var selectedRowsInTree: XCUIElementQuery {
        tree.descendants(matching: .any).matching(
            NSPredicate(format: "label ENDSWITH ', aperta' OR label ENDSWITH ', selezionata'")
        )
    }

    /// Waits for `identifier`'s own row to report the selected state, then asserts it is
    /// the *only* one doing so in `workspace-tree`.
    ///
    /// `XCUIElementQuery.count` is a single, unwaited snapshot - unlike
    /// `waitForExistence`, it does not poll. Counting straight after a click risks
    /// reading the tree a beat before SwiftUI's re-render (and the accessibility label it
    /// carries) has caught up, which is a timing gap in the assertion, not in the
    /// production code the click drives. Waiting for the one row this click is expected
    /// to select gives XCUITest's own retrying wait a chance to observe the settled
    /// state before the count below is taken as final.
    private func assertExactlyOneRowSelected(identifier: String, suffix: String, file: StaticString = #filePath, line: UInt = #line) {
        let expected = tree.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label ENDSWITH %@", identifier, suffix)
        ).firstMatch
        XCTAssertTrue(expected.waitForExistence(timeout: 5),
                      "la riga «\(identifier)» non riporta lo stato selezionato", file: file, line: line)
        XCTAssertEqual(selectedRowsInTree.count, 1,
                        "esattamente una riga dell'albero deve riportare lo stato selezionato", file: file, line: line)
    }

    // MARK: Ported (R-14) - same assertions as before, row lookup substituted for the row's new element type.

    func testThePaneOpensEmptyAndFillsInOnlyAfterAClick() throws {
        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5),
                      "il pane dovrebbe aprirsi senza nessuna board scelta")
        XCTAssertTrue(rootBoardRow.waitForExistence(timeout: 5))

        rootBoardRow.click()

        XCTAssertFalse(app.staticTexts["Nessuna board aperta"].exists,
                        "lo stato vuoto dovrebbe sparire una volta aperta una board")
    }

    /// This is the test the SPEC's Decision 7 and R-10 contradict (plan, "Five things the
    /// SPEC says that are false or under-determined"): no open-board persistence exists in
    /// this app, and `5041d5c` shipped exactly the behaviour asserted here. It stays green.
    func testLeavingAndReturningToTheWorkspacePaneForgetsTheOpenBoard() throws {
        rootBoardRow.click()
        XCTAssertFalse(app.staticTexts["Nessuna board aperta"].exists)

        app.staticTexts["Note"].click()
        XCTAssertTrue(app.staticTexts["Workspace"].waitForExistence(timeout: 5))
        app.staticTexts["Workspace"].click()

        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5),
                      "tornando sul pane la board aperta prima non dovrebbe essere rimasta")
    }

    // MARK: New (R-01) - a folder that owns a board is one row, not two.

    func testAFolderThatOwnsABoardIsOneRowNotTwo_R01() throws {
        XCTAssertTrue(row(identifier: "workspace-board-\(boardFile)").waitForExistence(timeout: 5),
                      "manca la riga unica della cartella «\(boardFolder)», che possiede una board")
        XCTAssertFalse(row(identifier: "workspace-folder-\(boardFolder)").exists,
                        "«\(boardFolder)» possiede una board: non deve esistere anche una riga workspace-folder-*")
    }

    // MARK: New (R-02/R-03) - selecting a nested board lights exactly its own row.

    func testSelectingANestedBoardLightsExactlyOneRowInTheTree_R02_R03() throws {
        app.buttons["workspace-expand-all"].click()

        let nested = row(identifier: "workspace-board-\(nestedBoardFile)")
        XCTAssertTrue(nested.waitForExistence(timeout: 5), "la board annidata non è comparsa dopo «Espandi tutto»")
        nested.click()

        assertExactlyOneRowSelected(identifier: "workspace-board-\(nestedBoardFile)", suffix: ", aperta")
    }

    // MARK: New (R-04) - a board-less folder's row closes the open board and selects only itself.

    func testClickingABoardLessFolderRowClosesTheOpenBoardAndSelectsOnlyItsRow_R04() throws {
        rootBoardRow.click()
        XCTAssertFalse(app.staticTexts["Nessuna board aperta"].exists, "la board radice avrebbe dovuto aprirsi")

        let grouping = row(identifier: "workspace-folder-\(groupingFolder)")
        XCTAssertTrue(grouping.waitForExistence(timeout: 5))
        grouping.click()

        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5),
                      "selezionare una cartella senza board dovrebbe richiudere quella aperta")
        assertExactlyOneRowSelected(identifier: "workspace-folder-\(groupingFolder)", suffix: ", selezionata")
    }

    // MARK: New (R-05) - a board-less folder's row opens nothing and raises no sheet.

    func testClickingABoardLessFolderRowOpensNoBoardAndRaisesNoSheet_R05() throws {
        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.sheets.count, 0)

        let grouping = row(identifier: "workspace-folder-\(groupingFolder)")
        XCTAssertTrue(grouping.waitForExistence(timeout: 5))
        grouping.click()

        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5),
                      "nessuna board dovrebbe essersi aperta cliccando una cartella senza board")
        XCTAssertEqual(app.sheets.count, 0, "nessun foglio dovrebbe comparire per il solo click sulla riga")
    }

    // MARK: Fixture

    /// Real folders and files on disk before the app ever launches: the root board
    /// itself (what the two ported tests click), one folder owning its own board
    /// directly under the root (`boardFolder`), a board nested two levels inside it
    /// (`nestedBoardFile`), and a board-less grouping folder whose only content is a
    /// subfolder that owns a board (`groupingFolder` / `groupingChildBoardFile`) - the
    /// shape SPEC Decision 3 and ADR-0024 §D5 both require a selectable, non-opening row
    /// for.
    ///
    /// The root board's own `.canvas` file is not optional here: `WorkspaceTree.build`
    /// only folds the root into a `.workspace(board: <path>)` row - the one
    /// `workspace-board-<vault>.canvas` identifier `rootBoardRow` looks for - when that
    /// file actually exists on disk (`WorkspaceTree.swift`, the root-synthesis fallback).
    /// With no such file it is `.workspace(board: nil)`, `workspace-folder-` instead, and
    /// clicking it selects rather than opens (ADR-0024 §D5, applied to the root exactly
    /// as to any other never-materialized folder). A vault that has genuinely never had
    /// a root board is a real state this app supports, but it is not what
    /// `testThePaneOpensEmptyAndFillsInOnlyAfterAClick` and
    /// `testLeavingAndReturningToTheWorkspacePaneForgetsTheOpenBoard` are about - both
    /// are ported unchanged in intent from `5041d5c`, where "click the root row" always
    /// meant "open the board", so the fixture gives them a root board to open.
    private func makeFixtureBoards() throws {
        let rootBoardFile = "\(vault.lastPathComponent).canvas"
        for boardPath in [rootBoardFile, boardFile, nestedBoardFile, groupingChildBoardFile] {
            let url = vault.appending(path: boardPath, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Self.emptyCanvas.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static let emptyCanvas = """
    { "nodes": [], "edges": [] }
    """
}
