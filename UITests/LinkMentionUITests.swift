import XCTest

/// N3 (R-26, ADR-0084 §D7): «Collega» on an unlinked mention, end to end - the scan, the row's
/// button, the diff sheet, the confirm. The write itself, its refusals and the diff text are the
/// unit suite's (`LinkMentionReviewTests`, the session and connector tests); what only a real window
/// proves is that the buttons are reachable in the inspector and that the index catches up, so the
/// note that now links shows among the backlinks.
final class LinkMentionUITests: PergamenumUITestCase {
    private let header = """
        ---
        date: 2026-09-09
        tags:
          - type-note
        ---


        """

    override func setUpWithError() throws {
        try super.setUpWithError()
        try makeTemporaryVault(prefix: "LinkMentionUITest")
        try (header + "Il tema della pagina.").write(
            to: vault.appending(path: "Curva.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
        // Names «Curva» in prose, once, spelled as the title and not linked.
        try (header + "La prova misura la Curva di carico.").write(
            to: vault.appending(path: "Prova.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )
        launchApp()
        waitForMainWindow()
    }

    func testCollegaLinksTheMentionAfterTheDiff() throws {
        let note = noteRow("Curva.md")
        XCTAssertTrue(note.waitForExistence(timeout: 10), "la nota 'Curva' non è nell'elenco")
        note.click()

        let scan = element("unlinked-mentions-scan")
        XCTAssertTrue(scan.waitForExistence(timeout: 5), "manca il pulsante di ricerca delle menzioni")
        scan.click()

        let collega = element("unlinked-mention-link-Prova.md")
        XCTAssertTrue(collega.waitForExistence(timeout: 5), "la menzione in 'Prova' non è fra i risultati")
        collega.click()

        let confirm = element("link-mention-confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "il foglio del confronto non è comparso")
        confirm.click()

        // The file is the proof: read by the test, which made the vault.
        let file = vault.appending(path: "Prova.md", directoryHint: .notDirectory)
        let deadline = Date().addingTimeInterval(5)
        var text = ""
        while Date() < deadline {
            text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            if text.contains("[[Curva]]") { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(text.contains("[[Curva]]"), "«Collega» non ha scritto [[Curva]] in 'Prova':\n\(text)")

        XCTAssertTrue(
            element("backlink-row-Prova.md").waitForExistence(timeout: 10),
            "'Prova' non compare fra i backlink dopo «Collega»"
        )
    }
}
