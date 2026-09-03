import XCTest

/// The design system in Settings, the vault's own themes, and reading mode.
///
/// All three were reachable only in principle before: the theme loader was called by
/// nobody, the colours were a read-only gallery in the sidebar, and the note could
/// only be seen as source. Each test here drives the running app and, where the
/// change is supposed to leave something behind, reads it back off disk.
final class DesignAndReadingUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var app: XCUIApplication!

    private var themesDirectory: URL {
        vault.appending(path: ".pergamenum/themes", directoryHint: .isDirectory)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try makeVault()

        // Nothing is snapshotted or restored here. `-recentVaults` below lands in the
        // argument domain, and `RecentVaults.remember` refuses to persist a list that
        // arrived that way, so this run cannot reach the user's own recents at all.
        // A guard on this side could not have worked: the XCUITest runner is sandboxed
        // and its `UserDefaults(suiteName:)` is a private copy in its own container.

        app = XCUIApplication()
        stateBase = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES",
                               "-stateBase", stateBase.path(percentEncoded: false)]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
    }

    // MARK: The sidebar carries the app's work, not its reference material

    func testTheSidebarNoLongerCarriesTheDesignSystemOrTheEditorMockup() throws {
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Workspace"].exists)
        // The gallery moved into Settings and the mockup was dropped: the Vault has
        // had the real editor since M1.
        XCTAssertFalse(app.staticTexts["Design system"].exists, "il pannello è ancora nella sidebar")
        XCTAssertFalse(app.staticTexts["Editor"].exists, "il mockup è ancora nella sidebar")
        XCTAssertFalse(app.staticTexts["mockup"].exists)
    }

    // MARK: A theme file in the vault is a theme the app offers

    func testAThemeFileInTheVaultReachesTheThemePicker() throws {
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))

        // Scoped to the window and matched by label: app-wide, `firstMatch` picked
        // the Touch Bar's own popup and the click failed on it.
        let picker = app.windows["Pergamenum"].popUpButtons["Tema"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "il selettore del tema non c'è")
        picker.click()

        // Written by hand into `.pergamenum/themes/`, which until now the app never
        // read outside the test suite.
        // `firstMatch`: the theme is offered in the sidebar picker and in Settings,
        // so the query matches more than one item and a bare click cannot resolve it.
        let custom = app.menuItems["Notte Vibrofer"].firstMatch
        XCTAssertTrue(custom.waitForExistence(timeout: 5), "il tema del vault non è nell'elenco")
        custom.click()

        // Chosen, not merely listed: the accent the file declares is what the app
        // now draws with.
        XCTAssertTrue(app.windows["Pergamenum"].popUpButtons["Tema"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows["Pergamenum"].popUpButtons["Tema"].value as? String, "Notte Vibrofer")
    }

    // MARK: The design system is a setting, and its colours can be reset

    func testTheDesignSystemPaneEditsTheVaultsOwnThemeFile() throws {
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))

        app.typeKey(",", modifierFlags: .command)
        let tab = app.buttons["Design system"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "la scheda Design system non c'è")
        tab.click()

        XCTAssertTrue(
            text(withValue: "color.accent.primary").waitForExistence(timeout: 5),
            "i token colore non sono elencati"
        )
        // Editable, not a gallery: every colour row carries a well.
        XCTAssertGreaterThan(app.colorWells.count, 10, "i colori non sono selezionabili")

        let reset = app.buttons["Ripristina"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.click()

        // The pane is wired to the file, not to a copy in memory: resetting removes
        // the theme from the vault.
        let file = themesDirectory.appending(path: "personalizzato.json")
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path(percentEncoded: false)),
            "il file del tema è ancora nel vault"
        )
    }

    // MARK: No Modifica/Lettura toggle

    /// ADR-0029 (R-01/R-02): the toggle is gone outright, not merely defaulted to one
    /// side - no radio buttons, no Vista menu entry, and the one editor left is always
    /// showing the note's own source, since there is no second, rendering-only view left
    /// to switch to.
    func testNoReadingModeToggleOrMenuEntryExistsAndTheEditorAlwaysShowsTheSource() throws {
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))

        let note = text(withValue: "20260812_Nota_Lettura")
        XCTAssertTrue(note.waitForExistence(timeout: 10), "la nota di prova non è nell'elenco")
        note.click()

        XCTAssertFalse(app.radioButtons["Modifica"].exists, "il controllo Modifica è ancora presente")
        XCTAssertFalse(app.radioButtons["Lettura"].exists, "il controllo Lettura è ancora presente")
        XCTAssertFalse(
            app.menuBars.menuItems["Modalità lettura"].exists, "la voce di menu è ancora presente"
        )

        // `NSTextView`'s own accessibility `value` is the raw source string regardless of
        // what TextKit 2 conceals on screen (ADR-0018 §D3's display-only principle), so
        // this is a content check, not a concealment one - concealment itself belongs to
        // `Tests/MarkupHidingTests.swift`, offscreen, where the *displayed* paragraph can
        // actually be inspected.
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "l'editor non c'è")
        let source = editor.value as? String ?? ""
        XCTAssertTrue(source.contains("Titolo della nota"), "l'editor non mostra il sorgente della nota")
    }

    // MARK: Tables

    /// ADR-0029 §D4: a GFM table draws as a real editable grid, found by its own
    /// `TableGridView`-carried identifier and never by the words in a cell (CLAUDE.md's
    /// working agreement) - concealment is not checkable at this level (see the test
    /// above), so this only asserts the grid itself is on screen.
    func testTheEditorRendersATableAsAGridRatherThanItsPipes() throws {
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
        let note = text(withValue: "20260812_Nota_Lettura")
        XCTAssertTrue(note.waitForExistence(timeout: 10), "la nota di prova non è nell'elenco")
        note.click()

        let grid = app.descendants(matching: .any).matching(identifier: "editor-table").firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 5), "la tabella non è resa come griglia")
    }

    // MARK: Keyboard scrolling
    //
    // `testReadingModeScrollsWithTheKeyboard` is deleted, not rewritten (plan
    // `2026-09-02-editor-wysiwyg-unification`, Task 6): it exercised a SwiftUI
    // `ScrollView`'s Page Down/Home/End handling, which no longer exists now that the
    // Modifica/Lettura toggle and `MarkdownReadingView` are gone (ADR-0029 §D14). The one
    // editor left is a plain `NSTextView`, and Page Down/Home/End on it are standard
    // AppKit key-view-loop behaviour with no app-specific logic behind them to regress -
    // there is nothing this repo wrote left for a test here to guard.

    /// A label the app draws as text: SwiftUI exposes it as the element's `value`,
    /// so the subscript form, which matches identifier or label, never finds it.
    private func text(withValue value: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value == %@", value)).firstMatch
    }

    // MARK: Fixture

    private func makeVault() throws {
        vault = URL(filePath: NSTemporaryDirectory())
            .appending(path: "DesignUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: themesDirectory, withIntermediateDirectories: true)

        try Self.vaultTheme.write(
            to: themesDirectory.appending(path: "notte-vibrofer.json"),
            atomically: true, encoding: .utf8
        )
        try Self.note.write(
            to: vault.appending(path: "20260812_Nota_Lettura.md"),
            atomically: true, encoding: .utf8
        )
        // A customisation as Settings writes it, present before launch: the engine
        // reads the vault's themes when it attaches, so a file written afterwards
        // would not be there to reset.
        try write(customization: "#00AA00")
    }

    private func write(customization hex: String) throws {
        let json = """
        {
          "meta": {
            "name": { "$type": "string", "$value": "Personalizzato" },
            "appearance": { "$type": "string", "$value": "light" }
          },
          "color": { "accent": { "primary": { "$type": "color", "$value": "\(hex)" } } }
        }
        """
        try json.write(
            to: themesDirectory.appending(path: "personalizzato.json"),
            atomically: true, encoding: .utf8
        )
    }

    private static let vaultTheme = """
    {
      "meta": {
        "name": { "$type": "string", "$value": "Notte Vibrofer" },
        "appearance": { "$type": "string", "$value": "dark" }
      },
      "color": { "accent": { "primary": { "$type": "color", "$value": "#BE1622" } } }
    }
    """

    /// Long on purpose: the keyboard-scrolling test needs a note that does not fit in
    /// the window, or Page Down has nowhere to go and the test passes without moving.
    private static let note = """
    ---
    date: 2026-08-12
    tags:
      - project-vibrofer
    ---

    # Titolo della nota

    Testo con **grassetto** e `codice`.

    - primo
    - secondo

    - [ ] da fare
    - [x] fatto

    | Proprietà | Tipo | Effetto |
    |:--|:-:|--:|
    | layout | stringa | Template da usare |
    | date | data | Data di pubblicazione |

    \(String(repeating: "Riempitivo per rendere la nota più alta della finestra.\n\n", count: 60))

    ## Fondo della nota
    """
}
