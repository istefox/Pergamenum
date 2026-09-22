import XCTest

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 10 -
// R-18, R-33, R-39; UX-BLUEPRINT's own accessibility-identifier checklist. Every
// assertion below reaches a control by its `accessibilityIdentifier`, never by the
// words on it (CLAUDE.md's own rule, paid for twice already).
//
// Four tests retired here per the UI-suite-replacement census (stage 3, Task 6): the
// pane/list/actions, filter-row, add-note/add-call and wizard-fields checks were all
// existence-of-identifier assertions with no production seam behind them, the same
// shape the census retired throughout this pass. What is left is the one real
// selection-wiring path this pane still needs a window for: a click on a list row
// driving the timeline and its inspector toggle.
final class PraticheUITests: XCTestCase {
    /// One conformant pratica, seeded on disk before `launch()`, so the list column
    /// has a row and the timeline/inspector/add-note/add-call surfaces - all gated on
    /// `pratiche.selection != nil` (`PratichePane.swift`'s `content`) - have something
    /// to open. `01 Progetti` is `PraticheSettings.defaultRootFolder`; `Acme` is the
    /// client folder `PraticheController.clientName(ofPraticaFolder:rootFolder:)` reads
    /// off the folder's parent.
    private static let praticaFolder = "01 Progetti/Acme/Offerta 118"

    private var vault: URL!
    private var stateBase: URL!
    private var mailStoreRoot: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory()).appending(path: "PraticheUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try seedFixturePratica()

        app = XCUIApplication()
        stateBase = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)
        // R-19/ADR §D7: a per-test fixture root, never the real `~/Library/Mail`, left
        // empty - `FullDiskAccessProbe.state()` reads `ENOENT` on an empty store as
        // `.granted`, same as it would a real one (`FullDiskAccessProbe.swift`'s own
        // doc comment).
        mailStoreRoot = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-mailstore", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: mailStoreRoot, withIntermediateDirectories: true)

        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES",
                               "-disableUpdater", "YES",
                               "-mailStoreRoot", mailStoreRoot.path(percentEncoded: false),
                               "-stateBase", stateBase.path(percentEncoded: false)]
        app.launch()
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
        showPratiche()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
        try? FileManager.default.removeItem(at: mailStoreRoot)
    }

    private func showPratiche() {
        let row = app.staticTexts["Pratiche"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la sezione Pratiche non è nella barra laterale")
        row.click()
        XCTAssertTrue(
            element("pratiche-pane").waitForExistence(timeout: 5),
            "la sezione Pratiche non si è aperta"
        )
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Writes `pratica.md` with a valid `pergamenum-dossier` and the tag set
    /// `Dossier`/`PraticheController.listItems` require (`type-note`, `topic-pratica`,
    /// `client-acme`, `status-active`, `source-email` - matched against
    /// `Tests/PraticheConnectorTests.swift`'s own fixture, not invented here), plus
    /// empty `email/`/`allegati/` directories (`PraticheController.messagesDirectoryName`/
    /// `.attachmentsDirectoryName`) - `readMessages` reads them with `try?` and copes
    /// with either missing entirely, but a real pratica folder always has both.
    private func seedFixturePratica() throws {
        let folder = vault.appending(path: Self.praticaFolder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: folder.appending(path: "email", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: folder.appending(path: "allegati", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let praticaNote = """
        ---
        date: 2026-09-01
        tags:
          - type-note
          - topic-pratica
          - client-acme
          - status-active
          - source-email
        pergamenum-dossier: 1
        pergamenum-dossier-counterparts:
          - m.rossi@acme.it
        pergamenum-dossier-conversations: [112409]
        ---

        Appunti pratica.
        """
        try praticaNote.write(
            to: folder.appending(path: "pratica.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
    }

    /// Clicks the fixture pratica's row (`pratiche-row-<folder path>`,
    /// `PraticheListColumn.praticaRow`'s own `pratica.id`, which is the folder path -
    /// `PraticheController.listItems`) and waits for the timeline that only exists once
    /// `pratiche.selection != nil` (`PratichePane.content`).
    private func selectFirstPratica() {
        let row = element("pratiche-row-\(Self.praticaFolder)")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la riga della pratica fixture non è nella lista")
        row.click()
        XCTAssertTrue(
            element("pratiche-timeline").waitForExistence(timeout: 5),
            "la timeline non si è aperta dopo la selezione della pratica"
        )
    }

    // MARK: - R-18: the pane itself, the list, and the Full Disk Access banner

    func testTheTimelineAndInspectorToggleAreAddressable() throws {
        selectFirstPratica()
        XCTAssertTrue(element("pratiche-timeline").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-inspector-toggle").waitForExistence(timeout: 5))
    }
}
