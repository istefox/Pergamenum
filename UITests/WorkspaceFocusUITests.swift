import XCTest

/// Concentrazione: the Workspace's own toggle that hides the app sidebar, the board
/// list and the tray at once, and brings them back on a second click.
final class WorkspaceFocusUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory())
            .appending(path: "WorkspaceFocusUITest-\(UUID().uuidString)")
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

    private var focusToggle: XCUIElement {
        let element = app.checkBoxes["Concentrazione"]
        XCTAssertTrue(element.waitForExistence(timeout: 5), "manca l'interruttore «Concentrazione»")
        return element
    }

    func testConcentrazioneHidesTheThreePanelsAndRestoresThemOnASecondClick() throws {
        // Before: the app sidebar and the board list are both on screen.
        XCTAssertTrue(app.staticTexts["Note"].exists, "la sidebar dell'app dovrebbe essere visibile")
        XCTAssertTrue(app.textFields["workspace-filter"].exists, "l'elenco board dovrebbe essere visibile")

        focusToggle.click()

        XCTAssertTrue(
            app.staticTexts["Note"].waitForNonExistence(timeout: 5),
            "la sidebar dell'app è ancora visibile in modalità concentrazione"
        )
        XCTAssertFalse(
            app.textFields["workspace-filter"].exists,
            "l'elenco board è ancora visibile in modalità concentrazione"
        )

        focusToggle.click()

        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 5), "la sidebar dell'app non è tornata")
        XCTAssertTrue(
            app.textFields["workspace-filter"].waitForExistence(timeout: 5),
            "l'elenco board non è tornato"
        )
    }

    func testConcentrazioneLeavesTheTrayStateAsItWasFound() throws {
        let trayToggle = app.checkBoxes["Nuovi elementi"]
        XCTAssertTrue(trayToggle.waitForExistence(timeout: 5))
        // Closed on purpose, before entering concentrazione: the mode hides the tray
        // without touching whether it was open, so this has to still read closed after.
        if trayToggle.value as? Int != 0 { trayToggle.click() }

        focusToggle.click()
        focusToggle.click()

        XCTAssertEqual(
            trayToggle.value as? Int, 0,
            "uscire dalla concentrazione ha riaperto il tray da solo"
        )
    }
}

private extension XCUIElement {
    /// The mirror of `waitForExistence`: succeeds once the element is gone, rather
    /// than once it appears.
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while exists, Date() < deadline { usleep(100_000) }
        return !exists
    }
}
