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

}
