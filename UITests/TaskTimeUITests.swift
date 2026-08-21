import XCTest

/// The hour a task can carry on its dates (ADR-0004), and the block it can become on
/// the day it belongs to.
///
/// Its own class rather than more of `ComposerUITests`: that one is about where the
/// composers live and how they keep focus, this one about what the dates mean.
final class TaskTimeUITests: XCTestCase {
    private var vault: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory())
            .appending(path: "TaskTimeUITest-\(UUID().uuidString)")
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
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
    }

    private func toolbarButton(_ label: String, timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.toolbars.buttons[label]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "manca il pulsante «\(label)»")
        return element
    }

    private func show(_ pane: String) {
        let row = app.staticTexts[pane]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la sezione \(pane) non è nella barra laterale")
        row.click()
    }

    // MARK: The hour, and the block it can become

    /// A deadline can carry an hour (ADR-0004), and a task with an hour can also be
    /// planned into the day it belongs to - which is the whole point of asking.
    func testAScadenzaWithAnHourCanAlsoBecomeABlockOnItsDay() throws {
        show("Attività")
        toolbarButton("Cattura rapida", timeout: 15).click()
        let text = app.textFields["task-composer-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.click()
        text.typeText("Collaudo con orario")

        // The day, which closes the panel.
        let target = iso(daysFromToday: 2)
        app.buttons["task-composer-due"].click()
        let day = app.descendants(matching: .any).matching(identifier: "day-\(target)").firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5), "il calendario non mostra \(target)")
        day.click()

        // The hour, by reopening the chip: the row is live now that there is a date.
        app.buttons["task-composer-due"].click()
        let add = app.buttons["time-row-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "manca la riga dell'orario nel pannello Scadenza")
        add.click()
        app.buttons["due-panel-done"].click()

        // With an hour there is a question to ask, and it is asked in the composer.
        let block = app.checkBoxes["task-composer-block"]
        XCTAssertTrue(block.waitForExistence(timeout: 5), "non chiede se metterlo nell'orario del giorno")
        block.click()
        app.buttons["task-composer-create"].click()

        let written = captured(containing: "Collaudo con orario")
        XCTAssertTrue(
            written.contains("- [ ] Collaudo con orario !\(target) 09:00"),
            "la scadenza non porta l'orario: \(written)"
        )

        // And the block, in the daily note of that day.
        let compact = target.replacingOccurrences(of: "-", with: "")
        let daily = vault.appending(path: "Calendar/\(compact).md")
        var plan = ""
        for _ in 0..<20 {
            plan = (try? String(contentsOf: daily, encoding: .utf8)) ?? ""
            if plan.contains("## Timeline") { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(
            plan.contains("- 09:00-09:30 Collaudo con orario"),
            "il blocco non è nella nota del giorno: \(plan)"
        )
    }

    /// No hour, no question: a block is a span of a day, and a date alone says nothing
    /// about where on the day it goes.
    func testWithoutAnHourTheComposerDoesNotAskAboutTheTimeline() throws {
        show("Attività")
        toolbarButton("Cattura rapida", timeout: 15).click()
        let text = app.textFields["task-composer-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.click()
        text.typeText("Task senza orario")

        app.buttons["task-composer-scheduled"].click()
        let today = app.descendants(matching: .any).matching(identifier: "date-option-today").firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.click()

        XCTAssertFalse(
            app.checkBoxes["task-composer-block"].waitForExistence(timeout: 2),
            "chiede del blocco tempo per un task che non ha un orario"
        )
    }

    // MARK: Fixture

    /// In the machine's own zone, because `CalendarDate.today` is: in GMT this helper
    /// names yesterday for the two hours after local midnight, and the app does not.
    private func iso(daysFromToday days: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date())
    }

    /// The inbox note, once the line containing a phrase has reached it.
    private func captured(containing phrase: String) -> String {
        let inbox = vault.appending(path: "00 Inbox/Capture.md")
        var written = ""
        for _ in 0..<20 {
            written = (try? String(contentsOf: inbox, encoding: .utf8)) ?? ""
            if written.contains(phrase) { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return written
    }
}
