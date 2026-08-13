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

        let parts = target.split(separator: "-")
        let shown = "\(parts[2])/\(parts[1])/\(parts[0])"
        XCTAssertTrue(
            app.staticTexts[shown].waitForExistence(timeout: 5),
            "la vista non si è spostata su \(shown)"
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
            app.staticTexts["05/03/2027"].waitForExistence(timeout: 5),
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

    /// The month is sized by the column, not by a grip of its own: dragging the
    /// divider that gives room to the timeline resizes it too.
    func testTheMonthFollowsTheDividerAndHasNoGripOfItsOwn() throws {
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "month-resize").firstMatch.exists,
            "la maniglia è ancora lì"
        )

        let before = month.frame.width

        // The splitter picked by where it is, not by index: `app.splitGroups.firstMatch`
        // is the window's own sidebar split, and dragging that collapsed the sidebar -
        // a state the app remembers, so every later launch started without it.
        let dividers = app.descendants(matching: .splitter).allElementsBoundByIndex
        guard let divider = dividers.first(where: { $0.frame.minX > 400 }) else {
            return XCTFail("non trovo il divisorio fra colonna e timeline")
        }

        // Rightwards: the timeline opens at its widest, so there is only room the other
        // way, and a drag that cannot move anything proves nothing.
        let grab = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grab.press(forDuration: 0.2, thenDragTo: grab.withOffset(CGVector(dx: 160, dy: 0)))

        XCTAssertGreaterThan(month.frame.width, before, "allargando la colonna il mese non è cresciuto")
        XCTAssertTrue(app.staticTexts["Note"].exists, "la trascinata ha preso il divisorio sbagliato")

        // Put it back, so the next test starts where this one did.
        let moved = app.descendants(matching: .splitter).allElementsBoundByIndex
            .first { $0.frame.minX > 400 } ?? divider
        let back = moved.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        back.press(forDuration: 0.2, thenDragTo: back.withOffset(CGVector(dx: -160, dy: 0)))
    }

    /// The header showed `20260813`, which is the file name, not a date.
    func testTheHeaderShowsTheDateTheItalianWay() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let today = formatter.string(from: Date())

        XCTAssertTrue(
            app.staticTexts[today].waitForExistence(timeout: 5),
            "l'intestazione non mostra \(today)"
        )
        let compact = today.replacingOccurrences(of: "/", with: "")
        let reversed = String(compact.suffix(4) + compact.prefix(4))
        XCTAssertFalse(app.staticTexts[reversed].exists, "l'intestazione mostra ancora la forma compatta")
    }

    /// The month grid, as one element rather than 42 cells.
    private var month: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "mini-calendar").firstMatch
    }
}
