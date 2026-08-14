import XCTest

/// Creating a time block and undoing it, from both places that offer to.
///
/// A block has two faces - a line of markdown in the daily note and a box on the day's
/// timeline - and one click has to take away both. It did not: the x on the box was
/// built only while the pointer was over it, so the rebuild at mouse-down removed the
/// button between press and release and the block survived, in the note and on screen.
final class TimeBlockUITests: XCTestCase {
    private var vault: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory()).appending(path: "TimeBlockUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

        // One task planned for today: "Inserisci Blocco Tempo" sits on a task row, so
        // without it there is nothing to block out.
        try """
        ---
        date: 2026-08-13
        tags:
          - type-note
        ---

        - [ ] Task di oggi >\(isoToday())
        """.write(
            to: vault.appending(path: "Attivita.md", directoryHint: .notDirectory),
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

    /// "Blocca" read as blocking the task. The button says what it does, and what it
    /// makes can be undone from the note column as well as from the timeline.
    func testATimeBlockIsInsertedAndCanBeDeleted() throws {
        let insert = app.buttons["insert-time-block"].firstMatch
        XCTAssertTrue(insert.waitForExistence(timeout: 5), "manca «Inserisci Blocco Tempo»")
        XCTAssertEqual(insert.label, "Inserisci Blocco Tempo", "il pulsante ha ancora il vecchio nome")
        insert.click()

        let blocks = app.descendants(matching: .any).matching(identifier: "blocks-card").firstMatch
        XCTAssertTrue(blocks.waitForExistence(timeout: 5), "il blocco non compare nella colonna della nota")
        XCTAssertTrue(
            waitForDailyNote { $0.contains("## Timeline") },
            "il blocco non è finito nella nota del giorno"
        )
        XCTAssertTrue(
            timelineBlock.waitForExistence(timeout: 5),
            "il blocco non compare sulla timeline"
        )

        let remove = app.descendants(matching: .any).matching(identifier: "remove-block").firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "il blocco non si può eliminare dalla nota")
        remove.click()

        assertNothingIsLeft(from: "il cestino della card")
    }

    /// The other way out: the x on the box itself, which is the one a person reaches
    /// for, since it sits on the thing they want gone.
    func testABlockIsDeletedFromTheTimelineToo() throws {
        let insert = app.buttons["insert-time-block"].firstMatch
        XCTAssertTrue(insert.waitForExistence(timeout: 5), "manca «Inserisci Blocco Tempo»")
        insert.click()

        XCTAssertTrue(timelineBlock.waitForExistence(timeout: 5), "il blocco non compare sulla timeline")
        XCTAssertTrue(waitForDailyNote { $0.contains("## Timeline") }, "il blocco non è nella nota")

        timelineBlock.hover()
        let remove = app.buttons["timeline-remove-block"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "manca la x sul blocco")
        remove.click()

        assertNothingIsLeft(from: "la x sul blocco")
    }

    /// Every trace of the block, wherever the click came from: the markdown section, the
    /// box on the timeline, the card in the note column.
    private func assertNothingIsLeft(from source: String, line: UInt = #line) {
        XCTAssertTrue(
            waitForDailyNote { !$0.contains("## Timeline") },
            "\(source): la nota conserva la sezione", line: line
        )
        XCTAssertFalse(
            timelineBlock.waitForExistence(timeout: 2),
            "\(source): il blocco è ancora disegnato sulla timeline", line: line
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "blocks-card")
                .firstMatch.waitForExistence(timeout: 2),
            "\(source): la card BLOCCHI TEMPO è ancora lì", line: line
        )
    }

    private var timelineBlock: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "timeline-block").firstMatch
    }

    /// Polls the daily note on disk until it satisfies `condition`, because the write
    /// happens on the app's side of the process boundary.
    private func waitForDailyNote(timeout: TimeInterval = 5, _ condition: (String) -> Bool) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = .current
        let path = vault
            .appending(path: "Calendar", directoryHint: .isDirectory)
            .appending(path: "\(formatter.string(from: Date())).md", directoryHint: .notDirectory)

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let text = try? String(contentsOf: path, encoding: .utf8), condition(text) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return false
    }

    /// In the machine's own zone, because `CalendarDate.today` is.
    private func isoToday(plus days: Int = 0) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: calendar.date(byAdding: .day, value: days, to: Date()) ?? Date())
    }
}
