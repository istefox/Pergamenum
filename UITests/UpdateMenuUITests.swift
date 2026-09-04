import XCTest

// ADR-0031 (Sparkle auto-update integration), plan
// docs/superpowers/plans/2026-09-04-sparkle-auto-update-integration.md, Task 4 (R-02).
//
// **What this file does not cover.** It never clicks «Cerca Aggiornamenti…»: a click is a
// real network fetch, and under `-disableUpdater YES` it is a no-op that would prove
// nothing either way. R-02's "triggers Sparkle's standard update-check UI" half is verified
// by hand against a real published appcast (plan Task 10), not by this suite. What this
// file does assert: the item exists, next to «Informazioni su Pergamenum», in the app menu
// every launch already shows - the one place in the repo where finding a control by its
// title is correct rather than forbidden (CLAUDE.md's `accessibilityIdentifier` rule is
// about app-authored controls; a `CommandGroup` button has none).
//
// Launches with **both** `-disableCalendar YES` and `-disableUpdater YES`, per CLAUDE.md's
// working agreement that every file under `UITests/` carries both flags, not only the ones
// that would otherwise notice.
final class UpdateMenuUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory())
            .appending(path: "UpdateMenuUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

        app = XCUIApplication()
        stateBase = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES",
                               "-disableUpdater", "YES",
                               "-stateBase", stateBase.path(percentEncoded: false)]
        app.launch()
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
    }

    func testPergamenumMenuHasACercaAggiornamentiItemBesideInformazioni() throws {
        let pergamenumMenu = app.menuBars.menuBarItems["Pergamenum"]
        XCTAssertTrue(pergamenumMenu.waitForExistence(timeout: 5), "manca il menu «Pergamenum»")
        pergamenumMenu.click()

        let about = app.menuBars.menuItems["Informazioni su Pergamenum"]
        XCTAssertTrue(about.waitForExistence(timeout: 5), "manca «Informazioni su Pergamenum»")

        let checkForUpdates = app.menuBars.menuItems["Cerca Aggiornamenti…"]
        XCTAssertTrue(
            checkForUpdates.waitForExistence(timeout: 5),
            "manca «Cerca Aggiornamenti…» nel menu Pergamenum"
        )

        // Never clicked - see the file header.
        pergamenumMenu.click() // closes the menu again
    }
}
