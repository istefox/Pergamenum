import XCTest

/// The two hour windows of Impostazioni › Giornata, read off the grids they govern.
///
/// Driven through `.pergamenum/settings.json` rather than through the settings window:
/// that file is exactly what the panel writes, the panel's own controls are bound
/// straight to it, and driving the window instead would change which tab the installed
/// app opens on - the runner shares the app's real preference domain, and this suite
/// has no business touching it.
final class TimelineHoursUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var mailStoreRoot: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory()).appending(path: "HoursUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
        try? FileManager.default.removeItem(at: mailStoreRoot)
    }

    /// Each section draws its own window, and changing one leaves the other alone.
    func testEachSectionDrawsItsOwnHours() throws {
        try writeSettings(day: (9, 14), diary: (8, 18))
        launch()

        show("Diario")
        XCTAssertTrue(hourLine("08:00").waitForExistence(timeout: 5), "il Diario non parte dalle 08:00")
        XCTAssertFalse(hourLine("06:00").exists, "il Diario disegna ancora le 06:00")
        XCTAssertTrue(hourLine("18:00").exists, "il Diario non arriva alle 18:00")
        XCTAssertFalse(hourLine("19:00").exists, "il Diario va oltre le 18:00")

        show("Oggi")
        XCTAssertTrue(hourLine("09:00").waitForExistence(timeout: 5), "Oggi non parte dalle 09:00")
        XCTAssertFalse(hourLine("06:00").exists, "Oggi disegna ancora le 06:00")
        XCTAssertTrue(hourLine("14:00").exists, "Oggi non arriva alle 14:00")
        XCTAssertFalse(hourLine("15:00").exists, "Oggi va oltre le 14:00")
    }

    /// Without a settings file both fall back to what they always drew.
    func testTheDefaultsAreTheHoursTheSectionsAlwaysHad() throws {
        launch()

        show("Diario")
        XCTAssertTrue(hourLine("06:00").waitForExistence(timeout: 5), "il Diario non parte dalle 06:00")
        XCTAssertTrue(hourLine("24:00").exists, "il Diario non arriva a mezzanotte")

        show("Oggi")
        XCTAssertTrue(hourLine("06:00").waitForExistence(timeout: 5), "Oggi non parte dalle 06:00")
        XCTAssertTrue(hourLine("22:00").exists, "Oggi non arriva alle 22:00")
    }

    /// A block outside the window widens the grid rather than disappearing behind it:
    /// the setting says which hours are always drawn, not which hours may exist.
    func testABlockOutsideTheWindowIsStillDrawn() throws {
        try writeSettings(day: (9, 14), diary: (8, 18))
        try writeDiary("""
        ---
        date: \(isoToday())
        tags:
          - type-note
        ---

        ## Diario

        - 21:00-22:00 Serata
        """)
        launch()

        show("Diario")
        XCTAssertTrue(hourLine("22:00").waitForExistence(timeout: 5), "la griglia non si è allargata fino al blocco")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "diary-entry").firstMatch.exists,
            "il blocco fuori finestra non è disegnato"
        )
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

    private func writeSettings(day: (Int, Int), diary: (Int, Int)) throws {
        let directory = vault.appending(path: ".pergamenum", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        {
          "dailyFolder": "Calendar",
          "diaryFolder": "Diario",
          "copyDroppedFiles": true,
          "boardShowsGrid": true,
          "boardSnapsToGrid": false,
          "blockMinutes": 30,
          "dayHours": { "first": \(day.0), "last": \(day.1) },
          "diaryHours": { "first": \(diary.0), "last": \(diary.1) }
        }
        """.write(
            to: directory.appending(path: "settings.json", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
    }

    private func writeDiary(_ contents: String) throws {
        let folder = vault.appending(path: "Diario", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try contents.write(
            to: folder.appending(path: "\(compactToday).md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
    }

    private func show(_ pane: String) {
        let row = app.staticTexts[pane].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "manca la sezione \(pane)")
        row.click()
    }

    /// An hour label on either timeline. Both draw them as plain text in the gutter.
    private func hourLine(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value == %@", text)).firstMatch
    }

    /// In the machine's own zone, because `CalendarDate.today` is.
    private var compactToday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }

    private func isoToday() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
