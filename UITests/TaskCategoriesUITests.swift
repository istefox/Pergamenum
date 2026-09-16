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
    }

    /// R-04, R-05: a registered category and an implicit one both show in the sidebar,
    /// and clicking the registered one opens its category view.
    func testTheCategoriesSectionShowsARegisteredAndAnImplicitRowAndOpensTheCategoryView() throws {
        show("Attività")

        let registeredRow = element("category-row-collaudi")
        XCTAssertTrue(registeredRow.waitForExistence(timeout: 10), "manca la riga della categoria registrata")

        let implicitRow = element("category-implicit-row-fantasma")
        XCTAssertTrue(implicitRow.waitForExistence(timeout: 5), "manca la riga della categoria implicita")

        registeredRow.click()

        let categoryView = element("category-view-collaudi")
        XCTAssertTrue(categoryView.waitForExistence(timeout: 5), "il click sulla riga non apre la vista categoria")
        XCTAssertTrue(
            app.staticTexts["Verifica pressione"].waitForExistence(timeout: 5),
            "la vista categoria non mostra il task diretto"
        )
    }
}
