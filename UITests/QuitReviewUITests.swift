import XCTest

/// Quitting with an unsaved note asks first (ADR-0073, R-18) - the one GUI test the chain
/// carries, justified in ADR-0073 §D9: the defect lived exactly where no in-process test
/// reaches, AppKit's terminate calling the delegate, which calls the review.
///
/// The alert's buttons are found by their accessibility identifiers (`quit-prompt-*`, ADR-0073
/// departure 18), not by their titles: prose grows (`CLAUDE.md`). The note is found by its
/// row's identifier, `note-row-Uscita.md` (PG-265). The isolation flags are
/// `PergamenumUITestCase`'s, as for every UI-test file.
///
/// Probe P2 (ADR-0073 §D8) is the other reason this file exists: if `app.terminate()` in a
/// teardown reaches the delegate, a test that leaves a note dirty now meets the alert. This
/// test leaves nothing dirty - it ends with the app gone.
final class QuitReviewUITests: PergamenumUITestCase {
    private let typed = "Riga scritta prima di uscire."

    override func setUpWithError() throws {
        try super.setUpWithError()
        try makeTemporaryVault(prefix: "QuitReviewUITest")
        try """
        ---
        date: 2026-09-29
        tags:
          - type-note
        ---

        Testo iniziale.
        """.write(to: noteURL, atomically: true, encoding: .utf8)

        launchApp()
        waitForMainWindow()
    }

    private var noteURL: URL { vault.appending(path: "Uscita.md", directoryHint: .notDirectory) }

    func testQuittingWithAnUnsavedNoteAsksAndSalvaWritesIt() throws {
        let note = noteRow("Uscita.md")
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
        let cancel = alertButton(identifier: "quit-prompt-cancel")
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "uscire con una nota non salvata non ha chiesto niente")
        cancel.click()
        XCTAssertEqual(app.state, .runningForeground, "«Annulla» ha chiuso l'app")
        XCTAssertTrue(saveChip.waitForExistence(timeout: 5), "dopo «Annulla» la nota non è più modificata")
        XCTAssertFalse(try String(contentsOf: noteURL, encoding: .utf8).contains(typed), "«Annulla» ha scritto la nota")

        // Second quit: «Salva» writes the note, then the app exits.
        app.typeKey("q", modifierFlags: .command)
        let save = alertButton(identifier: "quit-prompt-save")
        XCTAssertTrue(save.waitForExistence(timeout: 5), "la seconda uscita non ha chiesto niente")
        save.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "dopo «Salva» l'app non è uscita")
        let written = try String(contentsOf: noteURL, encoding: .utf8)
        XCTAssertTrue(written.contains(typed), "«Salva» non ha scritto la nota")
    }

    /// ADR-0089, PG-393 M1/M2: a diary day whose file moved on while it was being written asks at
    /// quit too, and neither «Annulla» nor «Non salvare» writes it. The wording, the order and the
    /// cancel's reveal are pinned in-process (`QuitReviewConflictTests`, `QuitCoordinatorTests`);
    /// what only a real window shows is AppKit's terminate reaching the review with a conflicted
    /// item and nothing else dirty. The day stands in for the board: both go through the same
    /// `QuitReview.diary`/`.board` path and a board needs a drag to dirty it. Like the test
    /// above, it ends with the app gone, so the teardown's `terminate()` meets no alert.
    func testQuittingWithAConflictedDiaryDayAsksAndWritesNothing() throws {
        openSidebarRow("pane-diary")
        let container = element("diary-editor")
        XCTAssertTrue(container.waitForExistence(timeout: 10), "l'editor del Diario non c'è")
        let editor = container.elementType == .textView
            ? container : container.descendants(matching: .textView).firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "il Diario non contiene un editor")
        // The diary replaces its text when it loads: a keystroke typed before that is overwritten.
        XCTAssertTrue(
            waitUntil { ((editor.value as? String) ?? "").contains("date:") },
            "il Diario non ha caricato la giornata"
        )
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("\nRiga del diario.")

        // Another writer rewrites the day file before the diary's own save: the buffer is dirty
        // and the file moved on, which is the conflict ADR-0057 names.
        let outside = "---\ndate: 2026-01-01\n---\n\nScritto da fuori.\n"
        try FileManager.default.createDirectory(at: dayFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try outside.write(to: dayFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(
            element("diary-conflict-banner").waitForExistence(timeout: 10),
            "il Diario non ha mostrato il conflitto di salvataggio"
        )

        // First quit: the question appears, and «Annulla» keeps the app, the banner and the file.
        app.typeKey("q", modifierFlags: .command)
        let cancel = alertButton(identifier: "quit-prompt-cancel")
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "uscire con un diario in conflitto non ha chiesto niente")
        cancel.click()
        XCTAssertEqual(app.state, .runningForeground, "«Annulla» ha chiuso l'app")
        XCTAssertTrue(element("diary-conflict-banner").waitForExistence(timeout: 5), "dopo «Annulla» il banner è sparito")
        XCTAssertEqual(try String(contentsOf: dayFile, encoding: .utf8), outside, "«Annulla» ha scritto il giorno")

        // Second quit: «Non salvare» lets the day go, writes nothing, and the app exits.
        app.typeKey("q", modifierFlags: .command)
        let discard = alertButton(identifier: "quit-prompt-discard")
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "la seconda uscita non ha chiesto niente")
        discard.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "dopo «Non salvare» l'app non è uscita")
        XCTAssertEqual(try String(contentsOf: dayFile, encoding: .utf8), outside, "«Non salvare» ha scritto il giorno")
    }

    /// The day's own file, `Diario/<yyyyMMdd>.md` in the machine's zone (`CalendarDate.today` is).
    private var dayFile: URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = .current
        return vault
            .appending(path: "Diario", directoryHint: .isDirectory)
            .appending(path: "\(formatter.string(from: Date())).md", directoryHint: .notDirectory)
    }

    private func waitUntil(timeout: TimeInterval = 6, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return false
    }

    /// A button of the quit alert, by the identifier `QuitReviewAlert.make` gives it
    /// (`quit-prompt-save`, `quit-prompt-cancel`, `quit-prompt-discard`): an app-modal `NSAlert`
    /// surfaces as a dialog, and a sheet is looked at too so the test does not depend on how
    /// AppKit exposes it.
    private func alertButton(identifier: String) -> XCUIElement {
        let inDialog = app.dialogs.buttons[identifier].firstMatch
        if inDialog.waitForExistence(timeout: 5) { return inDialog }
        return app.sheets.buttons[identifier].firstMatch
    }
}
