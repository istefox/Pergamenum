import XCTest

/// A shortcut the user moved in settings, checked against the menu bar it is meant to
/// change: a binding that is stored correctly and never reaches the menu bar would pass
/// every unit test in the suite, since `MenuCommands`'s store-to-menu-bar wiring has no
/// in-process cover.
///
/// Two tests retired here per the UI-suite-replacement census (stage 3, Task 6): the
/// folder-tree test (chevron clicked by a fixed pixel offset, `NoteTree`'s own structure)
/// and the settings-pane listing test (ShortcutTests:124,134,177 cover default, override
/// and reset; :209 covers the catalogue the pane is generated from). The fixture vault
/// no longer seeds folders or notes, since the kept test needs neither.
final class NoteTreeAndShortcutsUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var mailStoreRoot: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try makeVault()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
        try? FileManager.default.removeItem(at: mailStoreRoot)
    }

    /// Launches the app on the fixture vault.
    ///
    /// Nothing is snapshotted or restored. `-recentVaults` and `-shortcutOverrides`
    /// both land in the argument domain, and both stores refuse to persist a value
    /// that arrived that way, so a run cannot reach the user's own preferences. A
    /// guard on this side could not work: the XCUITest runner is sandboxed and its
    /// `UserDefaults(suiteName:)` is a private copy in its own container.
    private func launch(shortcuts: String? = nil) {
        app = XCUIApplication()
        stateBase = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)
        mailStoreRoot = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-mailstore", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: mailStoreRoot, withIntermediateDirectories: true)
        var arguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                         "-disableCalendar", "YES",
                         "-mailStoreRoot", mailStoreRoot.path(percentEncoded: false),
                         "-disablePlaud", "YES",
                         "-disableUpdater", "YES",
                         "-stateBase", stateBase.path(percentEncoded: false)]
        if let shortcuts {
            arguments += ["-shortcutOverrides", shortcuts]
        }
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
    }

    // MARK: A shortcut the user moved

    func testAShortcutChangedInSettingsIsTheOneTheMenuAnswersTo() throws {
        // The quick switcher moved off Cmd+O and onto Cmd+J. Written as an old-style
        // property list rather than as the JSON the settings pane stores: UserDefaults
        // parses an argument beginning with `{` as a plist, and a value that parser
        // cannot read is dropped before the app ever sees it, so a JSON literal here
        // would leave the shortcut at its default and the test would prove nothing.
        launch(shortcuts: "{quickSwitcher = {key = j; modifiers = 1;};}")

        app.typeKey("j", modifierFlags: .command)
        XCTAssertTrue(app.textFields["quick-switcher-field"].waitForExistence(timeout: 5),
                      "la scorciatoia riassegnata non ha aperto il quick switcher")
        app.typeKey(.escape, modifierFlags: [])

        // And the default is gone rather than still working alongside it: a menu that
        // answers to both keys is a menu that never read the new binding.
        XCTAssertTrue(app.textFields["quick-switcher-field"].waitForNonExistence(timeout: 5))
        app.typeKey("o", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(app.textFields["quick-switcher-field"].exists,
                       "Cmd+O apre ancora il quick switcher: la scorciatoia vecchia è rimasta")
    }

    // MARK: Fixture

    private func makeVault() throws {
        vault = URL(filePath: NSTemporaryDirectory())
            .appending(path: "TreeUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }
}
