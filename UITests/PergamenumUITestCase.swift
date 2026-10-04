import XCTest

/// The one launch harness every UI-test class runs through (PG-128, #228).
///
/// It owns the three throwaway directories a run needs - the vault, the per-vault state base
/// (`-stateBase`, ADR-0017) and an empty Mail store (`-mailStoreRoot`, ADR-0036) - the isolation
/// flags every launch passes, and the teardown that terminates the app and removes all three.
/// Each file used to spell this by hand, twenty-one copies at the peak, and that is how two of
/// them lost a flag (`PraticheUITests` had no `-disablePlaud`, `WikilinkNavigationUITests` no
/// `-mailStoreRoot`). A class that needs more arguments passes them to
/// `launchApp(extraArguments:)`; it never re-spells the base set.
///
/// `Tests/UITestLaunchHarnessGuardTests.swift` fails if a file under `UITests/` declares a test
/// class on `XCTestCase` directly, builds its own `XCUIApplication` or sets launch arguments, so
/// the copies cannot come back.
class PergamenumUITestCase: XCTestCase {
    var vault: URL!
    var stateBase: URL!
    var mailStoreRoot: URL!
    var app: XCUIApplication!

    /// The arguments every launch carries, each one a CLAUDE.md rule:
    /// - `-recentVaults` in the plist array form, since the key holds `[String]` and a bare path
    ///   leaves `stringArray(forKey:)` nil, so no vault would reopen;
    /// - `-disableCalendar YES`, so a run never reads the machine's real diary;
    /// - `-mailStoreRoot`, so a pratiche sync never reaches `~/Library/Mail` (ADR-0036);
    /// - `-disablePlaud YES`, so the recordings importer never calls the loopback service
    ///   (ADR-0032);
    /// - `-disableUpdater YES`, so no Sparkle alert lands on screen during `launch()` (ADR-0031);
    /// - `-disableContenitore YES`, so the real drop folder is never listed or emptied (ADR-0071);
    /// - `-stateBase`, so the index and derived state live beside the throwaway vault.
    static func isolationArguments(vault: URL, stateBase: URL, mailStoreRoot: URL) -> [String] {
        ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
         "-disableCalendar", "YES",
         "-mailStoreRoot", mailStoreRoot.path(percentEncoded: false),
         "-disablePlaud", "YES",
         "-disableUpdater", "YES", "-disableContenitore", "YES",
         "-stateBase", stateBase.path(percentEncoded: false)]
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // `QuitReviewUITests` ends with the app already gone, by its own Cmd+Q.
        if let app, app.state != .notRunning { app.terminate() }
        for directory in [vault, stateBase, mailStoreRoot].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    /// Creates an empty vault at `<tmp>/<prefix>-<UUID>` and keeps it as `vault`. The caller
    /// writes its fixture into it before `launchApp(extraArguments:)`.
    @discardableResult
    func makeTemporaryVault(prefix: String) throws -> URL {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: "\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        vault = root
        return root
    }

    /// Creates the state base and the empty Mail store beside `vault`, then launches the app on
    /// it with `isolationArguments` followed by `extraArguments`. Waiting for the window is the
    /// caller's: each class waits for its own landmark, with its own timeout and message.
    func launchApp(extraArguments: [String] = []) {
        precondition(vault != nil, "makeTemporaryVault(prefix:) must run before launchApp(extraArguments:)")
        let temporary = URL(filePath: NSTemporaryDirectory())
        stateBase = temporary.appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)
        mailStoreRoot = temporary.appending(path: vault.lastPathComponent + "-mailstore", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: mailStoreRoot, withIntermediateDirectories: true)

        app = XCUIApplication()
        app.launchArguments = Self.isolationArguments(
            vault: vault, stateBase: stateBase, mailStoreRoot: mailStoreRoot
        ) + extraArguments
        app.launch()
    }

    /// One sidebar row, by the `sidebar-<id>` identifier `RootView.row(_:)` derives from the
    /// `SidebarItem`'s `id` (`"pane-notes"`, `"pane-pratiche"`, `"scale-week"`, `"daily-note"`).
    /// Never by its title (PG-265): a pane's name is prose, and its own breadcrumb bar draws
    /// the same word when nothing is open in it.
    func sidebarRow(_ itemID: String) -> XCUIElement {
        element("sidebar-\(itemID)")
    }

    /// One note's row in the Note pane, tree or flat list alike, by the `note-row-<path>`
    /// identifier both draw from the note's vault-relative path (`"Origine.md"`,
    /// `"Ambiguo/NotaAmbigua.md"`). Never by its title (PG-265): the title is the fixture's
    /// prose, and the same words also show on the open tab and in the editor.
    func noteRow(_ relativePath: String) -> XCUIElement {
        element("note-row-\(relativePath)")
    }

    /// Any element in the app, of any kind, by its `accessibilityIdentifier`. Four classes kept
    /// their own copy of this lookup until PG-265. A class whose walk must stay inside one
    /// subtree (`GlobalSearchUITests.sheetElement(_:)`) scopes its own query instead.
    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Waits for one sidebar row, by `sidebarRow(_:)`, then clicks it. Four classes kept their
    /// own copy of these three lines until PG-265, each with its own failure message.
    func openSidebarRow(
        _ itemID: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line
    ) {
        let row = sidebarRow(itemID)
        XCTAssertTrue(
            row.waitForExistence(timeout: timeout),
            "manca la riga «sidebar-\(itemID)» nella barra laterale", file: file, line: line
        )
        row.click()
    }

    /// Opens the Pratiche pane from its sidebar row and waits for the pane itself. Here rather
    /// than in each class because `PraticheUITests` and `AttachmentChipContextMenuUITests` both
    /// need it, and kept two copies verbatim until PG-265.
    func showPratiche() {
        openSidebarRow("pane-pratiche")
        XCTAssertTrue(
            element("pratiche-pane").waitForExistence(timeout: 5),
            "la sezione Pratiche non si è aperta"
        )
    }

    /// Mirrors `PraticaMessageRow.hash(of:)` exactly (FNV-1a over the message id string), so a
    /// class computes the same `pratiche-message-…`/`pratiche-attachment-…` identifiers
    /// production draws without a `@testable import`. `PraticheUITests` and
    /// `AttachmentChipContextMenuUITests` each kept a copy until PG-120's sweep.
    static func hash(_ messageID: String) -> String {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array(messageID.utf8) {
            value ^= UInt64(byte)
            value &*= 0x0000_0100_0000_01b3
        }
        return String(value, radix: 16)
    }

    /// The launch-ready check: the window is up once the sidebar's Note row is. Fifteen classes
    /// spelled it as `app.staticTexts["Note"]`, which also matched the Note pane's breadcrumb;
    /// like that check, it witnesses the window, not the vault - the sidebar is drawn with or
    /// without one, so a class that needs the vault still waits for its own landmark.
    func waitForMainWindow(timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            sidebarRow("pane-notes").waitForExistence(timeout: timeout),
            "la barra laterale non è comparsa", file: file, line: line
        )
    }
}
