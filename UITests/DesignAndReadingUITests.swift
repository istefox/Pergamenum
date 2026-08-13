import XCTest

/// The design system in Settings, the vault's own themes, and reading mode.
///
/// All three were reachable only in principle before: the theme loader was called by
/// nobody, the colours were a read-only gallery in the sidebar, and the note could
/// only be seen as source. Each test here drives the running app and, where the
/// change is supposed to leave something behind, reads it back off disk.
final class DesignAndReadingUITests: XCTestCase {
    private var vault: URL!
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
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
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

    // MARK: Reading mode

    func testReadingModeRendersTheNoteAndTheEditorStillShowsTheSource() throws {
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))

        let note = text(withValue: "20260812_Nota_Lettura")
        XCTAssertTrue(note.waitForExistence(timeout: 10), "la nota di prova non è nell'elenco")
        note.click()

        // The two modes are a segmented picker, so radio buttons.
        XCTAssertTrue(app.radioButtons["Modifica"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews.firstMatch.exists, "l'editor non è quello di partenza")
        app.radioButtons["Lettura"].click()

        // Rendered: the heading is text, without its hashes, and the bold word is a
        // word rather than a pair of asterisks.
        XCTAssertTrue(
            text(withValue: "Titolo della nota").waitForExistence(timeout: 5),
            "il titolo non è reso"
        )
        XCTAssertFalse(text(withValue: "# Titolo della nota").exists, "la sintassi è ancora visibile")
        XCTAssertFalse(app.textViews.firstMatch.exists, "l'editor è ancora sullo schermo")

        // Back to the editor, and the source is back with it.
        app.radioButtons["Modifica"].click()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5), "l'editor non è tornato")

        // And from the Vista menu, which is where SPEC §10 puts the switch. Clicked
        // rather than typed: a shortcut hung on the picker itself did nothing at all,
        // and this asserts the menu entry is really connected to the mode.
        let item = app.menuBars.menuItems["Modalità lettura"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "la voce di menu non c'è")
        item.click()
        XCTAssertTrue(
            text(withValue: "Titolo della nota").waitForExistence(timeout: 5),
            "la voce di menu non passa in lettura"
        )
    }

    // MARK: Tables

    func testReadingModeRendersATableRatherThanItsPipes() throws {
        try openNoteInReadingMode()

        // Each cell is drawn on its own, so the header and a body cell are separate
        // pieces of text rather than one line of pipes.
        XCTAssertTrue(text(withValue: "Proprietà").waitForExistence(timeout: 5), "l'intestazione non è resa")
        XCTAssertTrue(text(withValue: "layout").exists, "una cella del corpo non è resa")
        XCTAssertTrue(text(withValue: "Template da usare").exists)

        // And the markup is gone: before this the whole table came out verbatim,
        // separator row included.
        XCTAssertFalse(text(withValue: "| layout | stringa | Template da usare |").exists,
                       "la riga è ancora testo grezzo")
        XCTAssertFalse(text(withValue: "|:--|:-:|--:|").exists, "la riga separatrice è visibile")
    }

    // MARK: Keyboard scrolling

    func testReadingModeScrollsWithTheKeyboard() throws {
        try openNoteInReadingMode()

        let anchor = text(withValue: "Titolo della nota")
        XCTAssertTrue(anchor.waitForExistence(timeout: 5))
        let before = anchor.frame.origin.y

        // A SwiftUI ScrollView takes the wheel but is not focusable, so this key went
        // nowhere and a note could only be read with a hand on the trackpad.
        app.typeKey(XCUIKeyboardKey.pageDown, modifierFlags: [])
        XCTAssertTrue(
            waitForTop(of: anchor) { $0 < before - 50 },
            "Page Down non ha fatto scorrere la nota"
        )

        // End reaches the bottom, and the last heading is on screen once it does.
        app.typeKey(XCUIKeyboardKey.end, modifierFlags: [])
        let bottom = text(withValue: "Fondo della nota")
        XCTAssertTrue(bottom.waitForExistence(timeout: 5), "Fine non ha raggiunto il fondo")

        // Home comes back, and the title is where it started.
        app.typeKey(XCUIKeyboardKey.home, modifierFlags: [])
        XCTAssertTrue(
            waitForTop(of: anchor) { $0 >= before - 1 },
            "Inizio non è tornato in cima"
        )
    }

    /// Waits for an element's top edge to satisfy a condition.
    ///
    /// Polled rather than expressed as an `NSPredicate`: `frame` comes back as an
    /// `NSValue`, which is not key-value coding compliant for `origin`, so a predicate
    /// on `frame.origin.y` throws instead of evaluating.
    private func waitForTop(
        of element: XCUIElement,
        timeout: TimeInterval = 5,
        _ satisfies: (CGFloat) -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if satisfies(element.frame.origin.y) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// Selects the fixture note and switches to reading mode.
    private func openNoteInReadingMode() throws {
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
        let note = text(withValue: "20260812_Nota_Lettura")
        XCTAssertTrue(note.waitForExistence(timeout: 10), "la nota di prova non è nell'elenco")
        note.click()
        XCTAssertTrue(app.radioButtons["Lettura"].waitForExistence(timeout: 5))
        app.radioButtons["Lettura"].click()
    }

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
