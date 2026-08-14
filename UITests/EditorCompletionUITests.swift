import XCTest

/// Typing a `#` at the start of a line, which is how a tag is written and how a heading
/// is written, and which used to take the app down.
///
/// Two separate faults have lived here. The first was an index trap in the completion
/// context, fixed for build 87. The second is this one: offering the completion from
/// `textDidChange` while the completion controller is itself inserting text, so the
/// insertion fires `textDidChange` again and the stack runs out. It is not specific to
/// the Diario pane - the Note editor is the same text view - so the test drives the
/// pane that has always had it.
final class EditorCompletionUITests: XCTestCase {
    private var vault: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory()).appending(path: "EditorCompletionUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try """
        ---
        date: 2026-08-14
        tags:
          - type-note
        ---

        Prima riga.
        """.write(
            to: vault.appending(path: "Nota.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )

        app = XCUIApplication()
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
    }

    func testTypingAHashAtTheStartOfALineDoesNotTakeTheAppDown() throws {
        app.staticTexts["Nota"].firstMatch.click()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "la nota non si è aperta")
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("\n## Titolo\n#area-training\n")

        // The assertion is that the app is still there to answer.
        XCTAssertTrue(
            app.staticTexts["Note"].waitForExistence(timeout: 5),
            "l'app non risponde più dopo aver scritto un # a inizio riga"
        )
        XCTAssertEqual(app.state, .runningForeground)
    }
}
