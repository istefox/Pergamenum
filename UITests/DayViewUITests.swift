import XCTest

/// The day view's two adjustable parts: the "Vai a data" sheet, which now uses the
/// app's own calendar, and the month at the top of the column, which can be put away
/// and resized.
final class DayViewUITests: XCTestCase {
    private var vault: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory()).appending(path: "DayViewUITest-\(UUID().uuidString)")
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
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
        app.staticTexts["Oggi"].firstMatch.click()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
    }

    private func isoToday(plus days: Int = 0) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: calendar.date(byAdding: .day, value: days, to: Date()) ?? Date())
    }

    /// The sheet used SwiftUI's graphical picker, which draws `Aug 2026` and `Mo Tu We`
    /// in system blue inside an interface that is Italian and themed everywhere else.
    func testVaiADataUsesTheAppsOwnCalendar() throws {
        app.toolbars.buttons["Vai a data"].click()
        XCTAssertTrue(app.textFields["go-to-date-field"].waitForExistence(timeout: 5), "la sheet non si è aperta")

        let today = isoToday()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "day-\(today)").firstMatch.exists,
            "il calendario dell'app non è nella sheet"
        )
        XCTAssertTrue(app.buttons["month-back"].exists, "manca la navigazione del mese")
    }

    /// Picking a day and confirming moves the day the pane shows, which is the only
    /// thing the sheet is for.
    func testVaiADataMovesTheDay() throws {
        let target = isoToday(plus: 2)
        app.toolbars.buttons["Vai a data"].click()
        XCTAssertTrue(app.textFields["go-to-date-field"].waitForExistence(timeout: 5))

        let day = app.descendants(matching: .any).matching(identifier: "day-\(target)").firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5), "il giorno \(target) non è nel calendario")
        day.click()
        app.buttons["go-to-date-confirm"].click()

        let compact = target.replacingOccurrences(of: "-", with: "")
        XCTAssertTrue(
            app.staticTexts[compact].waitForExistence(timeout: 5),
            "la vista non si è spostata su \(compact)"
        )
    }

    /// A date typed into the field is read, so the sheet does not force a hunt through
    /// the months for a day that is far away.
    func testADateTypedIntoVaiADataIsRead() throws {
        app.toolbars.buttons["Vai a data"].click()
        let field = app.textFields["go-to-date-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("2027-03-05")
        app.buttons["go-to-date-confirm"].click()

        XCTAssertTrue(
            app.staticTexts["20270305"].waitForExistence(timeout: 5),
            "la data scritta a mano non ha spostato la vista"
        )
    }

    /// The month filled the column and could not be made smaller. It can now be put
    /// away, and the choice survives the pane being left and come back to.
    func testTheMonthCanBePutAwayAndComesBackPutAway() throws {
        let disclosure = app.buttons["month-disclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5), "manca il controllo del mese")
        XCTAssertTrue(month.exists, "il mese non è mostrato all'avvio")

        disclosure.click()
        XCTAssertFalse(month.waitForExistence(timeout: 2), "il mese è ancora lì dopo averlo chiuso")

        app.staticTexts["Note"].firstMatch.click()
        app.staticTexts["Oggi"].firstMatch.click()
        XCTAssertFalse(month.waitForExistence(timeout: 2), "il mese è tornato da solo")

        // And back, so the test leaves the preference as it found it.
        app.buttons["month-disclosure"].click()
        XCTAssertTrue(month.waitForExistence(timeout: 5), "il mese non si riapre")
    }

    /// The grip that sets the width is there and changes it.
    ///
    /// The drag goes whichever way has room and is undone at the end: the width is a
    /// real preference in the app's own defaults, so a test that left it at the minimum
    /// would both change what the user sees and make its own next run assert nothing.
    func testTheMonthWidthCanBeDragged() throws {
        let handle = app.descendants(matching: .any).matching(identifier: "month-resize").firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5), "manca la maniglia della larghezza")
        XCTAssertTrue(month.waitForExistence(timeout: 5))

        let before = month.frame.width
        let distance: CGFloat = before < 400 ? 80 : -80
        drag(handle, by: distance)

        let after = month.frame.width
        XCTAssertEqual(after, before + distance, accuracy: 8, "la maniglia non ha cambiato la larghezza")

        drag(handle, by: -distance)
        XCTAssertEqual(month.frame.width, before, accuracy: 8, "la larghezza non è tornata dov'era")
    }

    private func drag(_ element: XCUIElement, by dx: CGFloat) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: dx, dy: 0)))
    }

    /// The month grid, as one element rather than 42 cells.
    private var month: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "mini-calendar").firstMatch
    }
}
