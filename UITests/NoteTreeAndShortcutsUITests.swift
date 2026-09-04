import XCTest

/// The folder tree in the sidebar and the shortcuts the user can move.
///
/// Both are things that can only be checked by running the app: a tree that builds
/// correctly and never appears, or a binding that is stored correctly and never
/// reaches the menu bar, would pass every unit test in the suite.
final class NoteTreeAndShortcutsUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try makeVault()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
    }

    /// Launches the app on the fixture vault.
    ///
    /// Nothing is snapshotted or restored. `-recentVaults` and `-shortcutOverrides`
    /// both land in the argument domain, and both stores refuse to persist a value
    /// that arrived that way, so a run cannot reach the user's own preferences. A
    /// guard on this side could not work: the XCUITest runner is sandboxed and its
    /// `UserDefaults(suiteName:)` is a private copy in its own container.
    private func launch(shortcuts: String? = nil) {
        app = XCUIApplication()
        stateBase = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)
        var arguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                         "-disableCalendar", "YES",
                         "-disableUpdater", "YES",
                         "-stateBase", stateBase.path(percentEncoded: false)]
        if let shortcuts {
            arguments += ["-shortcutOverrides", shortcuts]
        }
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
    }

    // MARK: The sidebar shows the folders

    func testTheSidebarShowsFoldersAndOpensThemOnClick() throws {
        launch()

        // The folders are rows of their own. The flat list this replaced printed the
        // folder under every note as a caption and showed no structure at all.
        let folder = app.staticTexts["01 Progetti"]
        XCTAssertTrue(folder.waitForExistence(timeout: 5), "la cartella non è nella barra laterale")
        XCTAssertTrue(app.staticTexts["02 Aree"].exists)

        // Toggling is the chevron's job, not the row body's (2026-08-28, toolbar-parity
        // chain): a folder row now carries `.tag` for Rinomina/Elimina, and a row-wide
        // gesture would starve `List(selection:)`'s own tap the same way
        // `WorkspaceRow.taggedRow`'s own comment records happening there first
        // (ADR-0025 §D9). `clickFolderChevron(_:)` clicks the chevron's own pixel,
        // never the words on the row (CLAUDE.md).

        // A note at the root is visible without opening anything.
        XCTAssertTrue(app.staticTexts["Appunti sparsi"].exists)

        // A note inside a folder is not, until the folder is opened.
        XCTAssertFalse(app.staticTexts["Trasmissibilità"].exists,
                       "la cartella è già aperta: il test non prova nulla")
        clickFolderChevron("01 Progetti")
        XCTAssertTrue(app.staticTexts["Trasmissibilità"].waitForExistence(timeout: 5),
                      "aprire la cartella non ha mostrato la nota")

        // And a subfolder inside it nests one level further in.
        XCTAssertTrue(app.staticTexts["Vibrofer"].exists)
        clickFolderChevron("01 Progetti/Vibrofer")
        XCTAssertTrue(app.staticTexts["Brief sito"].waitForExistence(timeout: 5))

        // Clicking the folder's chevron again closes it.
        clickFolderChevron("01 Progetti")
        XCTAssertFalse(app.staticTexts["Trasmissibilità"].exists, "la cartella non si è richiusa")
    }

    func testANoteInAClosedFolderCanStillBeOpenedAndBecomesVisible() throws {
        launch()

        // Reached from the quick switcher, which knows nothing about the tree: the
        // sidebar has to open the folders above whatever the app opens, or the note
        // being edited is selected inside a folder nobody can see.
        XCTAssertFalse(app.staticTexts["Trasmissibilità"].exists)
        app.typeKey("o", modifierFlags: .command)
        let field = app.textFields["quick-switcher-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "il quick switcher non si è aperto")
        field.typeText("Trasmissibilità\r")

        XCTAssertTrue(app.staticTexts["Trasmissibilità"].waitForExistence(timeout: 5),
                      "la cartella della nota aperta non è stata espansa")
    }

    // MARK: A shortcut the user moved

    func testAShortcutChangedInSettingsIsTheOneTheMenuAnswersTo() throws {
        // The quick switcher moved off Cmd+O and onto Cmd+J. Written as an old-style
        // property list rather than as the JSON the settings pane stores: UserDefaults
        // parses an argument beginning with `{` as a plist, and a value that parser
        // cannot read is dropped before the app ever sees it, so a JSON literal here
        // would leave the shortcut at its default and the test would prove nothing.
        launch(shortcuts: "{quickSwitcher = {key = j; modifiers = 1;};}")

        app.typeKey("j", modifierFlags: .command)
        XCTAssertTrue(app.textFields["quick-switcher-field"].waitForExistence(timeout: 5),
                      "la scorciatoia riassegnata non ha aperto il quick switcher")
        app.typeKey(.escape, modifierFlags: [])

        // And the default is gone rather than still working alongside it: a menu that
        // answers to both keys is a menu that never read the new binding.
        XCTAssertTrue(app.textFields["quick-switcher-field"].waitForNonExistence(timeout: 5))
        app.typeKey("o", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(app.textFields["quick-switcher-field"].exists,
                       "Cmd+O apre ancora il quick switcher: la scorciatoia vecchia è rimasta")
    }

    func testTheSettingsPaneListsEveryCommandAndCanPutOneBack() throws {
        launch(shortcuts: "{newNote = {key = j; modifiers = 1;};}")

        app.typeKey(",", modifierFlags: .command)
        // Matched app-wide rather than inside a window named in advance: the settings
        // scene's title comes from the system and is not this app's to promise.
        let tab = app.descendants(matching: .any).matching(identifier: "Scorciatoie").firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "la scheda Scorciatoie non è comparsa")
        tab.click()

        // The row is generated from the catalogue, and it shows the changed binding
        // rather than the default it no longer has.
        let recorder = app.buttons["shortcut-newNote"]
        XCTAssertTrue(recorder.waitForExistence(timeout: 5), "la riga di Nuova nota non c'è")
        XCTAssertEqual(recorder.value as? String, "⌘J")

        // Every other command is listed too: the pane is the whole catalogue, not a
        // hand-written selection of it.
        XCTAssertTrue(app.buttons["shortcut-save"].exists)
        XCTAssertTrue(app.buttons["shortcut-taskToday"].exists)
        XCTAssertTrue(app.buttons["shortcut-newReminder"].exists)

        // And the default comes back on demand. Nothing is written to disk by this:
        // the bindings arrived on the command line, so the store refuses to persist.
        app.buttons["reset-newNote"].click()
        XCTAssertEqual(recorder.value as? String, "⌘N")
    }

    func testTheRecorderTakesTheCombinationThatIsPressed() throws {
        launch(shortcuts: "{newNote = {key = j; modifiers = 1;};}")

        app.typeKey(",", modifierFlags: .command)
        let tab = app.descendants(matching: .any).matching(identifier: "Scorciatoie").firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.click()

        let recorder = app.buttons["shortcut-newNote"]
        XCTAssertTrue(recorder.waitForExistence(timeout: 5))
        recorder.click()

        // Cmd+Option+Y is nobody's shortcut here, so if the combination is recorded it
        // was the monitor that took it and not some menu item firing instead.
        app.typeKey("y", modifierFlags: [.command, .option])
        XCTAssertEqual(recorder.value as? String, "⌥⌘Y")

        // Escape leaves a recording as it was rather than clearing it, which is what
        // cancelling has to mean.
        recorder.click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(recorder.value as? String, "⌥⌘Y")

        // Backspace on its own removes the shortcut: a command may legitimately have
        // none, and there has to be a way to say so.
        recorder.click()
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertEqual(recorder.value as? String, "nessuna")
    }

    // MARK: Sidebar helpers

    /// Clicks a folder row's own toggle chevron - `NoteListPane.folderRow`'s leading
    /// `Image(systemName: "chevron.right")`, moved off the row body (2026-08-28,
    /// toolbar-parity chain) once the row itself gained `.tag` for Rinomina/Elimina.
    ///
    /// No `accessibilityIdentifier` reaches it: a macOS `List` row collapses its leaves
    /// into one accessibility element for the row, the same limitation
    /// `SidebarMoveUITests`'s header comment records for `WorkspaceRow`'s own chevron
    /// ("cannot be reached by identifier without first clicking that exact pixel"). This
    /// clicks the pixel instead, by a fixed point offset from the row's own leading edge
    /// (`"folder-\(folderId)"`, unaffected by this) rather than a normalized fraction,
    /// because the row spans the whole sidebar width while the chevron is a fixed ~14pt
    /// icon - `NoteListPane.indent` for the depth's own padding, plus half that again to
    /// land inside the icon rather than at its border.
    ///
    /// `folderId` is the same relative-path spelling `makeVault()` creates the folder
    /// with (e.g. `"01 Progetti/Vibrofer"`).
    ///
    /// No depth-dependent offset: the row's own accessibility frame tightly wraps its
    /// laid-out `HStack` content rather than spanning the sidebar's full width, so its
    /// own leading edge already sits past `.padding(.leading, depth * indent)` whatever
    /// the depth - confirmed by hand, a fixed offset from a depth-0 row's own edge
    /// landed short of the chevron once tried against a depth-1 row's identical offset
    /// plus the padding added back on top.
    private func clickFolderChevron(_ folderId: String) {
        // `.firstMatch`: a macOS `List` row's identifier can resolve to more than one
        // accessibility node (an outer table cell and its content view both answering
        // to it) that occupy the same point on screen, so either match clicks the same
        // pixel - `.firstMatch` picks one without asserting there is only one.
        let row = app.descendants(matching: .any)["folder-\(folderId)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la cartella «\(folderId)» non è nella barra laterale")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 7, dy: 0))
            .click()
    }

    // MARK: Fixture

    private func makeVault() throws {
        vault = URL(filePath: NSTemporaryDirectory())
            .appending(path: "TreeUITest-\(UUID().uuidString)")
        for folder in ["01 Progetti/Vibrofer", "02 Aree"] {
            try FileManager.default.createDirectory(
                at: vault.appending(path: folder, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }
        try write("Appunti sparsi", at: "Appunti sparsi.md")
        try write("Trasmissibilità", at: "01 Progetti/Trasmissibilità.md")
        try write("Brief sito", at: "01 Progetti/Vibrofer/Brief sito.md")
        try write("Capitolati", at: "02 Aree/Capitolati.md")
    }

    private func write(_ title: String, at relativePath: String) throws {
        let note = """
        ---
        date: 2026-08-13
        tags:
          - type-nota
        ---

        # \(title)

        Corpo della nota \(title).
        """
        try note.write(
            to: vault.appending(path: relativePath, directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
    }
}
