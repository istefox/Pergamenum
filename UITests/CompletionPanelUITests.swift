import XCTest

/// The editor at the bottom of a long note, which is where three separate complaints
/// landed on 2026-08-18: a click on the last line jumping the caret up the note, typing
/// under the last heading producing nothing, and the completion panel opening away from
/// the caret.
///
/// Here rather than in the unit suite because none of it is about the rule: the rule is
/// covered, green, and was green while all three happened. What is in question is the
/// running app - hit testing, first responder, and where a floating panel lands - and
/// only a real window has those.
final class CompletionPanelUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory()).appending(path: "CompletionPanelUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

        var lines = ["---", "date: 2026-08-18", "tags:", "  - type-note", "---", "", "# In fondo alla pagina", ""]
        for index in 1...40 {
            lines.append("Riga di riempimento numero \(index), senza altro scopo che occupare spazio.")
            lines.append("")
        }
        lines += ["## Prova qui sotto", "", "Ultima riga della nota.", ""]
        try lines.joined(separator: "\n").write(
            to: vault.appending(path: "Lunga.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
        try """
        # Prove in laboratorio

        Tre serie di misure.

        ## Campioni

        Tre campioni.

        ### Durezza

        A freddo.

        ## Strumenti

        Un fonometro.
        """.write(
            to: vault.appending(path: "Prove in laboratorio.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )

        app = XCUIApplication()
        stateBase = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES",
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

    /// Puts a screenshot in the result bundle.
    ///
    /// Not a file in the runner's temporary directory, which is the obvious move and is a
    /// dead end: that directory lives inside the runner's container and is not readable
    /// from outside it, not even with the sandbox off. An attachment travels in the
    /// `.xcresult` instead, which anything can open.
    private func keep(_ name: String) {
        let attachment = XCTAttachment(image: app.screenshot().image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openTheLongNote() -> XCUIElement {
        app.staticTexts["Lunga"].firstMatch.click()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "la nota non si è aperta")
        return editor
    }

    func testAHashInsideAWikilinkOffersTheHeadingsOfThatNote() throws {
        let editor = openTheLongNote()
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("\n[[Prove in laboratorio#")
        keep("04-sections-of-the-linked-note")

        // Every heading that note has, its title included: the title is a heading like the
        // others and `Transclusion.excerpt` can find it, so offering it is the promise the
        // completion makes (ADR-0010 §D5).
        for heading in ["Prove in laboratorio", "Campioni", "Durezza", "Strumenti"] {
            XCTAssertTrue(
                app.staticTexts[heading].waitForExistence(timeout: 3),
                "il pannello non offre la sezione «\(heading)»"
            )
        }
    }

    func testAColonOffersEmojiByName() throws {
        let editor = openTheLongNote()
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("\n:")
        // The one thing the panel has to say about itself: that typing narrows it. A search
        // row at the top said it too and duplicated the query the note already shows beside
        // the caret, so it lives in the footer, which never moves.
        XCTAssertTrue(
            app.staticTexts["scrivi per filtrare"].waitForExistence(timeout: 3),
            "il pannello non dice che digitando si filtra"
        )

        editor.typeText("bers")
        keep("05-emoji-on-a-colon")

        // The name is what the row shows, and it is what XCUI can read - the glyph beside it
        // is drawn, not labelled. Seeing the name proves the catalogue reached the panel;
        // that the glyph is drawn is what the screenshot is for.
        XCTAssertTrue(
            app.staticTexts["bersaglio"].waitForExistence(timeout: 3),
            "il pannello non offre l'emoji cercata"
        )

        app.typeKey(.enter, modifierFlags: [])
        let text = editor.value as? String ?? ""
        XCTAssertTrue(text.hasSuffix("\u{1F3AF}"), "la nota non finisce con il glifo scelto")
        XCTAssertFalse(text.contains(":bers"), "il testo digitato per raggiungerla è rimasto")
    }

    func testArrowingPastTheVisibleEdgeScrollsTheList() throws {
        // The panel rebuilds its hosting view on every arrow key, so the SwiftUI view never
        // sees the selection *change* - it is born with one. The list therefore never
        // scrolled and the highlight walked off the bottom edge while the rows stood still.
        let editor = openTheLongNote()
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("\n:")
        XCTAssertTrue(app.staticTexts["bersaglio"].waitForExistence(timeout: 3), "il pannello non si è aperto")

        for _ in 0..<15 { app.typeKey(.downArrow, modifierFlags: []) }
        keep("06-arrowed-past-the-visible-edge")

        // Sixteenth entry of the catalogue. Asserting on what Return writes is the only way
        // to know the selection actually moved; that the list scrolled with it is what the
        // screenshot is for.
        app.typeKey(.enter, modifierFlags: [])
        let text = editor.value as? String ?? ""
        XCTAssertTrue(text.hasSuffix("\u{1F9EA}"), "la freccia giù non ha portato la selezione alla sedicesima voce")
    }

    func testTypingAfterTheLastHeadingReachesTheEndOfTheNote() throws {
        let editor = openTheLongNote()
        // Command-Down puts the caret after everything, which is where the note was
        // unreachable: the styling had made the note taller than the text view knew, so the
        // last lines were outside the scroll view and what was typed there never appeared.
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        keep("01-scrolled-to-the-end")

        editor.typeText("MARCATORE")
        keep("02-after-typing-a-marker")

        let text = editor.value as? String ?? ""
        XCTAssertTrue(text.contains("MARCATORE"), "il testo digitato non è arrivato nell'editor")

        let lines = text.components(separatedBy: "\n")
        let landed = lines.firstIndex { $0.contains("MARCATORE") } ?? -1
        print("MARKER LANDED ON LINE \(landed) OF \(lines.count)")
        // After Command-Down there is exactly one place it can be: the end.
        XCTAssertEqual(landed, lines.count - 1, "il testo non è finito in fondo alla nota")
    }

    func testTheCompletionPanelOpensOnTheLastLine() throws {
        let editor = openTheLongNote()
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("\n[[Prove")
        keep("03-panel-on-the-last-line")

        let text = editor.value as? String ?? ""
        XCTAssertTrue(text.contains("[[Prove"), "il trigger non è arrivato nell'editor")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
