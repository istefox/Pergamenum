import XCTest

// `PraticheUITests`'s fixture and helpers, split out of `PraticheUITests.swift` in ADR-0045's
// `Type+Aspect.swift` shape so neither file trips SwiftLint's `file_length` (PG-364). The tests
// themselves stay in `PraticheUITests.swift`, unchanged. A member below that the tests call is
// `internal` rather than `private`, since `private` does not reach across files; each says so.
extension PraticheUITests {
    /// Not `private`: `PraticheUITests.swift`'s `setUpWithError` calls it.
    func showPratiche() {
        let row = app.staticTexts["Pratiche"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la sezione Pratiche non è nella barra laterale")
        row.click()
        XCTAssertTrue(
            element("pratiche-pane").waitForExistence(timeout: 5),
            "la sezione Pratiche non si è aperta"
        )
    }

    /// Not `private`: `PraticheUITests.swift`'s tests call it.
    func element(_ identifier: String) -> XCUIElement {
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
    ///
    /// Not `private`: `PraticheUITests.swift`'s `setUpWithError` calls it.
    func seedFixturePratica() throws {
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

        // The second paragraph is drawn only when the row is expanded: the collapsed preview is
        // the body's first line (`PraticheController.firstLine(of:)`), so it never matches
        // (`testDoubleClickTogglesMessageRow`).
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

        Seconda riga del corpo.
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
    /// Not `private`: `PraticheUITests.swift`'s tests call it.
    func selectFirstPratica() {
        let row = element("pratiche-row-\(Self.praticaFolder)")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la riga della pratica fixture non è nella lista")
        row.click()
        XCTAssertTrue(
            element("pratiche-timeline").waitForExistence(timeout: 5),
            "la timeline non si è aperta dopo la selezione della pratica"
        )
    }

    // MARK: - PG-298 helpers

    /// The header's trailing `Spacer`, not a button - the same coordinate Task 1's probe
    /// scenarios (S1/S2/S3) clicked, kept here so a click selects the row without landing
    /// on the chevron or a chip.
    /// Not `private`: `PraticheUITests.swift`'s tests call it.
    func clickTrailingHeaderArea(ofMessage messageID: String) {
        trailingHeaderArea(ofMessage: messageID).click()
    }

    /// The same trailing column, on the chevron's own line: an expanded row's middle is its
    /// body, where a double-click selects a word instead of toggling the row (ADR-0076 notes).
    /// Not `private`: `PraticheUITests.swift`'s tests call it.
    func doubleClickTrailingHeaderArea(ofMessage messageID: String) {
        trailingHeaderArea(ofMessage: messageID, onHeaderLine: true).doubleClick()
    }

    private func trailingHeaderArea(ofMessage messageID: String, onHeaderLine: Bool = false) -> XCUICoordinate {
        let row = element("pratiche-message-\(Self.hash(messageID))")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la riga del messaggio non è comparsa")
        var dy: CGFloat = 0.5
        if onHeaderLine {
            let chevron = element("pratiche-message-chevron-\(Self.hash(messageID))")
            XCTAssertTrue(chevron.waitForExistence(timeout: 5), "lo chevron del messaggio non è comparso")
            dy = (chevron.frame.midY - row.frame.minY) / row.frame.height
        }
        return row.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: dy))
    }

    /// Whether the row's chevron says «Espandi» or «Comprimi» within the timeout - its
    /// accessibility label, the one carrier of the row's state that is not body text.
    /// Not `private`: `PraticheUITests.swift`'s tests call it.
    func waitForChevron(ofMessage messageID: String, label: String) -> Bool {
        let chevron = element("pratiche-message-chevron-\(Self.hash(messageID))")
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label), object: chevron
        )
        return XCTWaiter().wait(for: [expectation], timeout: 5) == .completed
    }

    /// R-01/R-02/R-08's shared assertion: the row is gone, its `.md` left `email/`, and its
    /// `Message-ID` joined `pergamenum-dossier-excluded` in `pratica.md` (ADR-0068 §D12's
    /// own order of writes, untouched by this chain).
    /// Not `private`: `PraticheUITests.swift`'s tests call it.
    func assertExcluded(_ messageID: String, noteFile: String) {
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

    /// PG-306: the opposite of `assertExcluded`, held for two seconds so an exclusion that
    /// lands late is still caught: the row is there and its `.md` never left `email/`.
    /// Not `private`: `PraticheUITests.swift`'s tests call it.
    func assertStillInPratica(_ messageID: String, noteFile: String) {
        let row = element("pratiche-message-\(Self.hash(messageID))")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "la riga del messaggio non è più nella timeline")
        let noteURL = vault.appending(
            path: "\(Self.praticaFolder)/email/\(noteFile)", directoryHint: .notDirectory
        )
        XCTAssertFalse(
            waitForFile(noteURL, toExist: false, timeout: 2), "il messaggio è stato escluso senza volerlo"
        )
        XCTAssertTrue(row.exists, "la riga del messaggio è sparita dalla timeline")
    }

    /// PG-306, M7: the undo of an exclusion - the row is back, its `.md` is back in `email/`,
    /// and its `Message-ID` left `pergamenum-dossier-excluded`.
    /// Not `private`: `PraticheUITests.swift`'s tests call it.
    func assertRestored(_ messageID: String, noteFile: String) {
        let row = element("pratiche-message-\(Self.hash(messageID))")
        XCTAssertTrue(row.waitForExistence(timeout: 6), "«Annulla» non ha riportato la riga nella timeline")
        let noteURL = vault.appending(
            path: "\(Self.praticaFolder)/email/\(noteFile)", directoryHint: .notDirectory
        )
        XCTAssertTrue(waitForFile(noteURL, toExist: true), "«Annulla» non ha riportato il file in email/")
        let praticaURL = vault.appending(path: "\(Self.praticaFolder)/pratica.md", directoryHint: .notDirectory)
        let deadline = Date().addingTimeInterval(6)
        var text = try? String(contentsOf: praticaURL, encoding: .utf8)
        while text?.contains(messageID) ?? true, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
            text = try? String(contentsOf: praticaURL, encoding: .utf8)
        }
        XCTAssertFalse(text?.contains(messageID) ?? true, "il Message-ID è ancora escluso in pratica.md dopo «Annulla»")
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
    /// Not `private`: `PraticheUITests.swift`'s tests call it.
    static func hash(_ messageID: String) -> String {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array(messageID.utf8) {
            value ^= UInt64(byte)
            value &*= 0x0000_0100_0000_01b3
        }
        return String(value, radix: 16)
    }
}
