import XCTest

/// The Diario pane, driven the way a person drives it: the toolbar, the composer, the
/// timeline, and the file all of it ends up in.
///
/// The diary writes on its own - there is no Salva - so every one of these also checks
/// the file on disk. A day that is only on screen is a day that is not written down.
final class DiaryUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
    private var mailStoreRoot: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory()).appending(path: "DiaryUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

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
        showDiary()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
        try? FileManager.default.removeItem(at: mailStoreRoot)
    }

    private func showDiary() {
        let row = app.staticTexts["Diario"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la sezione Diario non è nella barra laterale")
        row.click()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "diary-header").firstMatch
                .waitForExistence(timeout: 5),
            "la sezione Diario non si è aperta"
        )
    }

    /// The pane carries its own toolbar, like every other section.
    func testTheDiarySectionCarriesItsToolbar() throws {
        for label in ["Nuovo blocco", "Giorno precedente", "Giorno successivo", "Vai a data"] {
            XCTAssertTrue(
                app.toolbars.buttons[label].waitForExistence(timeout: 5),
                "«\(label)» non è nella toolbar del Diario"
            )
        }
    }

    /// The pane hosts the one unified editor and nothing beside it: no separate preview
    /// rendering, and no picker to switch into a mode that no longer exists (R-11,
    /// ADR-0029 - supersedes ADR-0005 §D2's "editor and preview side by side" premise).
    func testTheEditorIsTheOnlyWritingSurfaceOnScreen() throws {
        XCTAssertTrue(element("diary-editor").waitForExistence(timeout: 5), "manca l'editor")
        XCTAssertTrue(element("diary-timeline").waitForExistence(timeout: 5), "manca la giornata")
        XCTAssertFalse(element("diary-preview").exists, "l'anteprima separata non deve più esistere")
        XCTAssertFalse(element("diary-layout").exists, "il selettore di modalità non deve più esistere")
    }

    /// The whole point of the pane: block out a couple of hours, give them a name, and
    /// find both on the timeline and in the file.
    func testABlockIsComposedAndWrittenToTheFile() throws {
        app.toolbars.buttons["Nuovo blocco"].click()

        let title = app.textFields["diary-sheet-title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "la scheda del blocco non si è aperta")
        title.click()
        title.typeText("Sopralluogo pressa 4")
        app.buttons["diary-sheet-save"].firstMatch.click()

        XCTAssertTrue(entry.waitForExistence(timeout: 5), "il blocco non compare sulla giornata")
        XCTAssertTrue(
            waitForDiary { $0.contains("## Diario") && $0.contains("Sopralluogo pressa 4") },
            "il blocco non è finito nel file del giorno"
        )
    }

    /// And out again, from the x that sits on the block itself.
    func testABlockIsDeletedFromTheTimeline() throws {
        composeBlock(named: "Da eliminare")

        entry.hover()
        let remove = app.buttons["diary-remove-entry"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "manca la x sul blocco")
        remove.click()

        XCTAssertTrue(
            waitForDiary { !$0.contains("## Diario") },
            "il file conserva la sezione dopo l'eliminazione"
        )
        XCTAssertFalse(entry.waitForExistence(timeout: 2), "il blocco è ancora disegnato")
    }

    /// The composer's own delete, for the block that is already open.
    func testABlockIsDeletedFromItsSheet() throws {
        composeBlock(named: "Da eliminare dalla scheda")

        entry.click()
        let delete = app.buttons["diary-sheet-delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "la scheda non offre di eliminare")
        delete.click()

        XCTAssertTrue(waitForDiary { !$0.contains("## Diario") }, "il blocco è rimasto nel file")
    }

    /// What is typed in the editor is written without anybody asking for it, and the
    /// day that was left is written before the next one is read.
    func testTypingIsSavedAndSurvivesAChangeOfDay() throws {
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "manca l'editor markdown")
        editor.click()
        editor.typeText("## Mattina\n\nRiunione con il cliente.\n")

        XCTAssertTrue(
            waitForDiary { $0.contains("Riunione con il cliente.") },
            "quello che è stato scritto non è finito nel file"
        )

        app.toolbars.buttons["Giorno successivo"].click()
        app.toolbars.buttons["Giorno precedente"].click()

        XCTAssertTrue(
            waitForDiary { $0.contains("Riunione con il cliente.") },
            "il testo si è perso cambiando giorno"
        )
    }

    // MARK: Support

    private var entry: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "diary-entry").firstMatch
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Opens the composer from the toolbar, names the block and saves it.
    private func composeBlock(named name: String) {
        app.toolbars.buttons["Nuovo blocco"].click()
        let title = app.textFields["diary-sheet-title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "la scheda del blocco non si è aperta")
        title.click()
        title.typeText(name)
        app.buttons["diary-sheet-save"].firstMatch.click()
        XCTAssertTrue(waitForDiary { $0.contains(name) }, "«\(name)» non è stato scritto")
    }

    /// Polls the diary file, because the write happens on the app's side of the process
    /// boundary and the diary saves on its own schedule.
    private func waitForDiary(timeout: TimeInterval = 6, _ condition: (String) -> Bool) -> Bool {
        let path = vault
            .appending(path: "Diario", directoryHint: .isDirectory)
            .appending(path: "\(compactToday).md", directoryHint: .notDirectory)
        return waitFor(timeout: timeout) {
            guard let text = try? String(contentsOf: path, encoding: .utf8) else { return false }
            return condition(text)
        }
    }

    private func waitFor(timeout: TimeInterval = 6, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return false
    }

    /// `20260814`, in the machine's own zone because `CalendarDate.today` is.
    private var compactToday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
