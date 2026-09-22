import XCTest

/// The Diario pane, driven the way a person drives it: the composer, the timeline, and
/// the file all of it ends up in.
///
/// The diary writes on its own - there is no Salva - so the kept test also checks the
/// file on disk. A day that is only on screen is a day that is not written down.
///
/// Five tests retired here per the UI-suite-replacement census (stage 3, Task 6): the
/// toolbar-existence and editor-only-surface checks had no production seam behind them
/// (existence-only assertions), and the two delete paths plus the typing/day-change
/// round trip are now covered by `DiaryControllerTests`, cited in the census's
/// DiaryUITests entry. What is left is the one end-to-end this pane still needs a real
/// window for: composing a block through the toolbar, the sheet and Salva, and finding
/// it both on the timeline and in the file.
final class DiaryUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var mailStoreRoot: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory()).appending(path: "DiaryUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

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
        showDiary()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
        try? FileManager.default.removeItem(at: mailStoreRoot)
    }

    private func showDiary() {
        let row = app.staticTexts["Diario"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la sezione Diario non è nella barra laterale")
        row.click()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "diary-header").firstMatch
                .waitForExistence(timeout: 5),
            "la sezione Diario non si è aperta"
        )
    }

    /// The whole point of the pane: block out a couple of hours, give them a name, and
    /// find both on the timeline and in the file.
    func testABlockIsComposedAndWrittenToTheFile() throws {
        app.toolbars.buttons["Nuovo blocco"].click()

        let title = app.textFields["diary-sheet-title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "la scheda del blocco non si è aperta")
        title.click()
        title.typeText("Sopralluogo pressa 4")
        app.buttons["diary-sheet-save"].firstMatch.click()

        XCTAssertTrue(entry.waitForExistence(timeout: 5), "il blocco non compare sulla giornata")
        XCTAssertTrue(
            waitForDiary { $0.contains("## Diario") && $0.contains("Sopralluogo pressa 4") },
            "il blocco non è finito nel file del giorno"
        )
    }

    // MARK: Support

    private var entry: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "diary-entry").firstMatch
    }

    /// Polls the diary file, because the write happens on the app's side of the process
    /// boundary and the diary saves on its own schedule.
    private func waitForDiary(timeout: TimeInterval = 6, _ condition: (String) -> Bool) -> Bool {
        let path = vault
            .appending(path: "Diario", directoryHint: .isDirectory)
            .appending(path: "\(compactToday).md", directoryHint: .notDirectory)
        return waitFor(timeout: timeout) {
            guard let text = try? String(contentsOf: path, encoding: .utf8) else { return false }
            return condition(text)
        }
    }

    private func waitFor(timeout: TimeInterval = 6, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return false
    }

    /// `20260814`, in the machine's own zone because `CalendarDate.today` is.
    private var compactToday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
