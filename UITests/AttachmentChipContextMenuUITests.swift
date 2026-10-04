import XCTest

// PG-134/#234 added this class to drive the chip's real rendered menu. PG-285 found that
// menu had never been reachable: the chip lives inside a timeline `List` row whose own
// `.contextMenu` took every right-click in the row, so a right-click on the chip opened
// the message menu instead. ADR-0069 moved the chip's menu to AppKit
// (`AttachmentChipMenuHost`). The catalogue, the menu's items and the menu view's presence
// on each chip are pinned in-process (`Tests/AttachmentChipTests.swift`,
// `Tests/AttachmentChipMenuTests.swift`); which menu a real right-click opens inside a live
// `List` is the one fact only this class observes, and it has two halves, one per test
// (ADR-0069 §D6 justifies both GUI tests):
//
// - `testAttachmentChipContextMenuShowsBothCatalogueEntries`: a right-click on the chip
//   opens the chip's menu, all four entries, and not the message menu (R-01).
// - `testRightClickBesideTheChipStillOpensTheMessageMenu`: a right-click on the subject,
//   in the same header line as the chip, still opens the message menu and not the chip's
//   (R-02).
// - `testLeftClickOnPendingChipOpensThePendingPopover`: a left click on a `.pending` chip
//   still opens its explanatory popover, which is the one thing the plan's own residual
//   risk (F11: "no GUI test clicks a chip") left unwitnessed - the overlay's `hitTest`
//   must let a plain left click straight through to the chip underneath. Justified as
//   the third GUI test for this feature (ADR-0069 §D6): it is the only mechanism this
//   chain could not verify in advance, and the two catalogue tests above say nothing
//   about it.
//
// Menu entries are `NSMenuItem`s outside the chip's own accessibility subtree, found by
// their production title (`SidebarDeleteUITests`' documented convention).
//
// Deterministic: one fixture pratica with one message carrying one attachment already
// placed in `allegati/` (`.txt`, an extension `AttachmentIntegrity` has no signature
// table for, so any non-empty file reads `.usable`) plus one message with a pending
// attachment (ADR-0040 §D8's bare-name form) - no real Mail store, no timing-dependent
// sync.
final class AttachmentChipContextMenuUITests: PergamenumUITestCase {
    private static let praticaFolder = "01 Progetti/Acme/Offerta 118"
    private static let usableMessageID = "<gui-test@example.com>"
    private static let pendingMessageID = "<gui-test-pending@example.com>"

    override func setUpWithError() throws {
        try super.setUpWithError()
        try makeTemporaryVault(prefix: "AttachmentChipMenuUITest")
        try seedFixturePraticaWithAttachment()

        launchApp()
        waitForMainWindow()
        showPratiche()
        selectFixturePratica()
    }

    func testAttachmentChipContextMenuShowsBothCatalogueEntries() throws {
        // Pinned to the usable message's own chip by its hashed identifier: the fixture
        // now also carries a pending chip for M5, and a bare `.firstMatch` on the
        // identifier prefix would no longer be guaranteed to land on this one.
        let chip = element("pratiche-attachment-\(Self.hash(Self.usableMessageID))-0")
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "il chip dell'allegato non è comparso")
        chip.rightClick()

        // Literal titles, not `AttachmentChipModel.contextMenuTitles` itself (this
        // target has no `@testable import Pergamenum`, same as every other UI test -
        // SidebarDeleteUITests' documented convention: a `.contextMenu` entry is found
        // by its production title). What this exercises that the unit test at
        // `Tests/AttachmentChipTests.swift:174` cannot: the real rendered menu of the
        // real running view, not the model constant compared to itself.
        // Counted in context menus only, `contextMenuItemCount(_:)` says why.
        XCTAssertTrue(
            waitForContextMenuItem("Mostra nel Finder"), "manca la voce «Mostra nel Finder» nel menu contestuale"
        )
        XCTAssertEqual(contextMenuItemCount("Copia"), 1, "manca la voce «Copia» nel menu contestuale")

        // PG-285: the chip's whole menu, and not the message menu in its place. «Anteprima
        // allegato» alone cannot tell the two apart, since the row menu carries it too
        // (`MessageCommand.previewAttachment`): the distinction rests on «Apri» being there
        // and «Escludi dalla pratica» counting zero.
        XCTAssertEqual(
            contextMenuItemCount("Anteprima allegato"), 1, "manca la voce «Anteprima allegato» nel menu del chip"
        )
        XCTAssertEqual(contextMenuItemCount("Apri"), 1, "manca la voce «Apri» nel menu del chip")
        XCTAssertEqual(
            contextMenuItemCount("Escludi dalla pratica"), 0,
            "si è aperto il menu del messaggio invece di quello del chip"
        )
        app.typeKey(.escape, modifierFlags: [])
    }

    /// R-02 (ADR-0069 §D6): the chip's menu stays on the chip. A right-click on the subject,
    /// in the same header line as the chip, still opens the message menu. Pinned to the
    /// usable message's own subject, same reason as the test above.
    func testRightClickBesideTheChipStillOpensTheMessageMenu() throws {
        let subject = element("pratiche-message-subject-\(Self.hash(Self.usableMessageID))")
        XCTAssertTrue(subject.waitForExistence(timeout: 5), "l'oggetto del messaggio non è comparso")
        subject.rightClick()

        XCTAssertTrue(
            waitForContextMenuItem("Escludi dalla pratica"),
            "il clic destro accanto al chip non ha aperto il menu del messaggio"
        )
        XCTAssertEqual(
            contextMenuItemCount("Mostra nel Finder"), 0,
            "il clic destro accanto al chip ha aperto il menu del chip"
        )
        app.typeKey(.escape, modifierFlags: [])
    }

    /// M5 (plan Task 7's hand-check table; ADR-0069 §D6 justifies this as the feature's
    /// third GUI test): a left click on the overlay must still reach the chip
    /// underneath, or the pending popover (`AttachmentChip.isShowingPendingExplanation`)
    /// would never open again once the AppKit overlay sat over every chip. This is the
    /// one mechanism the plan's own risk list (F11) named as unverified by any GUI test.
    func testLeftClickOnPendingChipOpensThePendingPopover() throws {
        let chip = element("pratiche-attachment-\(Self.hash(Self.pendingMessageID))-0")
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "il chip in attesa non è comparso")
        chip.click()

        XCTAssertTrue(
            app.staticTexts["L'allegato non è ancora disponibile in Mail. "
                + "Verrà riprovato alla prossima sincronizzazione."].waitForExistence(timeout: 5),
            "il popover dell'allegato in attesa non è comparso dopo il clic sinistro"
        )
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Navigation

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

    // MARK: - Context-menu lookup

    /// How many items titled `title` are open in a context menu, the menu bar's left out. The
    /// menu bar is always in the accessibility tree, and since PG-263 (#849) File has its own
    /// «Mostra nel Finder» beside Modifica's «Copia»: an app-wide `app.menuItems[title].exists`
    /// is true for those whether or not the chip's menu opened, so it proves nothing about it,
    /// and a check that the chip's menu stayed shut fails on the menu bar instead.
    private func contextMenuItemCount(_ title: String) -> Int {
        // One predicate per query: `matching(_:)` takes it as `sending`, so it cannot be shared.
        func titled() -> NSPredicate { NSPredicate(format: "title == %@ OR label == %@", title, title) }
        let everywhere = app.menuItems.matching(titled()).count
        let inMenuBar = app.menuBars.descendants(matching: .menuItem).matching(titled()).count
        return everywhere - inMenuBar
    }

    /// Waits up to five seconds for `title` to show in an open context menu.
    private func waitForContextMenuItem(_ title: String) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if contextMenuItemCount(title) > 0 { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return false
    }

    /// Mirrors `PraticaMessageRow.hash(of:)` exactly (FNV-1a over the message id
    /// string), so this file computes the same identifiers production draws without a
    /// `@testable import` - every UI test in this suite follows this convention rather
    /// than reaching into the production module.
    private static func hash(_ messageID: String) -> String {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array(messageID.utf8) {
            value ^= UInt64(byte)
            value &*= 0x0000_0100_0000_01b3
        }
        return String(value, radix: 16)
    }

    // MARK: - Fixture

    /// Same shape as `PraticheUITests.seedFixturePratica`, plus two messages under
    /// `email/`: one naming an attachment already placed in `allegati/` (ADR-0040 §D3's
    /// wikilink form, `[[nota.txt]]`), one naming a pending attachment (the bare-name
    /// form) for M5's left-click-through check.
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
        pergamenum-mail-message-id: "\(Self.usableMessageID)"
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

        // A second message, later the same morning, carrying a pending attachment (the
        // bare-name form, ADR-0040 §D8) rather than a placed one - M5's chip.
        let pendingMessageNote = """
        ---
        date: 2026-09-02
        tags:
          - type-note
          - type-email
          - topic-pratica
          - client-acme
          - source-email
        pergamenum-mail: 1
        pergamenum-mail-message-id: "\(Self.pendingMessageID)"
        pergamenum-mail-direction: received
        pergamenum-mail-date: 2026-09-02T09:15:00+02:00
        pergamenum-mail-from: "Mario Rossi <m.rossi@acme.it>"
        pergamenum-mail-subject: "Preventivo"
        pergamenum-mail-attachments: ["attesa.pdf"]
        pergamenum-mail-body: complete
        ---

        Preventivo in arrivo, a breve l'allegato.
        """
        try pendingMessageNote.write(
            to: emailDirectory.appending(path: "messaggio-pending.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
    }
}
