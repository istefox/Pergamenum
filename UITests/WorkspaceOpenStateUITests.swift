import XCTest

/// The Workspace pane starts empty - nothing highlighted in the board list, no board on
/// screen - until a board is actually clicked, the same way the note editor starts with
/// nothing open rather than with the last note pinned forever.
final class WorkspaceOpenStateUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory())
            .appending(path: "WorkspaceOpenStateUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

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

    /// The root board's row: named after the vault, exactly as `CanvasStore.boardPath(forFolder:)`
    /// maps an empty folder (SPEC §6.1 - "the root board is named after the vault").
    private var rootBoardRow: XCUIElement {
        app.buttons["workspace-board-\(vault.lastPathComponent).canvas"]
    }

    func testThePaneOpensEmptyAndFillsInOnlyAfterAClick() throws {
        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5),
                      "il pane dovrebbe aprirsi senza nessuna board scelta")
        XCTAssertTrue(rootBoardRow.waitForExistence(timeout: 5))

        rootBoardRow.click()

        XCTAssertFalse(app.staticTexts["Nessuna board aperta"].exists,
                        "lo stato vuoto dovrebbe sparire una volta aperta una board")
    }

    func testLeavingAndReturningToTheWorkspacePaneForgetsTheOpenBoard() throws {
        rootBoardRow.click()
        XCTAssertFalse(app.staticTexts["Nessuna board aperta"].exists)

        app.staticTexts["Note"].click()
        XCTAssertTrue(app.staticTexts["Workspace"].waitForExistence(timeout: 5))
        app.staticTexts["Workspace"].click()

        XCTAssertTrue(app.staticTexts["Nessuna board aperta"].waitForExistence(timeout: 5),
                      "tornando sul pane la board aperta prima non dovrebbe essere rimasta")
    }
}
