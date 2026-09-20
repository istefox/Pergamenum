import XCTest

/// The SPEC's single UI test for the category chain (ADR-0047, "Testing plan"): the
/// «Categorie» section shows a registered row and an implicit row, and clicking a row
/// opens the category view. The sidebar drag is not UI-tested while PG-162 is open; its
/// drop logic is Task 4's unit test (`Tests/TaskDropTests.swift`).
final class TaskCategoriesUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var mailStoreRoot: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory())
            .appending(path: "TaskCategoriesUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try writeFixture()

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

    private func show(_ pane: String) {
        let row = app.staticTexts[pane]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la sezione \(pane) non è nella barra laterale")
        row.click()
    }

    private func element(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// A task row carries no per-task identifier of its own (`TasksView.row` sets the same
    /// `"task-row"` on every one of them, folded into one combined accessibility element) -
    /// same trap and same fix as `WorkspaceIntegrationUITests.taskRow(containing:)`. Matched
    /// on its combined accessibility label instead, which carries `task.text` verbatim: this
    /// is content this test itself wrote, not prose the app could reword.
    private func taskRow(containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS[c] %@", "task-row", text))
            .firstMatch
    }

    /// One registered category ("Collaudi") and one task tagged with a slug the registry
    /// does not know about ("fantasma") - R-04's implicit row.
    private func writeFixture() throws {
        let pergamenumDirectory = vault.appending(path: ".pergamenum", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pergamenumDirectory, withIntermediateDirectories: true)
        try """
        {
          "version" : 1,
          "entries" : [
            {
              "slug" : "collaudi",
              "name" : "Collaudi",
              "color" : "verde",
              "order" : 0,
              "archived" : false
            }
          ]
        }
        """.write(
            to: pergamenumDirectory.appending(path: "categories.json", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
        try """
        ---
        date: 2026-08-13
        tags:
          - type-note
        ---

        # Collaudi

        - [ ] Verifica pressione #project-collaudi
        - [ ] Controllo residuo #project-fantasma
        """.write(
            to: vault.appending(path: "Collaudi.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
        // A second note with no category, the one PG-166's «Collega una nota…» picks.
        try """
        ---
        date: 2026-08-14
        tags:
          - type-note
        ---

        # Piano collaudi
        """.write(
            to: vault.appending(path: "Piano.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
    }

    /// R-04, R-05: a registered category and an implicit one both show in the sidebar,
    /// and clicking the registered one opens its category view.
    func testTheCategoriesSectionShowsARegisteredAndAnImplicitRowAndOpensTheCategoryView() throws {
        show("Attività")

        let registeredRow = element("category-row-collaudi")
        XCTAssertTrue(registeredRow.waitForExistence(timeout: 10), "manca la riga della categoria registrata")

        let implicitRow = element("category-implicit-row-fantasma")
        XCTAssertTrue(implicitRow.waitForExistence(timeout: 5), "manca la riga della categoria implicita")

        // A greedy `Color.clear` placeholder once let the row's height go unbounded and eat
        // the whole sidebar (the bug this height check pins down): a normal row's frame is
        // a couple of lines tall at most, never enough to reach halfway down the window.
        XCTAssertLessThan(
            registeredRow.frame.height, 60, "la riga della categoria registrata occupa troppo spazio verticale"
        )
        XCTAssertLessThan(
            implicitRow.frame.height, 60, "la riga della categoria implicita occupa troppo spazio verticale"
        )

        registeredRow.click()

        let categoryView = element("category-view-collaudi")
        XCTAssertTrue(categoryView.waitForExistence(timeout: 5), "il click sulla riga non apre la vista categoria")
        XCTAssertTrue(
            taskRow(containing: "Verifica pressione").waitForExistence(timeout: 5),
            "la vista categoria non mostra il task diretto"
        )
    }

    /// A defect where «Crea» stayed enabled with an empty slug and pressing it did
    /// nothing visible (the registry's refusal rendered as an empty sentence): the button
    /// must disable itself and name the reason under the slug field instead.
    func testCreaStaysDisabledWithAnEmptySlugAndNamesTheReason() throws {
        show("Attività")

        let addButton = element("category-add-button")
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "manca il bottone «Nuova categoria»")
        addButton.click()

        let nameField = element("category-editor-name")
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "manca il campo Nome del nuovo editor")
        nameField.click()
        nameField.typeText("Prova")

        let slugField = element("category-editor-slug")
        XCTAssertTrue(slugField.waitForExistence(timeout: 5), "manca il campo Slug")
        slugField.click()
        slugField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))

        let saveButton = element("category-editor-save")
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "manca il bottone di salvataggio")
        XCTAssertFalse(saveButton.isEnabled, "«Crea» resta attivo con lo slug vuoto")
        XCTAssertTrue(
            element("category-editor-slug-problem").waitForExistence(timeout: 5),
            "nessun avviso mostrato per lo slug vuoto"
        )
    }

    /// PG-166: a category with no home note offers «Collega una nota…», the picker writes
    /// the note's `pergamenum-category` key, and the view then offers «Vai alla nota».
    func testLinkingANoteFromTheCategoryViewMakesItTheHome() throws {
        show("Attività")
        element("category-row-collaudi").click()

        XCTAssertFalse(
            element("category-view-go-to-note").exists, "la categoria non dovrebbe avere ancora una nota"
        )
        let link = element("category-view-link-note")
        XCTAssertTrue(link.waitForExistence(timeout: 5), "manca «Collega una nota…» nella vista categoria")
        link.click()

        let row = element("category-note-picker-row-Piano.md")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "il picker non elenca la nota")
        row.click()

        XCTAssertTrue(
            element("category-view-go-to-note").waitForExistence(timeout: 10),
            "dopo il collegamento la vista non offre «Vai alla nota»"
        )
        let written = try String(contentsOf: vault.appending(path: "Piano.md"), encoding: .utf8)
        XCTAssertTrue(written.contains("pergamenum-category: collaudi"), "la chiave non è stata scritta sul file")
    }
}
