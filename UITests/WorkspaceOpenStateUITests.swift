import XCTest

/// The Workspace pane starts empty - nothing highlighted in the board list, no board on
/// screen - until a board is actually clicked, the same way the note editor starts with
/// nothing open rather than with the last note pinned forever.
///
/// ADR-0024 ("One selection, one row, one meaning"). Plan
/// `docs/superpowers/plans/2026-08-25-workspace-board-tree-single-selection.md`, Task 6
/// (R-14): this file is the rewrite that task asks for. Every row is found by
/// `accessibilityIdentifier`, never by the words on it (`CLAUDE.md`) - the tree stopped
/// being a `Button` per row (ADR-0024 §D1/F5), so the ported test below substitutes
/// `app.descendants(matching: .any).matching(identifier:)` for the old `app.buttons[...]`
/// lookup, and every new test follows the same rule from the start. No assertion in this
/// file reads `selectedFolder` or `hasOpenBoard` - both were removed from the production
/// code this plan's earlier tasks replaced (ADR-0024 §D4/§D6) and neither is a concept a
/// UI test, which only ever sees rendered rows and labels, could reach even by accident.
///
/// ADR-0025 ("A board is a file, a folder is a container") rewrote what the rows *are*
/// without touching how they are found: a folder and a `.canvas` are now two different
/// rows (§D2). The tests that chain added (R-01, R-03, R-08, R-10, R-11, and the §D2
/// reversal itself) retired here per the UI-suite-replacement census (stage 3, Task 6),
/// each with an in-process replacement named in the census's WorkspaceOpenStateUITests
/// entry. What is left is what stayed genuinely GUI-only: the empty-then-filled pane
/// (R-14) and selecting a nested board lighting exactly one row (R-02/R-03).
final class WorkspaceOpenStateUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var mailStoreRoot: URL!
    private var app: XCUIApplication!

    // MARK: Fixture identity, named once so every step and every assertion agrees.

    /// A board nested two levels deep - the R-02/R-03 target: selecting it must light
    /// exactly its own row, nowhere else in the tree.
    private let nestedBoardFile = "Vibrofer/Dettaglio/Dettaglio.canvas"

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
        mailStoreRoot = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-mailstore", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: mailStoreRoot, withIntermediateDirectories: true)
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES",
                               "-mailStoreRoot", mailStoreRoot.path(percentEncoded: false),
                               "-disablePlaud", "YES",
                               "-disableUpdater", "YES",
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
        try? FileManager.default.removeItem(at: mailStoreRoot)
    }

    // MARK: Row lookup - every one by identifier, never by the words on it (CLAUDE.md).

    /// The `.canvas` the fixture writes at the vault root. It is named after the vault
    /// only because the fixture writes it that way: since ADR-0025 §D1 no rule derives a
    /// board from a folder's name, and `CanvasStore.boardPath(forFolder:)` - what this
    /// comment used to point at - no longer exists.
    ///
    /// So this is an **ordinary top-level board row** (§D2), not the synthesized root row
    /// the tree used to fold a folder into: the vault root is the list itself and has no
    /// row at all. The identifier is unchanged, `workspace-board-<boardPath>`, which is
    /// exactly why every assertion below still resolves after that rewrite.
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

    // MARK: New (R-02/R-03) - selecting a nested board lights exactly its own row.

    func testSelectingANestedBoardLightsExactlyOneRowInTheTree_R02_R03() throws {
        app.buttons["workspace-expand-all"].click()

        let nested = row(identifier: "workspace-board-\(nestedBoardFile)")
        XCTAssertTrue(nested.waitForExistence(timeout: 5), "la board annidata non è comparsa dopo «Espandi tutto»")
        nested.click()

        assertExactlyOneRowSelected(identifier: "workspace-board-\(nestedBoardFile)", suffix: ", aperta")
    }

    // MARK: Fixture

    /// Real folders and files on disk before the app ever launches: a `.canvas` in the
    /// vault root itself (what the kept test clicks) and a board nested two levels inside
    /// a folder (`nestedBoardFile`, R-02/R-03's target).
    ///
    /// The root `.canvas` is not optional here, but the reason has changed with the model:
    /// it is no longer a root row the tree synthesizes when the file happens to exist, it
    /// is simply a board file, and a board file is a row because it is a file
    /// (ADR-0025 §D1/§D2). Remove it and the kept test has no board to open - nothing else
    /// about the tree changes, because the vault root is the list rather than a row in it.
    private func makeFixtureBoards() throws {
        let rootBoardFile = "\(vault.lastPathComponent).canvas"
        try writeBoard(Self.emptyCanvas, at: rootBoardFile)
        try writeBoard(Self.emptyCanvas, at: nestedBoardFile)
    }

    private func writeBoard(_ contents: String, at boardPath: String) throws {
        let url = vault.appending(path: boardPath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static let emptyCanvas = """
    { "nodes": [], "edges": [] }
    """
}
