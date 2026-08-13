import XCTest

/// The two composers: a new note is named in the editor pane, and a task is composed
/// in a panel that carries its destination and its dates.
///
/// Both were floating windows, and the note one was the complaint: a sheet over the
/// window is not where you write. What a sheet is and is not can only be checked on
/// the running app, which is what puts these here rather than in the unit suite.
final class ComposerUITests: XCTestCase {
    private var vault: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try makeVault()

        app = XCUIApplication()
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")"]
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
            app.staticTexts["Nota composta.md"].waitForExistence(timeout: 5),
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

    func testTheTaskComposerCarriesTheDestinationAndTheThreeDates() throws {
        show("Attività")
        toolbarButton("Cattura rapida").click()

        let text = app.textFields["task-composer-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5), "il composer dei task non si è aperto")
        XCTAssertTrue(app.buttons["task-composer-destination"].exists, "manca la destinazione")
        for chip in ["scheduled", "due", "reminder"] {
            XCTAssertTrue(
                app.buttons["task-composer-\(chip)"].exists,
                "manca il campo data «\(chip)»"
            )
        }
        XCTAssertTrue(app.buttons["task-composer-create"].exists, "manca il pulsante Crea")
    }

    func testATaskComposedWithADateIsWrittenWithThatDate() throws {
        show("Attività")
        toolbarButton("Cattura rapida").click()

        let text = app.textFields["task-composer-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.click()
        text.typeText("Task dal composer")

        app.buttons["task-composer-scheduled"].click()
        let today = app.descendants(matching: .any).matching(identifier: "date-quick-0").firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5), "il popover della data non si è aperto")
        today.click()

        app.buttons["task-composer-create"].click()

        // In the note on disk, which is the only place a task exists.
        let inbox = vault.appending(path: "00 Inbox/Capture.md")
        var written = ""
        for _ in 0..<20 {
            written = (try? String(contentsOf: inbox, encoding: .utf8)) ?? ""
            if written.contains("Task dal composer") { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(written.contains("- [ ] Task dal composer >"), "il task non porta la data: \(written)")
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
        let today = app.descendants(matching: .any).matching(identifier: "date-quick-0").firstMatch
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

    func testTheTaskComposerOpensFromAPaneThatIsNotAttivita() throws {
        show("Conformità")
        // Through the menu, which is where the command lives: presented by the Attività
        // pane it did nothing at all from anywhere else.
        app.menuBars.menuItems["Nuovo task rapido"].click()
        XCTAssertTrue(
            app.textFields["task-composer-text"].waitForExistence(timeout: 5),
            "la cattura rapida non si apre fuori dalla sezione Attività"
        )
    }

    // MARK: Fixture

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
