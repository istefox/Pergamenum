import XCTest

/// Creating a time block and undoing it, from both places that offer to.
///
/// A block has two faces - a line of markdown in the daily note and a box on the day's
/// timeline - and one click has to take away both. It did not: the x on the box was
/// built only while the pointer was over it, so the rebuild at mouse-down removed the
/// button between press and release and the block survived, in the note and on screen.
final class TimeBlockUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory()).appending(path: "TimeBlockUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

        // One task planned for today: the block is inserted from that row's context
        // menu, so without it there is nothing to block out.
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
        stateBase = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES",
                               "-stateBase", stateBase.path(percentEncoded: false)]
        app.launch()
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
        app.staticTexts["Oggi"].firstMatch.click()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
    }

    /// «Inserisci Blocco Tempo» is a context-menu entry on the task's row, not a button
    /// beside it: since ADR-0013 §D5 the ordinary way to block a task out is to drag it
    /// onto the hour you mean, and the button was taking a third of the row from the
    /// task it was about. The entry stays because a drag is invisible until somebody
    /// tries it.
    private func insertTimeBlockFromMenu(
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let row = app.staticTexts["Task di oggi"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "manca la riga del task", file: file, line: line)
        row.rightClick()

        let insert = app.menuItems["Inserisci Blocco Tempo"].firstMatch
        XCTAssertTrue(
            insert.waitForExistence(timeout: 5),
            "manca «Inserisci Blocco Tempo» nel menu della riga", file: file, line: line
        )
        insert.click()
    }

    /// "Blocca" read as blocking the task. The button says what it does, and what it
    /// makes can be undone from the note column as well as from the timeline.
    func testATimeBlockIsInsertedAndCanBeDeleted() throws {
        insertTimeBlockFromMenu()

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
        // The block is written to the file, not through the editor: no pane opens.
        XCTAssertTrue(
            app.buttons["Apri la nota di \(compactToday)"].exists,
            "inserire un blocco ha aperto la nota nell'editor"
        )

        let remove = app.descendants(matching: .any).matching(identifier: "remove-block").firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "il blocco non si può eliminare dalla nota")
        remove.click()

        assertNothingIsLeft(from: "il cestino della card")
    }

    /// The other way out: the x on the box itself, which is the one a person reaches
    /// for, since it sits on the thing they want gone.
    func testABlockIsDeletedFromTheTimelineToo() throws {
        insertTimeBlockFromMenu()

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
        // The editor the block opened closes with it: the note it wrote into holds
        // nothing else, and an empty pane under the task list is not a day's note.
        XCTAssertTrue(
            app.buttons["Apri la nota di \(compactToday)"].waitForExistence(timeout: 5),
            "\(source): il riquadro vuoto della nota è ancora aperto", line: line
        )
    }

    private var timelineBlock: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "timeline-block").firstMatch
    }

    /// Polls the daily note on disk until it satisfies `condition`, because the write
    /// happens on the app's side of the process boundary.
    private func waitForDailyNote(timeout: TimeInterval = 5, _ condition: (String) -> Bool) -> Bool {
        let path = vault
            .appending(path: "Calendar", directoryHint: .isDirectory)
            .appending(path: "\(compactToday).md", directoryHint: .notDirectory)

        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let text = try? String(contentsOf: path, encoding: .utf8), condition(text) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return false
    }

    /// `20260814`, the daily note's file name and the day named in the button that
    /// stands in for the editor when no note is open.
    private var compactToday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
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
