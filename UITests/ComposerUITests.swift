import XCTest

/// The two composers: a new note is named in the editor pane, and a task is composed
/// in a panel that carries its destination and its dates.
///
/// Both were floating windows, and the note one was the complaint: a sheet over the
/// window is not where you write. What a sheet is and is not can only be checked on
/// the running app, which is what puts these here rather than in the unit suite.
final class ComposerUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var mailStoreRoot: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try makeVault()

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

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
        try? FileManager.default.removeItem(at: mailStoreRoot)
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

    // MARK: New note

    func testANewNoteIsNamedInTheEditorAndNotInAFloatingWindow() throws {
        // The first test of the run meets a window that has just finished opening the
        // vault, so this one waits longer than the rest.
        toolbarButton("Nuova nota", timeout: 15).click()

        let title = app.textFields["new-note-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "il composer non è nella pagina di edit")
        // The whole point of the change: no sheet floats over the window while a note
        // is being named.
        XCTAssertEqual(app.sheets.count, 0, "la nuova nota apre ancora una finestra volante")

        title.click()
        title.typeText("Nota composta")
        app.typeKey(.enter, modifierFlags: [])

        // The composer gives way to the editor showing the note it just created.
        XCTAssertFalse(
            app.textFields["new-note-title"].waitForExistence(timeout: 2),
            "il composer è rimasto aperto dopo la creazione"
        )
        XCTAssertTrue(
            app.staticTexts["Nota composta"].waitForExistence(timeout: 5),
            "la nota creata non è aperta nell'editor"
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: vault.appending(path: "Nota composta.md").path(percentEncoded: false)
        ))
    }

    func testTheNewNoteComposerCanBeAbandoned() throws {
        toolbarButton("Nuova nota").click()
        let title = app.textFields["new-note-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        app.buttons["Annulla"].firstMatch.click()
        XCTAssertFalse(
            app.textFields["new-note-title"].waitForExistence(timeout: 2),
            "Annulla non ha chiuso il composer"
        )
    }

    // MARK: Task composer

    func testTheTaskComposerCarriesTheDestinationProgrammaAndScadenza() throws {
        show("Attività")
        toolbarButton("Cattura rapida").click()

        let text = app.textFields["task-composer-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5), "il composer dei task non si è aperto")
        XCTAssertTrue(app.buttons["task-composer-destination"].exists, "manca la destinazione")
        XCTAssertTrue(app.buttons["task-composer-scheduled"].exists, "manca il campo Programma")
        XCTAssertTrue(app.buttons["task-composer-due"].exists, "manca il campo Scadenza")
        XCTAssertTrue(app.buttons["task-composer-create"].exists, "manca il pulsante Crea")

        // The reminder is inside the Programma panel now, not a third chip of its own.
        XCTAssertFalse(app.buttons["task-composer-reminder"].exists, "il promemoria è ancora un campo a sé")
    }

    /// The panel of the screenshot: a field, the quick choices with the day beside
    /// each, the calendar one row down, and the reminder and the repetition below.
    func testTheProgrammaPanelListsTheQuickChoicesAndTheExtras() throws {
        show("Attività")
        toolbarButton("Cattura rapida").click()
        XCTAssertTrue(app.textFields["task-composer-text"].waitForExistence(timeout: 5))
        app.buttons["task-composer-scheduled"].click()

        XCTAssertTrue(app.textFields["date-panel-field"].waitForExistence(timeout: 5), "manca il campo del pannello")
        for option in ["today", "tomorrow", "next-week", "two-weeks", "three-weeks", "one-month", "choose"] {
            XCTAssertTrue(
                app.descendants(matching: .any).matching(identifier: "date-option-\(option)").firstMatch.exists,
                "manca la scelta «\(option)» nel pannello Programma"
            )
        }
        for extra in ["remind", "repeat"] {
            XCTAssertTrue(
                app.descendants(matching: .any).matching(identifier: "date-option-\(extra)").firstMatch.exists,
                "manca la riga «\(extra)» in fondo al pannello"
            )
        }
    }

    /// The reminder moved inside the Programma panel, where Craft keeps it. It has to
    /// still reach the line, which is the only place a reminder exists.
    func testTheReminderSetInsideTheProgrammaPanelReachesTheLine() throws {
        show("Attività")
        toolbarButton("Cattura rapida").click()
        let text = app.textFields["task-composer-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.click()
        text.typeText("Task con promemoria")

        app.buttons["task-composer-scheduled"].click()
        let today = app.descendants(matching: .any).matching(identifier: "date-option-today").firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.click()

        app.buttons["task-composer-scheduled"].click()
        let remind = app.descendants(matching: .any).matching(identifier: "date-option-remind").firstMatch
        XCTAssertTrue(remind.waitForExistence(timeout: 5))
        remind.click()
        let done = app.buttons["reminder-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "la pagina del promemoria non si è aperta")
        done.click()

        app.buttons["task-composer-create"].click()
        let written = captured(containing: "Task con promemoria")
        XCTAssertTrue(
            written.contains("@remind(\(iso(daysFromToday: 0))"),
            "il promemoria non è finito sulla riga: \(written)"
        )
    }

    /// "Fra 2 settimane" is one of the choices added to Craft's three, and the day it
    /// writes is the one the panel promised.
    func testAChoiceFurtherOutWritesTheDayItNames() throws {
        show("Attività")
        toolbarButton("Cattura rapida").click()
        let text = app.textFields["task-composer-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.click()
        text.typeText("Task fra due settimane")

        app.buttons["task-composer-scheduled"].click()
        let twoWeeks = app.descendants(matching: .any).matching(identifier: "date-option-two-weeks").firstMatch
        XCTAssertTrue(twoWeeks.waitForExistence(timeout: 5))
        twoWeeks.click()
        app.buttons["task-composer-create"].click()

        let expected = iso(daysFromToday: 14)
        XCTAssertTrue(
            captured(containing: "Task fra due settimane").contains("- [ ] Task fra due settimane >\(expected)"),
            "il task non porta il giorno promesso dalla riga: \(captured(containing: "Task fra due settimane"))"
        )
    }

    /// Scadenza opens on a calendar and writes `!`, which is a different marker from
    /// the one Programma writes.
    func testTheScadenzaPanelIsACalendarAndWritesTheDueMarker() throws {
        show("Attività")
        toolbarButton("Cattura rapida").click()
        let text = app.textFields["task-composer-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.click()
        text.typeText("Task con scadenza")

        app.buttons["task-composer-due"].click()
        XCTAssertTrue(app.textFields["due-panel-field"].waitForExistence(timeout: 5), "manca il campo Scadenza")

        let target = iso(daysFromToday: 3)
        let day = app.descendants(matching: .any).matching(identifier: "day-\(target)").firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5), "il calendario non mostra il giorno \(target)")
        day.click()
        // Picking a day dismisses the popover (DuePanel's onDone), and clicking "Crea"
        // while it is still animating out can land on the closing popover instead of
        // the button underneath, silently dropping the click (PG-072). Wait for the
        // panel to actually be gone first.
        XCTAssertTrue(
            app.textFields["due-panel-field"].waitForNonExistence(timeout: 5),
            "il pannello Scadenza non si è chiuso dopo aver scelto il giorno"
        )
        app.buttons["task-composer-create"].click()

        let written = captured(containing: "Task con scadenza")
        XCTAssertTrue(written.contains("- [ ] Task con scadenza !\(target)"), "manca il marcatore di scadenza: \(written)")
        XCTAssertFalse(written.contains(">\(target)"), "la scadenza ha scritto anche la data pianificata")
    }

    func testATaskComposedWithADateIsWrittenWithThatDate() throws {
        show("Attività")
        toolbarButton("Cattura rapida").click()

        let text = app.textFields["task-composer-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.click()
        text.typeText("Task dal composer")

        app.buttons["task-composer-scheduled"].click()
        let quickToday = app.descendants(matching: .any).matching(identifier: "date-option-today").firstMatch
        XCTAssertTrue(quickToday.waitForExistence(timeout: 5), "il pannello Programma non si è aperto")
        quickToday.click()

        app.buttons["task-composer-create"].click()

        // In the note on disk, which is the only place a task exists.
        let written = captured(containing: "Task dal composer")
        XCTAssertTrue(
            written.contains("- [ ] Task dal composer >\(iso(daysFromToday: 0))"),
            "il task non porta la data programmata: \(written)"
        )
    }

    /// Setting a date used to cost the text: SwiftUI gave focus back to the field by
    /// selecting all of it, so the next keystroke replaced the task instead of
    /// continuing it. Typing after a date is the only way to see that.
    func testTypingAfterChoosingADateContinuesTheTextInsteadOfReplacingIt() throws {
        show("Attività")
        toolbarButton("Cattura rapida").click()

        let text = app.textFields["task-composer-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.click()
        text.typeText("Primo pezzo")

        app.buttons["task-composer-scheduled"].click()
        let today = app.descendants(matching: .any).matching(identifier: "date-option-today").firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.click()

        app.typeText(" e secondo")
        app.buttons["task-composer-create"].click()

        let inbox = vault.appending(path: "00 Inbox/Capture.md")
        var written = ""
        for _ in 0..<20 {
            written = (try? String(contentsOf: inbox, encoding: .utf8)) ?? ""
            if written.contains("Primo pezzo") { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(
            written.contains("- [ ] Primo pezzo e secondo >"),
            "il testo scritto prima della data è stato perso: \(written)"
        )
    }

    /// Captured from the Note pane, the task lands in Inbox - a view Attività does not
    /// open on. Arriving there afterwards has to show it, or the capture reads as lost.
    func testAttivitaOpensOnTheViewTheCapturedTaskLandedIn() throws {
        app.menuBars.menuItems["Nuovo task rapido"].click()
        let text = app.textFields["task-composer-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.click()
        text.typeText("Task catturato da Note")
        app.buttons["task-composer-create"].click()

        show("Attività")
        let row = app.descendants(matching: .any).matching(identifier: "task-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "la sezione non si è messa sulla vista del task")
        XCTAssertTrue(
            app.staticTexts["Inbox"].exists,
            "il task senza scadenza è in Inbox, ma la vista mostrata è un'altra"
        )
    }

    func testTheTaskComposerOpensFromAPaneThatIsNotAttivita() throws {
        show("Tag")
        // Through the menu, which is where the command lives: presented by the Attività
        // pane it did nothing at all from anywhere else.
        app.menuBars.menuItems["Nuovo task rapido"].click()
        XCTAssertTrue(
            app.textFields["task-composer-text"].waitForExistence(timeout: 5),
            "la cattura rapida non si apre fuori dalla sezione Attività"
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

    private func makeVault() throws {
        vault = URL(filePath: NSTemporaryDirectory())
            .appending(path: "ComposerUITest-\(UUID().uuidString)")
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
    }
}
