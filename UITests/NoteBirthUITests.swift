import XCTest

/// The two links of PG-387 (N4) that only a real key window shows (plan
/// `docs/plans/pg-387-n4-birth-of-note.md`, Task 8; R-17 caps the GUI tests of this feature at
/// two): a menu shortcut reaching a pane and a list's keyboard focus, then a sheet over a key
/// window; and the first key landing at the caret a daily template placed.
///
/// Every other behaviour of the feature is covered in-process (`UnfiledListModelTests`,
/// `ClassifyNoteControllerTests`, `DailyNoteCaretTests` and the session tests); these two prove
/// the wiring those cannot reach. Both finish on the file on disk, since a result that is only
/// on screen is not written down.
final class NoteBirthUITests: PergamenumUITestCase {
    // MARK: Filing a capture (ADR-0085 §D11; R-01, R-03)

    /// Ctrl+Cmd+I opens «Da classificare», Down and Return reach the row's «Classifica…», the
    /// sheet takes a topic and a folder, and the note leaves the pane having moved.
    func testFilingACaptureFromDaClassificare() throws {
        try makeTemporaryVault(prefix: "NoteBirthUITest")
        try write("""
            ---
            date: 2026-10-12
            tags:
              - type-note
              - status-inbox
            ---

            # Idea

            Un pensiero da sistemare.

            """, to: "00 Inbox/Idea.md")
        // The folder picker lists the folders of indexed notes (`VaultSession.folders`), so an empty
        // directory is not offered: «03 Risorse» holds one already-filed note, with no `status-inbox`
        // so the pane still ends with no row once Idea.md has left it.
        try write("""
            ---
            date: 2026-10-01
            tags:
              - type-note
              - topic-archivio
            ---

            # Archivio

            """, to: "03 Risorse/Archivio.md")

        launchApp()
        waitForMainWindow()

        app.typeKey("i", modifierFlags: [.control, .command])
        XCTAssertTrue(element("unfiled-pane").waitForExistence(timeout: 5), "«Da classificare» non si è aperta")
        XCTAssertTrue(element("unfiled-row").waitForExistence(timeout: 5), "la cattura non compare tra le righe")

        // The list holds the keyboard on appear (ADR-0070): no click on the row.
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])

        let topic = element("note-classifica-topic")
        XCTAssertTrue(topic.waitForExistence(timeout: 5), "Invio sulla riga non ha aperto la scheda «Classifica»")
        topic.click()
        topic.typeText("materiali")
        // Return commits the typed text as a chip; the confirm stays disabled until one exists.
        app.typeKey(.return, modifierFlags: [])

        let folder = element("note-classifica-folder")
        XCTAssertTrue(folder.waitForExistence(timeout: 5), "manca la scelta della cartella")
        folder.click()
        let target = app.menuItems["03 Risorse"].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5), "«03 Risorse» non è tra le cartelle offerte")
        target.click()

        let confirm = element("note-classifica-confirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "manca il pulsante di conferma")
        confirm.click()

        XCTAssertTrue(
            waitFor { exists("03 Risorse/Idea.md") && !exists("00 Inbox/Idea.md") },
            "la nota non è stata spostata in «03 Risorse»"
        )
        let filed = try XCTUnwrap(
            try? String(contentsOf: vault.appending(path: "03 Risorse/Idea.md"), encoding: .utf8)
        )
        XCTAssertTrue(filed.contains("topic-materiali"), "l'argomento non è nel frontmatter:\n\(filed)")
        XCTAssertFalse(filed.contains("status-inbox"), "status-inbox è rimasto nel frontmatter:\n\(filed)")
        XCTAssertTrue(
            element("unfiled-row").waitForNonExistence(timeout: 5),
            "la nota classificata è ancora nel pannello"
        )
    }

    // MARK: The daily template's caret (ADR-0086 §D8; R-06, R-08)

    /// Cmd+Shift+D creates today's note from the template and puts the caret on `{{cursor}}`, so
    /// the first thing typed lands between the two headings rather than at the top.
    func testTheDailyTemplatePlacesTheCaret() throws {
        try makeTemporaryVault(prefix: "NoteBirthUITest")
        try write("""
            ---
            tags:
              - type-note
            ---

            ## {{time}}

            {{cursor}}

            ## Note

            """, to: "Templates/Giornata.md")
        try write(#"{"dailyTemplate": "Templates/Giornata.md"}"#, to: ".pergamenum/settings.json")

        launchApp()
        waitForMainWindow()

        app.typeKey("d", modifierFlags: [.command, .shift])
        // The note exists on disk as soon as the day is born, before anything is typed.
        XCTAssertTrue(waitFor { exists(dailyPath) }, "la nota del giorno non è stata creata")

        // The editor is on screen before the first key, and is not clicked: a click would move the
        // caret this test exists to prove (the caret request takes the keyboard, ADR-0086 §D4).
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "l'editor non è comparso")

        app.typeText("Primo appunto")
        app.typeKey("s", modifierFlags: .command)

        XCTAssertTrue(
            waitFor { (try? text(dailyPath))?.contains("Primo appunto") == true },
            "il testo digitato non è arrivato nel file del giorno"
        )
        let written = try text(dailyPath)
        XCTAssertFalse(written.contains("{{"), "è rimasto un segnaposto nel file:\n\(written)")

        let lines = written.components(separatedBy: "\n")
        let typed = try XCTUnwrap(lines.firstIndex { $0.contains("Primo appunto") }, "riga non trovata:\n\(written)")
        let before = lines[..<typed].last { !$0.isEmpty }
        let after = lines[(typed + 1)...].first { !$0.isEmpty }
        XCTAssertNotNil(
            before?.range(of: #"^## \d{2}:\d{2}$"#, options: .regularExpression),
            "il testo non segue il titolo con l'ora:\n\(written)"
        )
        XCTAssertEqual(after, "## Note", "il testo non precede «## Note»:\n\(written)")
        XCTAssertEqual(lines[typed], "Primo appunto", "il testo non è solo sulla riga del cursore:\n\(written)")
    }

    // MARK: Support

    /// `Calendar/<yyyyMMdd>.md`, in the machine's own zone because `CalendarDate.today` is.
    private var dailyPath: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = .current
        return "Calendar/\(formatter.string(from: Date())).md"
    }

    private func write(_ contents: String, to relativePath: String) throws {
        let url = vault.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func text(_ relativePath: String) throws -> String {
        try String(contentsOf: vault.appending(path: relativePath, directoryHint: .notDirectory), encoding: .utf8)
    }

    private func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: vault.appending(path: relativePath, directoryHint: .notDirectory).path)
    }

    /// Polls, because the write happens on the app's side of the process boundary.
    private func waitFor(timeout: TimeInterval = 8, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return false
    }
}
