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
//
// PG-298, ADR-0070 (`docs/plans/pg-298-timeline-backspace-exclude.md`, Task 4) added the
// fixture's two message files and the two Backspace tests below - R-01, R-02, R-08. A real
// key delivered to a live `List`'s focus and responder chain is observable nowhere in-process
// (ADR-0070 F10), so this is the only place either is witnessed; `Tests/PraticaDeleteKeyTests
// .swift` pins the pure target rule the key calls into. `UITests/AttachmentChipContextMenuUITests
// .swift` is not touched (R-07).
final class PraticheUITests: XCTestCase {
    /// One conformant pratica, seeded on disk before `launch()`, so the list column
    /// has a row and the timeline/inspector/add-note/add-call surfaces - all gated on
    /// `pratiche.selection != nil` (`PratichePane.swift`'s `content`) - have something
    /// to open. `01 Progetti` is `PraticheSettings.defaultRootFolder`; `Acme` is the
    /// client folder `PraticheController.clientName(ofPraticaFolder:rootFolder:)` reads
    /// off the folder's parent.
    private static let praticaFolder = "01 Progetti/Acme/Offerta 118"
    /// PG-298 fixture messages: one carries a placed attachment (for the Quick Look
    /// preview R-08 needs), one carries none (the row both Backspace tests exclude).
    private static let messageWithAttachmentID = "<pg298-attachment@example.com>"
    private static let messageWithoutAttachmentID = "<pg298-plain@example.com>"

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
    /// `email/`/`allegati/` directories (`PraticheController.messagesDirectoryName`/
    /// `.attachmentsDirectoryName`) - `readMessages` reads them with `try?` and copes
    /// with either missing entirely, but a real pratica folder always has both.
    ///
    /// PG-298: two message files under `email/`, the shape
    /// `AttachmentChipContextMenuUITests.seedFixturePraticaWithAttachment` already uses - one
    /// naming a placed attachment (`[[nota.txt]]`), one naming none.
    private func seedFixturePratica() throws {
        let folder = vault.appending(path: Self.praticaFolder, directoryHint: .isDirectory)
        let emailDirectory = folder.appending(path: "email", directoryHint: .isDirectory)
        let attachmentsDirectory = folder.appending(path: "allegati", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: emailDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
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

        try "contenuto".write(
            to: attachmentsDirectory.appending(path: "nota.txt", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )

        let withAttachment = """
        ---
        date: 2026-09-02
        tags:
          - type-note
          - type-email
          - topic-pratica
          - client-acme
          - source-email
        pergamenum-mail: 1
        pergamenum-mail-message-id: "\(Self.messageWithAttachmentID)"
        pergamenum-mail-direction: received
        pergamenum-mail-date: 2026-09-02T09:00:00+02:00
        pergamenum-mail-from: "Mario Rossi <m.rossi@acme.it>"
        pergamenum-mail-subject: "Con allegato"
        pergamenum-mail-attachments: ["[[nota.txt]]"]
        pergamenum-mail-body: complete
        ---

        Messaggio con un allegato.
        """
        try withAttachment.write(
            to: emailDirectory.appending(path: "con-allegato.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )

        let withoutAttachment = """
        ---
        date: 2026-09-02
        tags:
          - type-note
          - type-email
          - topic-pratica
          - client-acme
          - source-email
        pergamenum-mail: 1
        pergamenum-mail-message-id: "\(Self.messageWithoutAttachmentID)"
        pergamenum-mail-direction: received
        pergamenum-mail-date: 2026-09-02T09:15:00+02:00
        pergamenum-mail-from: "Mario Rossi <m.rossi@acme.it>"
        pergamenum-mail-subject: "Senza allegato"
        pergamenum-mail-body: complete
        ---

        Messaggio senza allegati.
        """
        try withoutAttachment.write(
            to: emailDirectory.appending(path: "senza-allegato.md", directoryHint: .notDirectory),
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

    // MARK: - PG-298, ADR-0070: Backspace excludes the selected message (R-01, R-02, R-08)

    /// R-01, R-02: Backspace on a collapsed row, then on an expanded one, each runs
    /// «Escludi dalla pratica» on the selected row and no other.
    func testBackspaceExcludesTheSelectedMessageCollapsedAndExpanded() throws {
        selectFirstPratica()

        clickTrailingHeaderArea(ofMessage: Self.messageWithoutAttachmentID)
        app.typeKey(.delete, modifierFlags: [])
        assertExcluded(Self.messageWithoutAttachmentID, noteFile: "senza-allegato.md")

        let chevron = element("pratiche-message-chevron-\(Self.hash(Self.messageWithAttachmentID))")
        XCTAssertTrue(chevron.waitForExistence(timeout: 5), "lo chevron del messaggio non è comparso")
        chevron.click()
        clickTrailingHeaderArea(ofMessage: Self.messageWithAttachmentID)
        app.typeKey(.delete, modifierFlags: [])
        assertExcluded(Self.messageWithAttachmentID, noteFile: "con-allegato.md")
    }

    /// R-08: keyboard focus survives a Quick Look preview. After a chip click opened the
    /// panel and Esc closed it, a click on a message row followed by Backspace still
    /// excludes that message - the one focus hand-off between the Quick Look host and the
    /// timeline's `List` that no other test observes (ADR-0070 §D5).
    func testBackspaceStillExcludesAfterAQuickLookPreview() throws {
        selectFirstPratica()

        let chip = element("pratiche-attachment-\(Self.hash(Self.messageWithAttachmentID))-0")
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "il chip dell'allegato non è comparso")
        chip.click()
        // The panel's own AX window title is "Quick Look", never the previewed file's name -
        // "nota.txt" is a `StaticText` label drawn inside the panel, not the window's title
        // (confirmed from a captured AX hierarchy on this exact failure).
        let panel = app.windows["Quick Look"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "il pannello Quick Look non è comparso")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(panel.waitForExistence(timeout: 5), "il pannello Quick Look non si è chiuso")

        // PG-307: the focus handed back to the timeline still reopens the last attachment on
        // a bare space, as it did while the host held the keyboard.
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "la barra spaziatrice non ha riaperto il pannello")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(panel.waitForExistence(timeout: 5), "il pannello Quick Look non si è richiuso")

        clickTrailingHeaderArea(ofMessage: Self.messageWithoutAttachmentID)
        app.typeKey(.delete, modifierFlags: [])
        assertExcluded(Self.messageWithoutAttachmentID, noteFile: "senza-allegato.md")
    }

    // MARK: - PG-298 helpers

    /// The header's trailing `Spacer`, not a button - the same coordinate Task 1's probe
    /// scenarios (S1/S2/S3) clicked, kept here so a click selects the row without landing
    /// on the chevron or a chip.
    private func clickTrailingHeaderArea(ofMessage messageID: String) {
        let row = element("pratiche-message-\(Self.hash(messageID))")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la riga del messaggio non è comparsa")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).click()
    }

    /// R-01/R-02/R-08's shared assertion: the row is gone, its `.md` left `email/`, and its
    /// `Message-ID` joined `pergamenum-dossier-excluded` in `pratica.md` (ADR-0068 §D12's
    /// own order of writes, untouched by this chain).
    private func assertExcluded(_ messageID: String, noteFile: String) {
        let row = element("pratiche-message-\(Self.hash(messageID))")
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "la riga esclusa è ancora nella timeline")
        let noteURL = vault.appending(
            path: "\(Self.praticaFolder)/email/\(noteFile)", directoryHint: .notDirectory
        )
        XCTAssertTrue(
            waitForFile(noteURL, toExist: false), "il file del messaggio è ancora in email/ dopo l'esclusione"
        )
        let praticaText = praticaDossierText()
        XCTAssertTrue(
            praticaText?.contains(messageID) ?? false,
            "il Message-ID escluso non compare in pergamenum-dossier-excluded di pratica.md"
        )
    }

    private func waitForFile(_ url: URL, toExist expected: Bool, timeout: TimeInterval = 6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) == expected {
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) == expected
    }

    private func praticaDossierText() -> String? {
        let url = vault.appending(path: "\(Self.praticaFolder)/pratica.md", directoryHint: .notDirectory)
        let deadline = Date().addingTimeInterval(6)
        repeat {
            if let text = try? String(contentsOf: url, encoding: .utf8), text.contains("pergamenum-dossier-excluded") {
                return text
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Mirrors `PraticaMessageRow.hash(of:)` exactly (FNV-1a over the message id string),
    /// as `AttachmentChipContextMenuUITests.hash(_:)` already does - this file computes the
    /// same identifiers production draws without a `@testable import`.
    private static func hash(_ messageID: String) -> String {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array(messageID.utf8) {
            value ^= UInt64(byte)
            value &*= 0x0000_0100_0000_01b3
        }
        return String(value, radix: 16)
    }
}
