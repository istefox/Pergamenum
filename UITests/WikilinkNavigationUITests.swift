import XCTest

/// Issue #188 (R-12, R-13): Cmd+click on a wikilink navigates to the linked note; a plain
/// click on the same text places the caret and does not navigate, preserving ADR-0029's
/// always-editable model.
final class WikilinkNavigationUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var mailStoreRoot: URL!
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

    /// A concealed `[[Destinazione]]` still surfaces as a real `AXLink` element titled after
    /// the note it targets (confirmed via `xcrun xcresulttool export attachments` on a failed
    /// run's UI-hierarchy dump) - clicking it directly is immune to window size, word-wrap and
    /// paragraph position, unlike the hardcoded-pixel-offset approach this replaced, which
    /// missed the link's actual left edge by a couple of points regardless of window width
    /// (confirmed by widening the window well past the 720pt readable-width cap and seeing the
    /// same 3 failures). The link's title is the note's own name, the same identifier
    /// `openOriginAndReturnEditor()` already uses for `app.staticTexts["Origine"]` - not prose
    /// that can grow and break the lookup (CLAUDE.md's "must not find a control by the words on
    /// it" is about UI copy, not a note's own stable title).
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

        wikilinkElement().click()

        let source = editor.value as? String ?? ""
        XCTAssertFalse(
            source.contains("Nota di arrivo"),
            "un click semplice sul wikilink, dopo un click precedente altrove, ha navigato"
        )
    }

    func testAPlainClickOnAWikilinkPlacesTheCaretAndDoesNotNavigate() throws {
        let editor = openOriginAndReturnEditor()

        wikilinkElement().click()

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
}
