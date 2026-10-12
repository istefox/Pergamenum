import XCTest

/// Issue #188 (R-12, R-13): Cmd+click on a wikilink navigates to the linked note, exercising
/// the real `AXLink` click with real modifier flags - the editor's central interaction and
/// the one path a synthetic click could actually reproduce.
///
/// The two plain-click tests retired here per the UI-suite-replacement census (stage 3,
/// Task 6) were vacuous by their own comments: synthetic XCUITest clicks never reproduced
/// the underlying AppKit gesture regardless of click sequencing, so what they asserted was
/// the absence of navigation from a click that was never a real click to begin with. Both
/// are replaced by the plain-click-refused unit test the injectable Cmd-state closure
/// (`NoteTextView+Coordinator.swift:411`) makes possible, named in the census's
/// WorkspaceFocusUITests/WikilinkNavigationUITests entry.
final class WikilinkNavigationUITests: PergamenumUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try makeTemporaryVault(prefix: "WikilinkNavigationUITest")

        // The wikilink sits alone on the note's first body line so a click anywhere on that
        // line's visible text lands on it - no other text on the line to miss it for.
        try """
        ---
        date: 2026-09-09
        tags:
          - type-note
        ---

        [[Destinazione]]
        """.write(
            to: vault.appending(path: "Origine.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
        try """
        ---
        date: 2026-09-09
        tags:
          - type-note
        ---

        Nota di arrivo.
        """.write(
            to: vault.appending(path: "Destinazione.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )

        launchApp()
        waitForMainWindow()
    }

    /// Opens "Origine", returns the editor's text view once its source contains the
    /// wikilink - never asserting on rendered/concealed on-screen text (CLAUDE.md).
    private func openOriginAndReturnEditor() -> XCUIElement {
        let note = noteRow("Origine.md")
        XCTAssertTrue(note.waitForExistence(timeout: 10), "la nota 'Origine' non è nell'elenco")
        note.click()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "l'editor non c'è")
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !((editor.value as? String ?? "").contains("Destinazione")) {
            Thread.sleep(forTimeInterval: 0.1)
        }
        return editor
    }

    /// A concealed `[[Destinazione]]` still surfaces as a real `AXLink` element titled after
    /// the note it targets (confirmed via `xcrun xcresulttool export attachments` on a failed
    /// run's UI-hierarchy dump) - clicking it directly is immune to window size, word-wrap and
    /// paragraph position, unlike the hardcoded-pixel-offset approach this replaced, which
    /// missed the link's actual left edge by a couple of points regardless of window width
    /// (confirmed by widening the window well past the 720pt readable-width cap and seeing the
    /// same 3 failures). The link's title is the note's own name: a link drawn inside the
    /// note's text has no view of its own to carry an `accessibilityIdentifier`, so this is the
    /// one lookup here that still reads the fixture's words (`openOriginAndReturnEditor()` finds
    /// the note's row by `note-row-Origine.md`, PG-265).
    /// The link's own `AXTitle` carries the raw markdown target text, bold markers and all -
    /// confirmed via the same attachment export: `[[**Destinazione**]]` surfaces as a link
    /// titled `**Destinazione**`, not the concealed "Destinazione" the plain case uses.
    private func wikilinkElement(title: String = "Destinazione") -> XCUIElement {
        let link = app.links[title]
        XCTAssertTrue(link.waitForExistence(timeout: 5), "il link '\(title)' non è nell'editor")
        return link
    }

    func testCommandClickOnAWikilinkNavigatesToTheLinkedNote() throws {
        let editor = openOriginAndReturnEditor()

        let link = wikilinkElement()
        XCUIElement.perform(withKeyModifiers: .command) { link.click() }

        // "Destinazione" alone is not a usable navigation signal: its sidebar row exists
        // whether or not the note is open. The editor's own content switching to its body
        // is what actually proves the Cmd+click navigated.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !((editor.value as? String ?? "").contains("Nota di arrivo")) {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(
            (editor.value as? String ?? "").contains("Nota di arrivo"),
            "Cmd+click sul wikilink non ha aperto 'Destinazione'"
        )
    }

    /// Waits up to `timeout` seconds for the editor's source to contain `text`.
    private func waitForEditor(_ editor: XCUIElement, toContain text: String, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !((editor.value as? String ?? "").contains(text)) {
            Thread.sleep(forTimeInterval: 0.1)
        }
        return (editor.value as? String ?? "").contains(text)
    }

    /// The window and the editor's source, kept with the result bundle: the runner's own temporary
    /// directory cannot be read afterwards, so a red is diagnosed from attachments (ui-tests rules).
    private func attachEvidence(named name: String, editor: XCUIElement) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(name): finestra"
        shot.lifetime = .keepAlways
        add(shot)
        let source = XCTAttachment(string: editor.value as? String ?? "(nessun valore)")
        source.name = "\(name): testo dell'editor"
        source.lifetime = .keepAlways
        add(source)
    }

    /// N3 (R-21, ADR-0083 §D8): Cmd+Opt+Return follows the link under the caret, Cmd+[ comes back.
    /// The caret goes inside `[[Destinazione]]` by keyboard alone: the fixture has no trailing
    /// newline, so Cmd+Down lands at the end of the text and three Left arrows step back over
    /// `]]` and one letter, whatever the line wraps to.
    func testFollowingTheLinkAtTheCaretAndComingBack() throws {
        let editor = openOriginAndReturnEditor()
        editor.click()
        editor.typeKey(.downArrow, modifierFlags: .command)
        for _ in 0..<3 { editor.typeKey(.leftArrow, modifierFlags: []) }

        editor.typeKey(.return, modifierFlags: [.command, .option])
        XCTAssertTrue(
            waitForEditor(editor, toContain: "Nota di arrivo"),
            "Cmd+Opt+Return con il cursore nel link non ha aperto 'Destinazione'"
        )

        // Read before the key, to tell "the history recorded nothing" from "the key never arrived".
        let backWasEnabled = element("history-back").isEnabled
        editor.typeKey("[", modifierFlags: .command)
        let cameBack = waitForEditor(editor, toContain: "Destinazione")
        if !cameBack {
            // Evidence only: does the toolbar's own button walk back? Tells a key the editor
            // swallowed from a history that cannot go back.
            element("history-back").click()
            let buttonWorks = waitForEditor(editor, toContain: "Destinazione", timeout: 3)
            attachEvidence(
                named: "dopo Cmd+[ (history-back abilitato prima del tasto: \(backWasEnabled); "
                    + "il pulsante torna indietro: \(buttonWorks))",
                editor: editor
            )
        }
        XCTAssertTrue(cameBack, "Cmd+[ non è tornato a 'Origine'")
        XCTAssertFalse(
            (editor.value as? String ?? "").contains("Nota di arrivo"),
            "dopo Cmd+[ l'editor mostra ancora 'Destinazione'"
        )
    }

    /// N3 (R-20, ADR-0083 §D8): the preview shows under Cmd+hover and goes when the modifier is
    /// released, and it leaves the keyboard with the editor - a character typed afterwards lands
    /// in the note. The dwell is 250 ms, so the wait is generous.
    func testCommandHoverShowsThePreviewAndReleaseHidesIt() throws {
        let editor = openOriginAndReturnEditor()
        editor.click()
        let link = wikilinkElement()
        // Resolved outside the block: a closure that reaches `self` is not `Sendable`.
        let preview = element("link-preview")

        let application: XCUIApplication = app
        var shown = false
        var evidence: XCUIScreenshot?
        XCUIElement.perform(withKeyModifiers: .command) {
            link.hover()
            shown = preview.waitForExistence(timeout: 3)
            if !shown { evidence = application.screenshot() }
        }
        if let evidence {
            let attachment = XCTAttachment(screenshot: evidence)
            attachment.name = "Cmd+hover senza anteprima"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(shown, "Cmd+hover sul wikilink non ha mostrato l'anteprima")

        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: preview
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone], timeout: 2), .completed,
            "rilasciato Cmd l'anteprima è rimasta"
        )

        editor.typeText("Q")
        XCTAssertTrue(
            waitForEditor(editor, toContain: "Q"),
            "il carattere digitato dopo l'anteprima non è arrivato all'editor"
        )
    }
}
