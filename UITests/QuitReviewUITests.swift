import XCTest

/// Quitting with an unsaved note asks first (ADR-0073, R-18) - the one GUI test the chain
/// carries, justified in ADR-0073 §D9: the defect lived exactly where no in-process test
/// reaches, AppKit's terminate calling the delegate, which calls the review.
///
/// The alert's buttons are found by their titles: they are the contract here, the same words
/// the tab-close dialog uses (ADR-0012 §D3). Everything else goes by identifier or by the
/// note's own name. `-disableCalendar`, `-disableUpdater` and `-mailStoreRoot` as every
/// UI-test file passes them.
///
/// Probe P2 (ADR-0073 §D8) is the other reason this file exists: if `app.terminate()` in a
/// teardown reaches the delegate, a test that leaves a note dirty now meets the alert. This
/// test leaves nothing dirty - it ends with the app gone.
final class QuitReviewUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var mailStoreRoot: URL!
    private var app: XCUIApplication!

    private let typed = "Riga scritta prima di uscire."

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory()).appending(path: "QuitReviewUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try """
        ---
        date: 2026-09-29
        tags:
          - type-note
        ---

        Testo iniziale.
        """.write(to: noteURL, atomically: true, encoding: .utf8)

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
                               "-disableUpdater", "YES", "-disableContenitore", "YES",
                               "-stateBase", stateBase.path(percentEncoded: false)]
        app.launch()
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        if app?.state != .notRunning { app?.terminate() }
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
        try? FileManager.default.removeItem(at: mailStoreRoot)
    }

    private var noteURL: URL { vault.appending(path: "Uscita.md", directoryHint: .notDirectory) }

    func testQuittingWithAnUnsavedNoteAsksAndSalvaWritesIt() throws {
        let note = app.staticTexts["Uscita"]
        XCTAssertTrue(note.waitForExistence(timeout: 10), "la nota 'Uscita' non è nell'elenco")
        note.click()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "l'editor non c'è")
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("\n\(typed)")
        let saveChip = app.buttons["note-save-chip"]
        XCTAssertTrue(saveChip.waitForExistence(timeout: 5), "la nota non risulta modificata")

        // First quit: the question appears, and «Annulla» keeps the app and the edit.
        app.typeKey("q", modifierFlags: .command)
        let cancel = alertButton("Annulla")
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "uscire con una nota non salvata non ha chiesto niente")
        cancel.click()
        XCTAssertEqual(app.state, .runningForeground, "«Annulla» ha chiuso l'app")
        XCTAssertTrue(saveChip.waitForExistence(timeout: 5), "dopo «Annulla» la nota non è più modificata")
        XCTAssertFalse(try String(contentsOf: noteURL, encoding: .utf8).contains(typed), "«Annulla» ha scritto la nota")

        // Second quit: «Salva» writes the note, then the app exits.
        app.typeKey("q", modifierFlags: .command)
        let save = alertButton("Salva")
        XCTAssertTrue(save.waitForExistence(timeout: 5), "la seconda uscita non ha chiesto niente")
        save.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "dopo «Salva» l'app non è uscita")
        let written = try String(contentsOf: noteURL, encoding: .utf8)
        XCTAssertTrue(written.contains(typed), "«Salva» non ha scritto la nota")
    }

    /// A button of the quit alert: an app-modal `NSAlert` surfaces as a dialog, and a sheet is
    /// looked at too so the test does not depend on how AppKit exposes it.
    private func alertButton(_ title: String) -> XCUIElement {
        let inDialog = app.dialogs.buttons[title].firstMatch
        if inDialog.waitForExistence(timeout: 5) { return inDialog }
        return app.sheets.buttons[title].firstMatch
    }
}
