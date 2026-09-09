import XCTest

/// Issue #188 (R-12, R-13): Cmd+click on a wikilink navigates to the linked note; a plain
/// click on the same text places the caret and does not navigate, preserving ADR-0029's
/// always-editable model.
final class WikilinkNavigationUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory()).appending(path: "WikilinkNavigationUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

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

        app = XCUIApplication()
        stateBase = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES",
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
    }

    /// Opens "Origine", returns the editor's text view once its source contains the
    /// wikilink - never asserting on rendered/concealed on-screen text (CLAUDE.md).
    private func openOriginAndReturnEditor() -> XCUIElement {
        let note = app.staticTexts["Origine"]
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

    /// The wikilink's whole line is the first (and only) line of the note body - a point
    /// near its top-left, inside the editor's readable-width text column, always lands on
    /// the link's own characters regardless of concealment (ADR-0018 §D3).
    private func wikilinkPoint(in editor: XCUIElement) -> XCUICoordinate {
        // Absolute pixel offset from the editor's own top-left corner, not a fraction of its
        // total (often mostly-blank) height - a normalized offset shifts with window size,
        // an absolute one from the readable-width inset (ADR-0030 §D7) does not. The wikilink
        // is the 7th source line (5 frontmatter lines, a blank line, then itself).
        let leftInset = max(24.0, (editor.frame.width - 720.0) / 2.0)
        let topInset = 24.0
        let lineHeight = 22.4
        let origin = editor.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        return origin.withOffset(CGVector(dx: leftInset + 12, dy: topInset + 6.5 * lineHeight))
    }

    func testCommandClickOnAWikilinkNavigatesToTheLinkedNote() throws {
        let editor = openOriginAndReturnEditor()

        let point = wikilinkPoint(in: editor)
        XCUIElement.perform(withKeyModifiers: .command) { point.click() }

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

    /// Mirrors the exact sequence that reproduced the reported regression on a real mouse
    /// (issue #188): a click elsewhere in the note first, so the view has already become first
    /// responder, THEN a plain click on the wikilink - not the wikilink as the very first click.
    /// Synthetic XCUITest clicks never reproduced the underlying AppKit gesture regardless of
    /// this sequencing, but the assertion still guards the behavior the fix defends: even if
    /// AppKit's own automatic "clickedOnLink" fires here on its own, the Cmd-liveness check in
    /// `textView(_:clickedOnLink:at:)` must refuse it.
    func testAPlainClickOnAWikilinkAfterAPriorUnrelatedClickDoesNotNavigate() throws {
        let editor = openOriginAndReturnEditor()

        // Click near the top-left, on the frontmatter "---" - far from the wikilink line -
        // first, mirroring "clicco in un punto diverso e la nota renderizza".
        let origin = editor.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        origin.withOffset(CGVector(dx: 40, dy: 30)).click()

        wikilinkPoint(in: editor).click()

        let source = editor.value as? String ?? ""
        XCTAssertFalse(
            source.contains("Nota di arrivo"),
            "un click semplice sul wikilink, dopo un click precedente altrove, ha navigato"
        )
    }

    func testAPlainClickOnAWikilinkPlacesTheCaretAndDoesNotNavigate() throws {
        let editor = openOriginAndReturnEditor()

        wikilinkPoint(in: editor).click()

        // ADR-0029: the editor stays always-editable, so a plain click on link text is an
        // ordinary caret placement, never a navigation - typing right after the click must
        // land in "Origine", not silently in a note that was never opened. "Destinazione"
        // is not a usable navigation signal here: its own sidebar row exists regardless of
        // whether it is open, so the check must read the editor's own content instead.
        editor.typeText("X")
        let source = editor.value as? String ?? ""
        XCTAssertTrue(
            source.contains("X"),
            "il click semplice non ha posizionato il cursore nell'editor di 'Origine'"
        )
        XCTAssertFalse(
            source.contains("Nota di arrivo"),
            "un click semplice sul wikilink ha navigato, invece di posizionare solo il cursore"
        )
    }

    /// R-07 regression guard for the `rightMouseDown(with:)` override added to stop a
    /// right-click on a link from un-concealing its paragraph before the menu appears
    /// (issue #188 fix 1): the override replaces AppKit's own default dispatch for a
    /// right-click landing on a link, so "Apri collegamento" navigating correctly is the one
    /// thing a UI test can still verify here - concealment itself is a display-only effect
    /// over the same raw source `editor.value` always returns, so it isn't observable this
    /// way (CLAUDE.md: no rendered-text assertions), and is checked by hand instead.
    func testRightClickApriCollegamentoStillNavigatesAfterTheRightMouseDownFix() throws {
        let editor = openOriginAndReturnEditor()

        wikilinkPoint(in: editor).rightClick()
        let menuItem = app.menuItems["Apri collegamento"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "«Apri collegamento» non è nel menu contestuale")
        menuItem.click()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !((editor.value as? String ?? "").contains("Nota di arrivo")) {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(
            (editor.value as? String ?? "").contains("Nota di arrivo"),
            "«Apri collegamento» dal menu contestuale non ha aperto 'Destinazione'"
        )
    }
}
