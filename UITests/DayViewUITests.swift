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

        // Tasks for the day view's lists: one planned for today, one already done, one
        // falling due in three days. Written with today's dates so the views that
        // depend on "oggi" are exercised rather than merely rendered.
        try """
        ---
        date: 2026-08-13
        tags:
          - type-note
        ---

        - [ ] Task di oggi >\(isoToday())
        - [x] Task chiuso >\(isoToday()) @done(\(isoToday()))
        - [ ] Task in scadenza !\(isoToday(plus: 3)) 15:00
        """.write(
            to: vault.appending(path: "Attivita.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )

        app = XCUIApplication()
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
        app.staticTexts["Oggi"].firstMatch.click()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
    }

    /// In the machine's own zone, because `CalendarDate.today` is: formatted in GMT
    /// these helpers disagree with the app for the two hours after local midnight, and
    /// a test that only fails at night is worse than no test.
    private func isoToday(plus days: Int = 0) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
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
        formatter.timeZone = .current
        let today = formatter.string(from: Date())

        XCTAssertTrue(
            app.staticTexts[today].waitForExistence(timeout: 5),
            "l'intestazione non mostra \(today)"
        )
        let compact = today.replacingOccurrences(of: "/", with: "")
        let reversed = String(compact.suffix(4) + compact.prefix(4))
        XCTAssertFalse(app.staticTexts[reversed].exists, "l'intestazione mostra ancora la forma compatta")
    }

    // MARK: The toolbar's task controls

    /// Capture from the day one is looking at, without going to Attività for it.
    func testTheToolbarCapturesANewTask() throws {
        let button = app.toolbars.buttons["Nuovo task"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "manca il pulsante del nuovo task")
        button.click()
        XCTAssertTrue(
            app.textFields["task-composer-text"].waitForExistence(timeout: 5),
            "il pulsante non apre il composer"
        )
        app.typeKey(.escape, modifierFlags: [])
    }

    /// The bell used to create a reminder, which the Calendario menu already does. It
    /// is a filter now: what falls due next, listed and marked on the month.
    func testTheBellShowsWhatFallsDueNext() throws {
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "due-tasks-card").firstMatch.exists,
            "l'elenco delle scadenze è mostrato senza che sia stato chiesto"
        )

        let bell = app.toolbars.checkBoxes["Scadenze in arrivo"]
        XCTAssertTrue(bell.waitForExistence(timeout: 5), "manca il filtro delle scadenze")
        bell.click()

        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "due-tasks-card")
                .firstMatch.waitForExistence(timeout: 5),
            "il filtro non mostra le scadenze"
        )
        XCTAssertTrue(app.staticTexts["Task in scadenza"].exists, "il task con scadenza non è elencato")

        bell.click()
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "due-tasks-card")
                .firstMatch.waitForExistence(timeout: 2),
            "il filtro non si spegne"
        )
    }

    /// A day with a deadline on it is marked on the month, whether or not the filter
    /// is on: a deadline exists to be seen before it arrives.
    func testTheMonthMarksTheDaysSomethingIsDueOn() throws {
        let due = app.descendants(matching: .any)
            .matching(identifier: "due-dot-\(isoToday(plus: 3))").firstMatch
        XCTAssertTrue(due.waitForExistence(timeout: 5), "il giorno della scadenza non è segnato sul mese")
    }

    /// Completed tasks leave the day's list the moment they are ticked, which is right
    /// until one wants to see what got done.
    func testTheCompletedFilterBringsFinishedTasksBack() throws {
        XCTAssertTrue(app.staticTexts["Task di oggi"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Task chiuso"].exists, "i completati sono mostrati di default")

        let filter = app.toolbars.checkBoxes["Mostra completati"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "manca il filtro dei completati")
        filter.click()
        XCTAssertTrue(
            app.staticTexts["Task chiuso"].waitForExistence(timeout: 5),
            "il filtro non mostra i task completati"
        )
        filter.click()
    }

    /// The month grid, as one element rather than 42 cells.
    private var month: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "mini-calendar").firstMatch
    }
}
