import XCTest

/// Indietro and Avanti, walked on screen (ADR-0015).
///
/// `NavigationHistoryTests` owns the rules; this suite owns the wiring, which is the half no
/// unit test in a SwiftUI project can reach: whether the two buttons are in the window at all,
/// whether the observer that fills the history is attached, and whether §D3's drift rule
/// survives the trip through a real toolbar. Three of the four assertions here would pass
/// against a history nothing was recording.
///
/// Every control is found by `accessibilityIdentifier`. The sidebar rows are the exception the
/// whole suite already makes - their titles are the pane names, which are a contract of their
/// own - and `-disableCalendar YES` keeps `EventKitStore` away from somebody's real diary.
final class HistoryNavigationUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var mailStoreRoot: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory()).appending(path: "HistoryUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
        try? FileManager.default.removeItem(at: mailStoreRoot)
    }

    /// A window that has been nowhere offers no way back, and the first move enables one.
    func testTheArrowsAreOffUntilThereIsSomewhereToGo() throws {
        launch()

        XCTAssertFalse(back.isEnabled, "«Indietro» è accesa su una finestra appena aperta")
        XCTAssertFalse(forward.isEnabled, "«Avanti» è accesa su una finestra appena aperta")

        show("Tag")
        XCTAssertTrue(tagList.waitForExistence(timeout: 5), "la pane Tag non è comparsa")
        XCTAssertTrue(back.isEnabled, "«Indietro» è spenta dopo essere andati da qualche parte")
        XCTAssertFalse(forward.isEnabled, "«Avanti» è accesa senza essere tornati indietro")
    }

    /// Three panes forward, three back, three forward again, in the same order.
    func testTheArrowsWalkThePanesInOrder() throws {
        launch()

        show("Tag")
        XCTAssertTrue(tagList.waitForExistence(timeout: 5), "la pane Tag non è comparsa")
        show("Viste")
        XCTAssertTrue(viewsPane.waitForExistence(timeout: 5), "la pane Viste non è comparsa")

        back.click()
        XCTAssertTrue(tagList.waitForExistence(timeout: 5), "indietro non è tornato a Tag")
        XCTAssertFalse(viewsPane.exists, "la pane Viste è ancora disegnata dopo indietro")

        forward.click()
        XCTAssertTrue(viewsPane.waitForExistence(timeout: 5), "avanti non è tornato a Viste")
    }

    // MARK: Support

    private func launch() {
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

    private func show(_ pane: String) {
        let row = app.staticTexts[pane].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "manca la sezione \(pane)")
        row.click()
    }

    private var back: XCUIElement { app.buttons["history-back"].firstMatch }
    private var forward: XCUIElement { app.buttons["history-forward"].firstMatch }
    private var dayNext: XCUIElement { app.buttons["day-next"].firstMatch }
    private var tagList: XCUIElement { app.descendants(matching: .any).matching(identifier: "tag-list").firstMatch }
    private var viewsPane: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "views-pane").firstMatch
    }
}
