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
                               "-disableUpdater", "YES",
                               "-stateBase", stateBase.path(percentEncoded: false)]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: stateBase)
    }

    func testTheEditorDrawsTheEmbeddedPictureAndSaysWhenOneIsMissing() throws {
        XCTAssertTrue(app.staticTexts["Note"].waitForExistence(timeout: 10))
        let note = app.staticTexts.matching(
            NSPredicate(format: "value == %@", "20260814_Nota_Immagine")
        ).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10), "la nota di prova non è nell'elenco")
        note.click()

        // ADR-0029: no Lettura toggle to switch to any more - `hidesMarkup` is on by
        // default, so the one editor draws both embeds directly. Both share the same
        // "editor-embed" identifier (`CompletingTextView+Accessibility.swift`), unlike
        // Lettura's own separate "note-embed"/"note-embed-missing" - a drawn picture and
        // a `.missing` placeholder are told apart only by their own accessibility label.
        XCTAssertTrue(editorEmbeds.firstMatch.waitForExistence(timeout: 5), "l'editor non sta disegnando le immagini")
        let labels = (0..<editorEmbeds.count).map { editorEmbeds.element(boundBy: $0).label }
        XCTAssertTrue(labels.contains("Pressa 4"), "la didascalia dell'immagine disegnata non c'è: \(labels)")
        XCTAssertTrue(labels.contains("assente.png"), "il file mancante non è segnalato: \(labels)")
    }

    /// The editor's own drawn embeds (ADR-0018 slice 3): the `NSAccessibilityElement`s a
    /// resolved image or PDF, and a `.missing` placeholder, each carry once
    /// `EditorDecorationDelegate` collapses their run into a picture.
    private var editorEmbeds: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "editor-embed")
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
