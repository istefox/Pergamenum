import XCTest

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 10 -
// R-18, R-33, R-39; UX-BLUEPRINT's own accessibility-identifier checklist.
//
// Per this dispatch's explicit instruction: this file must **build for testing and
// never run**. `PergamenumUITests` launches a real `Pergamenum.app` instance that
// steals the global hotkey (`CLAUDE.md` "`.claude/test-cmd` runs at the end of every
// turn"), so it is compiled here (`xcodebuild ... build-for-testing`) and executed
// only by hand, never by an agent. Every assertion below reaches a control by its
// `accessibilityIdentifier`, never by the words on it (CLAUDE.md's own rule, paid for
// twice already).
//
// Identifiers asserted here are the ones the UX-BLUEPRINT checklist names that
// `Sources/Features/Pratiche/**` already carries as of this dispatch. A checklist
// identifier with no real view behind it yet is intentionally left out of this file
// rather than asserted against a control that cannot exist - see this dispatch's own
// report for the MISSING list the coder still owes.
final class PraticheUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var mailStoreRoot: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory()).appending(path: "PraticheUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

        app = XCUIApplication()
        stateBase = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)
        // R-19/ADR §D7: a per-test fixture root, never the real `~/Library/Mail` -
        // no test in this file writes an Envelope Index into it, so every FDA/tray
        // read below finds an empty, readable store rather than a real mailbox.
        mailStoreRoot = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-mailstore", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: mailStoreRoot, withIntermediateDirectories: true)

        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES",
                               "-disableUpdater", "YES",
                               "-mailStoreRoot", mailStoreRoot.path(percentEncoded: false),
                               "-stateBase", stateBase.path(percentEncoded: false)]
        app.launch()
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
        showPratiche()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
        try? FileManager.default.removeItem(at: mailStoreRoot)
    }

    private func showPratiche() {
        let row = app.staticTexts["Pratiche"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la sezione Pratiche non è nella barra laterale")
        row.click()
        XCTAssertTrue(
            element("pratiche-pane").waitForExistence(timeout: 5),
            "la sezione Pratiche non si è aperta"
        )
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    // MARK: - R-18: the pane itself, the list, and the Full Disk Access banner

    func testThePaneCarriesItsListAndPrimaryActions() throws {
        XCTAssertTrue(element("pratiche-pane").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-list").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-new").waitForExistence(timeout: 5), "manca «Nuova pratica»")
        XCTAssertTrue(element("pratiche-refresh").waitForExistence(timeout: 5), "manca «Aggiorna»")
    }

    /// R-18: "Full Disk Access is probed per trigger" - the banner and its settings
    /// button carry their own stable identifiers so a future test can assert on the
    /// denied state without reading any Italian copy.
    func testTheFullDiskAccessBannerAndItsSettingsButtonAreAddressable() throws {
        XCTAssertTrue(element("pratiche-fda-banner").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-fda-open-settings").waitForExistence(timeout: 5))
    }

    func testTheFilterRowCarriesTheSenderMenuAndAttachmentsToggle() throws {
        XCTAssertTrue(element("pratiche-filter").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-sender-menu").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-attachments-only").waitForExistence(timeout: 5))
    }

    // MARK: - R-33: the tray

    func testTheTrayIsAddressable() throws {
        XCTAssertTrue(element("pratiche-tray").waitForExistence(timeout: 5))
    }

    // MARK: - R-39: the timeline and its inspector toggle

    func testTheTimelineAndInspectorToggleAreAddressable() throws {
        XCTAssertTrue(element("pratiche-timeline").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-inspector-toggle").waitForExistence(timeout: 5))
    }

    func testTheAddNoteAndAddCallEntryPointsAreAddressable() throws {
        XCTAssertTrue(element("pratiche-add-note").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-add-call").waitForExistence(timeout: 5))
    }

    // MARK: - The wizard (opened from «Nuova pratica»)

    func testTheWizardOpensWithItsTitleAndClientFields() throws {
        element("pratiche-new").click()
        XCTAssertTrue(element("pratiche-wizard").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-wizard-title").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-wizard-client").waitForExistence(timeout: 5))
    }
}
