import XCTest

/// The two hand checks of PG-144's G2 table (`docs/plans/pg-144-editor-coordinator-feature-controllers.md`)
/// that only a real, key window can prove, kept as GUI tests on purpose (ADR-0074, implementation
/// notes). Every other G2 row is pinned in-process.
///
/// - H10: typing in the find field never moves the keyboard into the note (the 2026-08-18
///   defect was a SwiftUI update cycle while typing, which only real key focus reproduces).
/// - H16: the Diario and Oggi panes host the same editor, and nothing else tests their wiring.
final class EditorHandCheckUITests: PergamenumUITestCase {
    private static let noteBody = "alfa beta alfa gamma alfa"

    override func setUpWithError() throws {
        try super.setUpWithError()
        try makeTemporaryVault(prefix: "EditorHandCheckUITest")
        try """
        ---
        date: 2026-09-30
        tags:
          - type-note
        ---

        \(Self.noteBody)
        """.write(
            to: vault.appending(path: "Nota di prova.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )

        launchApp()
        waitForMainWindow()
    }

    /// G2 H10. Each character goes to the field, none to the note, and Return steps through the
    /// matches. The note's source is read, never its rendered text (CLAUDE.md).
    func testTypingInTheFindFieldNeverMovesTheKeyboardIntoTheNote() {
        let note = app.staticTexts["Nota di prova"]
        XCTAssertTrue(note.waitForExistence(timeout: 10), "la nota non è nell'elenco")
        note.click()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "l'editor non c'è")
        XCTAssertTrue(waitUntil { self.text(of: editor).contains(Self.noteBody) }, "la nota non si è caricata")
        let before = text(of: editor)

        editor.click()
        app.typeKey("f", modifierFlags: .command)
        let field = app.textFields["find-query"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "il campo di ricerca non è apparso")
        field.typeText("alfa")

        XCTAssertEqual(field.value as? String, "alfa", "un carattere è finito fuori dal campo")
        XCTAssertEqual(text(of: editor), before, "la digitazione ha raggiunto la nota")

        let tally = app.staticTexts["find-tally"].firstMatch
        XCTAssertTrue(tally.waitForExistence(timeout: 5), "nessun conteggio delle corrispondenze")
        // A SwiftUI `Text` exposes its string as the element's value on macOS, not its label:
        // the label is empty before and after, so comparing it could never see a step.
        let first = text(of: tally)
        XCTAssertFalse(first.isEmpty, "il conteggio delle corrispondenze è vuoto")
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil { self.text(of: tally) != first }, "Invio non passa alla corrispondenza successiva")
        XCTAssertEqual(text(of: editor), before, "Invio ha modificato la nota")
    }

    /// G2 H16, Diario. A list item continues on Return in the diary's editor.
    func testTheDiaryEditorContinuesAList() {
        let row = sidebarRow("pane-diary")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "la voce Diario non c'è")
        row.click()
        assertListContinues(in: editor(identifiedBy: "diary-editor"), loadedWhen: { $0.contains("date:") })
    }

    /// G2 H16, Oggi. The same check in the day's own note.
    func testTheTodayEditorContinuesAList() {
        let row = sidebarRow("pane-today")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "la voce Oggi non c'è")
        row.click()
        let open = app.descendants(matching: .any).matching(identifier: "today-open-daily-note").firstMatch
        if open.waitForExistence(timeout: 3) { open.click() }
        assertListContinues(in: editor(identifiedBy: "today-editor"), loadedWhen: { $0.contains("date:") })
    }

    // MARK: - Helpers

    /// The text view behind an identified editor: SwiftUI may put the identifier on the text
    /// view itself or on the scroll view around it.
    private func editor(identifiedBy identifier: String) -> XCUIElement {
        let container = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(container.waitForExistence(timeout: 10), "\(identifier) non è apparso")
        if container.elementType == .textView { return container }
        let inner = container.descendants(matching: .textView).firstMatch
        XCTAssertTrue(inner.waitForExistence(timeout: 5), "\(identifier) non contiene un editor")
        return inner
    }

    /// Waits for the pane's own load first: the diary replaces its text when it loads, so a
    /// keystroke typed before that would be overwritten.
    private func assertListContinues(in editor: XCUIElement, loadedWhen loaded: @escaping (String) -> Bool) {
        XCTAssertTrue(waitUntil { loaded(self.text(of: editor)) }, "il riquadro non ha caricato la nota")
        editor.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("\n- uno\n")
        XCTAssertTrue(
            waitUntil { self.text(of: editor).hasSuffix("- uno\n- ") },
            "Invio non continua l'elenco: \(text(of: editor).suffix(40).debugDescription)"
        )
    }

    private func text(of element: XCUIElement) -> String { element.value as? String ?? "" }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return condition()
    }
}
