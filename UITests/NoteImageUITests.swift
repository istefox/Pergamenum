import AppKit
import XCTest

/// A picture embedded in a note, seen inside the app.
///
/// Inserting one already worked - the Inserisci menu and the drop both copy the file
/// into the vault and write `![[nome.png]]` - and reading mode has long drawn it as a
/// real picture rather than a label. ADR-0018 slice 3 closed the editor's own half of
/// that gap: with `hidesMarkup` on (the vault's own default), a resolved image or PDF
/// is drawn in the run's own place too, rather than left as raw syntax.
final class NoteImageUITests: XCTestCase {
    private var vault: URL!
    private var stateBase: URL!
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
        stateBase = URL(filePath: NSTemporaryDirectory())
            .appending(path: vault.lastPathComponent + "-state", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: stateBase, withIntermediateDirectories: true)
        app.launchArguments = ["-recentVaults", "(\"\(vault.path(percentEncoded: false))\")",
                               "-disableCalendar", "YES",
                               "-stateBase", stateBase.path(percentEncoded: false)]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
    }

    func testReadingModeDrawsTheEmbeddedPictureAndSaysWhenOneIsMissing() throws {
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
        let note = app.staticTexts.matching(
            NSPredicate(format: "value == %@", "20260814_Nota_Immagine")
        ).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10), "la nota di prova non è nell'elenco")
        note.click()

        // `hidesMarkup` is on by default, so the editor draws the picture in the run's
        // own place too (ADR-0018 slice 3) - Lettura is no longer the only mode that does.
        XCTAssertTrue(app.radioButtons["Lettura"].waitForExistence(timeout: 5))
        XCTAssertTrue(editorEmbed.waitForExistence(timeout: 5), "l'editor non sta disegnando l'immagine")

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
        XCTAssertTrue(
            editorEmbed.waitForExistence(timeout: 5), "l'editor non è tornato a disegnare l'immagine"
        )
    }

    private var embed: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "note-embed").firstMatch
    }

    /// The editor's own drawn embed (ADR-0018 slice 3), distinct from `embed` above: that
    /// one is `EmbeddedFileView`'s, Lettura's SwiftUI reading view, and never appears while
    /// the editor is on screen. This one is the `NSAccessibilityElement` a resolved image
    /// or PDF carries once `EditorDecorationDelegate` collapses its run into a picture.
    private var editorEmbed: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "editor-embed").firstMatch
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
