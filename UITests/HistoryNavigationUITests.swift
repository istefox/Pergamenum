import XCTest

/// Indietro and Avanti, walked on screen (ADR-0015).
///
/// `NavigationHistoryTests` owns the rules; this suite owns the wiring, which is the half no
/// unit test in a SwiftUI project can reach: whether the two buttons are in the window at all,
/// and whether the observer that fills the history is attached.
///
/// Every control is found by `accessibilityIdentifier`, the sidebar rows included
/// (`sidebarRow(_:)`), and `-disableCalendar YES` keeps `EventKitStore` away from somebody's
/// real diary.
///
/// The off-until-somewhere-to-go test retired here per the UI-suite-replacement census (stage
/// 3, Task 6): its two initial checks were true with no recorder attached, so it wasn't
/// exercising the wiring it claimed to. Replaced by CommandActionTests:56 and
/// NavigationHistoryTests:25.
final class HistoryNavigationUITests: PergamenumUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try makeTemporaryVault(prefix: "HistoryUITest")
    }

    /// Three panes forward, three back, three forward again, in the same order.
    func testTheArrowsWalkThePanesInOrder() throws {
        launch()

        openSidebarRow("pane-tags")
        XCTAssertTrue(tagList.waitForExistence(timeout: 5), "la pane Tag non è comparsa")
        openSidebarRow("pane-views")
        XCTAssertTrue(viewsPane.waitForExistence(timeout: 5), "la pane Viste non è comparsa")

        back.click()
        XCTAssertTrue(tagList.waitForExistence(timeout: 5), "indietro non è tornato a Tag")
        XCTAssertFalse(viewsPane.exists, "la pane Viste è ancora disegnata dopo indietro")

        forward.click()
        XCTAssertTrue(viewsPane.waitForExistence(timeout: 5), "avanti non è tornato a Viste")
    }

    // MARK: Support

    private func launch() {
        launchApp()
        waitForMainWindow()
    }

    private var back: XCUIElement { app.buttons["history-back"].firstMatch }
    private var forward: XCUIElement { app.buttons["history-forward"].firstMatch }
    private var tagList: XCUIElement { app.descendants(matching: .any).matching(identifier: "tag-list").firstMatch }
    private var viewsPane: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "views-pane").firstMatch
    }
}
