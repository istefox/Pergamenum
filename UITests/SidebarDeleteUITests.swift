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
/// item is found by its production title. The confirmation dialog's destructive button
/// carries its own identifier (`sidebar-trash-confirm`, PG-265).
final class SidebarDeleteUITests: PergamenumUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try makeVault()

        launchApp()
        waitForMainWindow()
    }

    func testDeletingANoteFromTheContextMenuRemovesItFromTheTreeAndTheVault() throws {
        let row = noteRow("DaEliminare.md")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la riga della nota non è comparsa")
        row.rightClick()

        let deleteItem = app.menuItems["Elimina…"]
        XCTAssertTrue(deleteItem.waitForExistence(timeout: 5), "manca la voce «Elimina…» nel menu")
        deleteItem.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "il dialogo di conferma non è comparso")
        // Scoped to the sheet, like the dialog it belongs to.
        let confirm = sheet.buttons["sidebar-trash-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "manca il bottone «Sposta nel Cestino»")
        confirm.click()

        XCTAssertTrue(waitForFile(vault.appending(path: "DaEliminare.md"), toExist: false),
                     "il file è ancora nel vault dopo la conferma di eliminazione")
        XCTAssertFalse(noteRow("DaEliminare.md").waitForExistence(timeout: 5),
                       "la riga è ancora nell'albero dopo l'eliminazione")
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
        try makeTemporaryVault(prefix: "SidebarDeleteUITest")
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
