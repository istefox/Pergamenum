import XCTest

// PG-134/#234: `AttachmentChip`'s `.contextMenu` used to hard-code «Mostra nel Finder»/
// «Copia» instead of reading `AttachmentChipModel.contextMenuTitles`, the catalogue that
// exists specifically to be the one source of truth for those two entries
// (`AttachmentChipModel.swift:105`). `Tests/AttachmentChipTests.swift:174` only checked
// the catalogue against itself, so a future edit to one side could drift from the other
// without either suite noticing. This test drives the actual rendered menu, the one seam
// a unit test cannot reach (a `.contextMenu`'s entries are `NSMenuItem`s outside the
// chip's own accessibility subtree - `SidebarDeleteUITests`' documented convention).
//
// Deterministic: one fixture pratica with one message carrying one attachment already
// placed in `allegati/` (`.txt`, an extension `AttachmentIntegrity` has no signature
// table for, so any non-empty file reads `.usable` - no real Mail store, no timing-
// dependent sync).
final class AttachmentChipContextMenuUITests: XCTestCase {
    private static let praticaFolder = "01 Progetti/Acme/Offerta 118"

    private var vault: URL!
    private var stateBase: URL!
    private var mailStoreRoot: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory())
            .appending(path: "AttachmentChipMenuUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try seedFixturePraticaWithAttachment()

        app = XCUIApplication()
        stateBase = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)
        mailStoreRoot = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-mailstore", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: mailStoreRoot, withIntermediateDirectories: true)

        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES",
                               "-disableUpdater", "YES",
                               "-mailStoreRoot", mailStoreRoot.path(percentEncoded: false),
                               "-stateBase", stateBase.path(percentEncoded: false)]
        app.launch()
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10), "il vault non si è aperto")
        showPratiche()
        selectFixturePratica()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
        try? FileManager.default.removeItem(at: mailStoreRoot)
    }

    func testAttachmentChipContextMenuShowsBothCatalogueEntries() throws {
        let chip = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "pratiche-attachment-"))
            .firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "il chip dell'allegato non è comparso")
        chip.rightClick()

        // Literal titles, not `AttachmentChipModel.contextMenuTitles` itself (this
        // target has no `@testable import Pergamenum`, same as every other UI test -
        // SidebarDeleteUITests' documented convention: a `.contextMenu` entry is found
        // by its production title). What this exercises that the unit test at
        // `Tests/AttachmentChipTests.swift:174` cannot: the real rendered menu of the
        // real running view, not the model constant compared to itself.
        let revealItem = app.menuItems["Mostra nel Finder"]
        XCTAssertTrue(revealItem.waitForExistence(timeout: 5), "manca la voce «Mostra nel Finder» nel menu contestuale")
        let copyItem = app.menuItems["Copia"]
        XCTAssertTrue(copyItem.waitForExistence(timeout: 5), "manca la voce «Copia» nel menu contestuale")
    }

    // MARK: - Navigation

    private func showPratiche() {
        let row = app.staticTexts["Pratiche"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la sezione Pratiche non è nella barra laterale")
        row.click()
        XCTAssertTrue(
            element("pratiche-pane").waitForExistence(timeout: 5),
            "la sezione Pratiche non si è aperta"
        )
    }

    private func selectFixturePratica() {
        let row = element("pratiche-row-\(Self.praticaFolder)")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la riga della pratica fixture non è nella lista")
        row.click()
        XCTAssertTrue(
            element("pratiche-timeline").waitForExistence(timeout: 5),
            "la timeline non si è aperta dopo la selezione della pratica"
        )
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    // MARK: - Fixture

    /// Same shape as `PraticheUITests.seedFixturePratica`, plus one message under
    /// `email/` naming one attachment already placed in `allegati/` (ADR-0040 §D3's
    /// wikilink form, `[[nota.txt]]` - a placed entry, never a pending one).
    private func seedFixturePraticaWithAttachment() throws {
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

        // No signature table in `AttachmentIntegrity` for `.txt`: any non-empty file
        // reads `.usable`, so the chip's «Mostra nel Finder»/«Copia» are both enabled
        // rather than disabled-and-unreachable by a right-click.
        try "contenuto".write(
            to: attachmentsDirectory.appending(path: "nota.txt", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )

        let messageNote = """
        ---
        date: 2026-09-02
        tags:
          - type-note
          - type-email
          - topic-pratica
          - client-acme
          - source-email
        pergamenum-mail: 1
        pergamenum-mail-message-id: "<gui-test@example.com>"
        pergamenum-mail-direction: received
        pergamenum-mail-date: 2026-09-02T09:00:00+02:00
        pergamenum-mail-from: "Mario Rossi <m.rossi@acme.it>"
        pergamenum-mail-subject: "Offerta 118"
        pergamenum-mail-attachments: ["[[nota.txt]]"]
        pergamenum-mail-body: complete
        ---

        Buongiorno, in allegato l'offerta.
        """
        try messageNote.write(
            to: emailDirectory.appending(path: "messaggio.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
    }
}
