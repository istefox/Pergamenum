import XCTest

/// «Elimina…» → «Sposta nel Cestino» on a note row in the sidebar (Note pane, not
/// Workspace) actually removes it, not just closes the dialog.
///
/// Regression for the bug where `deleting` (a `@State`) was read *inside* the
/// confirmation button's `Task`, after the `isPresented` binding's own setter had
/// already nilled it on dismissal - the trash call was silently skipped, no alert shown,
/// the row stayed in the tree, and nothing landed in the Finder Trash. Fixed by
/// `.confirmationDialog(..., presenting: deleting) { note in ... }`, the same shape
/// `WorkspaceBrowser`'s own delete dialog already used.
///
/// Row lookup and menu-item lookup follow `SidebarMoveUITests`'s documented convention:
/// the note row itself carries an `accessibilityIdentifier`, but a `.contextMenu`'s
/// entries are `NSMenuItem`s outside that row's accessibility hierarchy, so the menu
/// item and the confirmation dialog's buttons are found by their production title.
final class SidebarDeleteUITests: XCTestCase {
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
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10), "il vault non si è aperto")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
        try? FileManager.default.removeItem(at: mailStoreRoot)
    }

    func testDeletingANoteFromTheContextMenuRemovesItFromTheTreeAndTheVault() throws {
        let row = noteRow("note-row-DaEliminare.md")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la riga della nota non è comparsa")
        row.rightClick()

        let deleteItem = app.menuItems["Elimina…"]
        XCTAssertTrue(deleteItem.waitForExistence(timeout: 5), "manca la voce «Elimina…» nel menu")
        deleteItem.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "il dialogo di conferma non è comparso")
        // Scoped to the sheet, not `app.buttons[...]`: the destructive button's title also
        // matches other, unrelated controls in the wider accessibility tree.
        let confirm = sheet.buttons["Sposta nel Cestino"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "manca il bottone «Sposta nel Cestino»")
        confirm.click()

        XCTAssertTrue(waitForFile(vault.appending(path: "DaEliminare.md"), toExist: false),
                     "il file è ancora nel vault dopo la conferma di eliminazione")
        XCTAssertFalse(noteRow("note-row-DaEliminare.md").waitForExistence(timeout: 5),
                       "la riga è ancora nell'albero dopo l'eliminazione")
    }

    // MARK: Navigation

    private func noteRow(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    // MARK: Reading the result off disk

    private func waitForFile(_ url: URL, toExist expected: Bool, timeout: TimeInterval = 6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) == expected {
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) == expected
    }

    // MARK: Fixture

    private func makeVault() throws {
        vault = URL(filePath: NSTemporaryDirectory())
            .appending(path: "SidebarDeleteUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try writeNote("Da Eliminare", at: "DaEliminare.md")
    }

    private func writeNote(_ title: String, at relativePath: String) throws {
        let note = """
        ---
        date: 2026-08-27
        tags:
          - type-nota
        ---

        # \(title)

        Corpo della nota \(title).
        """
        try note.write(
            to: vault.appending(path: relativePath, directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
    }
}
