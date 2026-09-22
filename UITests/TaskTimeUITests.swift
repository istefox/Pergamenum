import XCTest

/// The hour a task can carry on its dates (ADR-0004), and the block it can become on
/// the day it belongs to.
///
/// Its own class rather than more of `ComposerUITests`: that one is about where the
/// composers live and how they keep focus, this one about what the dates mean.
final class TaskTimeUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var mailStoreRoot: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory())
            .appending(path: "TaskTimeUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try """
        ---
        date: 2026-08-13
        tags:
          - type-note
        ---

        # Nota di prova
        """.write(
            to: vault.appending(path: "Nota di prova.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )

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
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
        try? FileManager.default.removeItem(at: mailStoreRoot)
    }

    private func toolbarButton(_ label: String, timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.toolbars.buttons[label]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "manca il pulsante «\(label)»")
        return element
    }

    private func show(_ pane: String) {
        let row = app.staticTexts[pane]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la sezione \(pane) non è nella barra laterale")
        row.click()
    }

    // MARK: The hour, and the block it can become

    /// No hour, no question: a block is a span of a day, and a date alone says nothing
    /// about where on the day it goes.
    func testWithoutAnHourTheComposerDoesNotAskAboutTheTimeline() throws {
        show("Attività")
        toolbarButton("Cattura rapida", timeout: 15).click()
        let text = app.textFields["task-composer-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.click()
        text.typeText("Task senza orario")

        app.buttons["task-composer-scheduled"].click()
        let today = app.descendants(matching: .any).matching(identifier: "date-option-today").firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.click()

        XCTAssertFalse(
            app.checkBoxes["task-composer-block"].waitForExistence(timeout: 2),
            "chiede del blocco tempo per un task che non ha un orario"
        )
    }

}
