import AppKit
import XCTest

/// A picture embedded in a note, seen inside the app.
///
/// Inserting one already worked - the Inserisci menu and the drop both copy the file
/// into the vault and write `![[nome.png]]` - but nothing ever drew it: the editor shows
/// the source by design (SPEC §5) and reading mode rendered the embed as a label.
final class NoteImageUITests: XCTestCase {
    private var vault: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        vault = URL(filePath: NSTemporaryDirectory()).appending(path: "NoteImageUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)

        try Self.png(width: 240, height: 120).write(to: vault.appending(path: "foto.png"))
        try """
        ---
        date: 2026-08-14
        tags:
          - type-note
        ---

        # Sopralluogo

        ![Pressa 4](foto.png)

        ![[assente.png]]
        """.write(
            to: vault.appending(path: "20260814_Nota_Immagine.md"),
            atomically: true, encoding: .utf8
        )

        app = XCUIApplication()
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
    }

    func testReadingModeDrawsTheEmbeddedPictureAndSaysWhenOneIsMissing() throws {
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
        let note = app.staticTexts.matching(
            NSPredicate(format: "value == %@", "20260814_Nota_Immagine")
        ).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10), "la nota di prova non è nell'elenco")
        note.click()

        // The editor shows the source and no picture: that is the mode's whole job.
        XCTAssertTrue(app.radioButtons["Lettura"].waitForExistence(timeout: 5))
        XCTAssertFalse(embed.exists, "l'editor sta disegnando l'immagine")

        app.radioButtons["Lettura"].click()
        XCTAssertTrue(embed.waitForExistence(timeout: 10), "l'immagine non è disegnata in lettura")
        XCTAssertTrue(
            app.staticTexts["Pressa 4"].exists,
            "la didascalia dell'immagine non c'è"
        )
        // A file the vault does not have is said out loud rather than left as a gap.
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "note-embed-missing")
                .firstMatch.waitForExistence(timeout: 5),
            "l'embed rotto non è segnalato"
        )

        app.radioButtons["Modifica"].click()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5), "l'editor non è tornato")
        XCTAssertFalse(embed.exists, "l'immagine è rimasta sullo schermo con l'editor")
    }

    private var embed: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "note-embed").firstMatch
    }

    /// A real PNG, so Quick Look has something it can actually render: a file with the
    /// right extension and the wrong bytes would test the placeholder, not the picture.
    private static func png(width: Int, height: Int) throws -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}
