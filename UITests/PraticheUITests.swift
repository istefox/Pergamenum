import XCTest

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 10 -
// R-18, R-33, R-39; UX-BLUEPRINT's own accessibility-identifier checklist.
//
// Per this dispatch's explicit instruction: this file must **build for testing and
// never run**. `PergamenumUITests` launches a real `Pergamenum.app` instance that
// steals the global hotkey (`CLAUDE.md` "`.claude/test-cmd` runs at the end of every
// turn"), so it is compiled here (`xcodebuild ... build-for-testing`) and executed
// only by hand, never by an agent. Every assertion below reaches a control by its
// `accessibilityIdentifier`, never by the words on it (CLAUDE.md's own rule, paid for
// twice already).
//
// Identifiers asserted here are the ones the UX-BLUEPRINT checklist names that
// `Sources/Features/Pratiche/**` already carries as of this dispatch. A checklist
// identifier with no real view behind it yet is intentionally left out of this file
// rather than asserted against a control that cannot exist - see this dispatch's own
// report for the MISSING list the coder still owes.
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
        // R-19/ADR §D7: a per-test fixture root, never the real `~/Library/Mail`. Left
        // empty for every test but the «Rigenera» one below, which seeds a real
        // Envelope Index into it before `launch()` so a message reaches the timeline -
        // `FullDiskAccessProbe.state()` reads a successful `open(2)` on real content
        // the same way it reads `ENOENT` on an empty store, `.granted` either way
        // (`FullDiskAccessProbe.swift`'s own doc comment), so seeding it here does not
        // disturb `testTheFullDiskAccessBannerIsAbsentWithAReadableMailStoreFixture`.
        mailStoreRoot = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-mailstore", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: mailStoreRoot, withIntermediateDirectories: true)
        if name.contains("testRigeneraShowsADiffPreviewAndAnnullaLeavesTheFileOnDisk") {
            try seedMailStoreFixtureForRegeneration()
        }

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

    /// A real, schema-accurate Envelope Index (`MailStoreFixture`, `Tests/`-authored
    /// and pure Foundation, no XCTest import - reused here rather than forked so this
    /// UI test and the unit suite never carry two copies of the SQL fixture script) with
    /// one message on the fixture pratica's already-followed conversation
    /// (`pergamenum-dossier-conversations: [112409]` above), so a sync run
    /// (`PratichePane`'s own `.task`, fired on every test's `showPratiche()`) writes it
    /// straight into the timeline rather than into the tray. Only the «Rigenera» test
    /// below calls this - every other test in this file keeps the empty mail store its
    /// own doc comments describe.
    private func seedMailStoreFixtureForRegeneration() throws {
        _ = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1000), dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )],
            in: mailStoreRoot
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

    func testThePaneCarriesItsListAndPrimaryActions() throws {
        XCTAssertTrue(element("pratiche-pane").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-list").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-new").waitForExistence(timeout: 5), "manca «Nuova pratica»")
        XCTAssertTrue(element("pratiche-refresh").waitForExistence(timeout: 5), "manca «Aggiorna»")
    }

    func testTheFilterRowCarriesTheSenderMenuAndAttachmentsToggle() throws {
        XCTAssertTrue(element("pratiche-filter").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-sender-menu").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-attachments-only").waitForExistence(timeout: 5))
    }

    // MARK: - R-39: the timeline and its inspector toggle

    func testTheTimelineAndInspectorToggleAreAddressable() throws {
        selectFirstPratica()
        XCTAssertTrue(element("pratiche-timeline").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-inspector-toggle").waitForExistence(timeout: 5))
    }

    func testTheAddNoteAndAddCallEntryPointsAreAddressable() throws {
        selectFirstPratica()
        XCTAssertTrue(element("pratiche-add-note").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-add-call").waitForExistence(timeout: 5))
    }

    // MARK: - The wizard (opened from «Nuova pratica»)

    func testTheWizardOpensWithItsTitleAndClientFields() throws {
        element("pratiche-new").click()
        XCTAssertTrue(element("pratiche-wizard").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-wizard-title").waitForExistence(timeout: 5))
        XCTAssertTrue(element("pratiche-wizard-client").waitForExistence(timeout: 5))
    }

}
