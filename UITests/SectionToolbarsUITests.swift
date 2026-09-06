import XCTest

/// Every section carries its own toolbar.
///
/// Until now exactly one view in the app declared a `.toolbar`, so four of the five
/// panes showed an empty strip where their commands should have been. A toolbar is
/// visible or it is nothing, which is what makes this a UI test and not a unit one.
final class SectionToolbarsUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try makeVault()

        app = XCUIApplication()
        stateBase = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES",
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
    }

    /// Clicks a pane in the sidebar and waits for it to be showing.
    private func show(_ pane: String) {
        let row = app.staticTexts[pane]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la sezione \(pane) non è nella barra laterale")
        row.click()
    }

    /// A button in the window's toolbar.
    ///
    /// Scoped to the toolbar rather than to the whole app: the Oggi pane's "Oggi"
    /// button and the sidebar's own "Oggi" row both answer to that name, and an
    /// app-wide query cannot say which one it found.
    private func button(_ label: String, timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.toolbars.buttons[label]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "manca il pulsante «\(label)»")
        return element
    }

    /// A toolbar toggle, which AppKit reports as a checkbox rather than as a button.
    private func toggle(_ label: String, timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.checkBoxes[label]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "manca l'interruttore «\(label)»")
        return element
    }

    func testTheNoteSectionCarriesItsCommands() throws {
        for label in ["Nuova nota", "Vai alla nota", "Ricerca globale"] {
            XCTAssertTrue(button(label).exists, "«\(label)» non è nella toolbar della sezione Note")
        }
        // «Ispettore» è un Toggle, non un Button (2026-08-28, parità toolbar Note/Workspace):
        // AppKit lo riporta come checkbox, esattamente come «Nuovi elementi» in Workspace.
        for label in ["Ispettore", "Concentrazione", "Albero"] {
            XCTAssertTrue(toggle(label).exists, "manca l'interruttore «\(label)» nella sezione Note")
        }
    }

    func testTheOggiSectionCarriesTheCalendarCommands() throws {
        show("Oggi")
        // "Nuovo evento" is there whether or not EventKit has been granted: a control
        // that disappears leaves the user hunting for a feature they were told exists.
        for label in ["Giorno precedente", "Giorno successivo", "Vai a data",
                      "Aggiorna da EventKit", "Nuovo evento", "Nuovo task"] {
            XCTAssertTrue(button(label).exists, "«\(label)» non è nella toolbar della sezione Oggi")
        }
        // The bell became a filter, so the toolbar no longer creates a reminder. The
        // command it used to duplicate is still in the Calendario menu, keys and all.
        XCTAssertFalse(
            app.toolbars.buttons["Nuovo promemoria"].exists,
            "il campanello crea ancora un promemoria invece di filtrare"
        )
        XCTAssertTrue(
            app.menuBars.menuItems["Nuovo promemoria"].exists,
            "«Nuovo promemoria» è sparito anche dal menu Calendario"
        )
        for label in ["Scadenze in arrivo", "Mostra completati"] {
            XCTAssertTrue(toggle(label).exists, "manca il filtro «\(label)»")
        }

        // And it acts on the day the pane is showing, which is the whole reason for
        // putting it here rather than leaving it in the menu.
        button("Giorno successivo").click()
        XCTAssertTrue(button("Oggi").isEnabled, "«Oggi» è ancora disattivato: il giorno non è cambiato")
        button("Oggi").click()
        XCTAssertFalse(button("Oggi").isEnabled, "il ritorno a oggi non ha avuto effetto")
    }

    func testTheAttivitaSectionCarriesTheTaskCommands() throws {
        show("Attività")
        XCTAssertTrue(button("Cattura rapida").exists)

        // The four actions on a task are there and refuse to act on nothing: with no
        // row selected they would otherwise be four buttons that silently do nothing.
        for label in ["Completa o riapri", "Pianifica oggi", "Collega nota o board", "Vai alla nota di origine"] {
            XCTAssertFalse(button(label).isEnabled, "«\(label)» è attivo senza un task selezionato")
        }

        let row = app.descendants(matching: .any).matching(identifier: "task-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "il task della nota di prova non è nell'elenco")
        row.click()
        XCTAssertTrue(button("Completa o riapri").isEnabled, "il task selezionato non ha attivato il pulsante")
    }

    func testTheConformitaSectionRunsTheLinterFromTheToolbar() throws {
        show("Conformità")
        XCTAssertTrue(app.staticTexts["Nessuna verifica eseguita."].waitForExistence(timeout: 5))

        button("Verifica ora").click()
        // The fixture note has no frontmatter at all, so the linter has something to
        // report and "nothing ran" cannot be mistaken for "everything is conformant".
        XCTAssertTrue(
            app.staticTexts["1 note non conformi su 1"].waitForExistence(timeout: 10),
            "il linter non ha prodotto un esito"
        )
    }

    func testTheWorkspaceSectionCarriesTheBoardCommands() throws {
        show("Workspace")
        for label in ["Annulla", "Ripeti", "Anteprima"] {
            XCTAssertTrue(
                button(label, timeout: 10).exists,
                "«\(label)» non è nella toolbar della sezione Workspace"
            )
        }
        XCTAssertTrue(toggle("Nuovi elementi").exists)

        // Nothing has been done to the board yet, so neither can fire.
        XCTAssertFalse(button("Annulla").isEnabled)
        XCTAssertFalse(button("Ripeti").isEnabled)
    }

    // MARK: Fixture

    private func makeVault() throws {
        vault = URL(filePath: NSTemporaryDirectory())
            .appending(path: "ToolbarUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

        // Scheduled for today, because the Attività pane opens on the Oggi view and an
        // undated task lives in Inbox: a fixture that is never on screen would fail the
        // test for a reason that has nothing to do with the toolbar.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        // Deliberately non-conformant - no frontmatter - so the linter has something
        // to find.
        try """
        # Nota di prova

        - [ ] un task da fare >\(today)
        """.write(
            to: vault.appending(path: "Nota di prova.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
    }
}
