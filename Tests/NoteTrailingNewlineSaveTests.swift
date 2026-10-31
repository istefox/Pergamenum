import AppKit
import Foundation
import Testing
@testable import Pergamenum

// PG-424: pins only, not a fix and not a reproduction. The first save of a note whose text ends in
// a trailing newline was seen once to remove it (50455 to 50454 bytes), and a click was seen to
// leave the editor reading «Non salvato». The cause is unattributed and neither symptom reproduces
// here, so these pin what the save path must hold whatever the cause was: the buffer reaches the
// disk byte for byte, a trailing newline included (LF, and CRLF with its `\r`), and a note nobody
// edited is neither dirty nor written. The two click tests prove only that the styling and reveal
// passes, and on the synthetic 50 KB note the hooks of a click and the caret placement after it,
// do not write the binding.
//
// Not covered by any test: the path from an edit in the AppKit text view, through the binding, to
// what `NoteSaveIndicator` displays in the top bar. The indicator's own mapping from dirty and
// clean to its label is `NoteSaveIndicatorTests`'; what feeds it from a live text view is not.

private let bodyWithNewline = quitNote("Corpo del testo.\n")
private let bodyWithTwoNewlines = quitNote("Corpo del testo.\n\n")

@MainActor
private func controller(
    _ vault: borrowing TemporaryVault, files: [String: String]
) async throws -> VaultController {
    for (path, text) in files { try vault.write(text, to: path) }
    return try await quitController(vault)
}

private func bytes(_ root: URL, _ path: String) throws -> Data {
    try Data(contentsOf: root.appending(path: path, directoryHint: .notDirectory))
}

@MainActor
@Test func anEditedNoteWithATrailingNewlineIsWrittenByteForByte() async throws {
    for (path, original) in [("Finale.md", bodyWithNewline), ("Doppio.md", bodyWithTwoNewlines)] {
        let vault = try TemporaryVault()
        let root = vault.root
        let controller = try await controller(vault, files: [path: original])
        controller.openNote(at: path)
        let id = try #require(controller.focusedTab?.id)
        #expect(controller.openNote?.text == original, "\(path): la nota aperta non e il file")
        #expect(controller.openNote?.hasUnsavedChanges == false, "\(path): sporca appena aperta")

        let edited = original.replacingOccurrences(of: "Corpo", with: "Il corpo")
        controller.updateOpenNoteText(edited)
        #expect(await controller.saveTab(id) == .saved)

        let onDisk = try bytes(root, path)
        #expect(onDisk == Data(edited.utf8), "\(path): i byte su disco non sono quelli del buffer")
        #expect(onDisk.count == Data(original.utf8).count + 3, "\(path): la dimensione")
        #expect(onDisk.last == 0x0A, "\(path): il fine riga finale e sparito")
        #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == false, "\(path): resta «Non salvato»")
        controller.close()
    }
}

@MainActor
@Test func aNoteWhoseTextWasSetBackToItsOwnIsCleanAndNeverWritten() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await controller(vault, files: ["Finale.md": bodyWithNewline])
    controller.openNote(at: "Finale.md")
    let id = try #require(controller.focusedTab?.id)
    let before = try bytes(root, "Finale.md")

    // What a click that reports the same text does: the text the buffer already has. The mark goes
    // on at once and the typing pause clears it (ADR-0096 §D3, §D4), so the decision, which reads
    // `differsFromSaved`, is clean immediately and the mark after the pause.
    controller.updateOpenNoteText(bodyWithNewline)
    #expect(controller.tab(withID: id)?.note.differsFromSaved == false)
    controller.settleUnsavedMarks()

    #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == false)
    #expect(await controller.saveTab(id) == .clean)
    #expect(try bytes(root, "Finale.md") == before)
    controller.close()
}

@MainActor
@Test func aClickAtTheEndOfANoteWithATrailingNewlineWritesNothingToTheBuffer() {
    for note in [bodyWithNewline, bodyWithTwoNewlines] {
        let bound = BoundText(note)
        let fixture = ScrolledEditorFixture(text: note, bound: bound)
        let end = (note as NSString).length

        // A click on the empty last line: the selection moves, the reveal and the styling pass run.
        fixture.textView.setSelectedRange(NSRange(location: end, length: 0))
        fixture.coordinator.applyReveal(to: fixture.textView)
        fixture.coordinator.applyStyling(to: fixture.textView, theme: .emergency)

        #expect(fixture.textView.string == note, "il testo del campo e cambiato")
        #expect(bound.value == note, "il binding e cambiato")
        #expect(bound.writes == 0, "il binding e stato scritto \(bound.writes) volte")
    }
}

// The 2026-10-31 pass: the byte count named one byte, not which one, and a dropped `\r` is one byte
// too (the CRLF tail family: PG-316, PG-318, PG-319). Pinned the same way as the LF pair above.
@MainActor
@Test func anEditedCRLFNoteKeepsItsWholeTerminatorByteForByte() async throws {
    let original = "---\r\ndate: 2026-09-29\r\ntags:\r\n  - type-note\r\n---\r\n\r\nCorpo del testo.\r\n"
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await controller(vault, files: ["Finale.md": original])
    controller.openNote(at: "Finale.md")
    let id = try #require(controller.focusedTab?.id)
    #expect(controller.openNote?.text == original, "la nota aperta non e il file")
    #expect(controller.openNote?.hasUnsavedChanges == false, "sporca appena aperta")

    let edited = original.replacingOccurrences(of: "Corpo", with: "Il corpo")
    controller.updateOpenNoteText(edited)
    #expect(await controller.saveTab(id) == .saved)

    let onDisk = try bytes(root, "Finale.md")
    #expect(onDisk == Data(edited.utf8), "i byte su disco non sono quelli del buffer")
    #expect(onDisk.suffix(2) == Data([0x0D, 0x0A]), "il CRLF finale non e intero")
    #expect(controller.tab(withID: id)?.note.hasUnsavedChanges == false, "resta «Non salvato»")
    controller.close()
}

// The click half on the restyle bench's note (`RestyleBudget.syntheticNote`, 50 KB, both variants:
// the fences one carries `pergamenum-view` blocks), the closest fixture to hand; the one in the
// sighting (50455 bytes) is not identified. Through the hooks `mouseDown` asks before `super` and
// `placeCaretForPlainClick`, at the three places «click low» can land: on the last line with text,
// on the empty line after the final newline, and below every line. `super.mouseDown` itself runs
// AppKit's tracking loop and is not driven here; what it does to a plain click is set the selection,
// which posts the selection notification the coordinator answers, so the selection is set to where
// the view says the point inserts (`characterIndexForInsertion`) before the passes run.
// `placeCaretForPlainClick` is `mouseUp`'s half and does nothing off a link, so it is called for
// completeness: the selection it sees is the one set here.
@MainActor
@Test func aClickLowInASyntheticNoteWritesNothingToTheBuffer() throws {
    for variant in RestyleBudget.Variant.allCases {
        let note = RestyleBudget.syntheticNote(bytes: 50 * RestyleBudget.kilobyte, variant: variant)
        #expect(note.hasSuffix("\n"), "\(variant): la nota sintetica non finisce con un a capo")
        let bound = BoundText(note)
        let fixture = ScrolledEditorFixture(text: note, bound: bound)
        fixture.openLikeTheApp()
        fixture.runPasses()
        let end = (note as NSString).length
        let view = fixture.textView
        let onEmbedResize = try #require(view.onEmbedResize, "\(variant): nessun gancio di ridimensionamento")
        let onClickInMargin = try #require(view.onClickInMargin, "\(variant): nessun gancio del margine")
        let onToggleCheckbox = try #require(view.onToggleCheckbox, "\(variant): nessun gancio delle caselle")
        // From the layout manager, not `firstRect`: that answers a zero rectangle for the empty line
        // after the final newline (measured here), and a point derived from it would test a click near
        // the top of the note instead. A point just above the bottom edge of the fragment holding the
        // last character is the lowest point on the last line with text; the bottom of the text
        // container's used rectangle, which includes the extra fragment of the empty line after the
        // final newline, gives the point on that empty line.
        let lastFragment = try #require(lastFragmentFrame(in: view, note: note), "\(variant): nessun frammento")
        let used = try #require(view.textLayoutManager?.usageBoundsForTextContainer, "\(variant): nessun impaginato")
        let origin = view.textContainerOrigin
        let onLastTextLine = CGPoint(x: lastFragment.minX + 4, y: lastFragment.maxY - 2)
        let onEmptyLastLine = CGPoint(x: origin.x + 4, y: origin.y + used.maxY - 2)
        let below = CGPoint(x: view.bounds.midX, y: view.bounds.maxY - 1)
        #expect(lastFragment.height > 0, "\(variant): il fondo della nota non e impaginato")
        #expect(below.y > lastFragment.maxY, "\(variant): il punto basso non e sotto l'ultima riga")
        #expect(
            view.characterIndexForInsertion(at: onEmptyLastLine) == end,
            "\(variant): il punto non cade sulla riga vuota finale")

        for point in [onLastTextLine, onEmptyLastLine, below] {
            #expect(onEmbedResize(.began(point)) == false, "\(variant): una presa di ridimensionamento")
            #expect(onClickInMargin(point) == false, "\(variant): un clic sul margine")
            #expect(onToggleCheckbox(point) == false, "\(variant): una casella spuntata")
            view.setSelectedRange(NSRange(location: view.characterIndexForInsertion(at: point), length: 0))
            view.placeCaretForPlainClick(at: point)
            fixture.runPasses()
        }

        #expect(view.string == note, "\(variant): il testo del campo e cambiato")
        #expect(bound.value == note, "\(variant): il binding e cambiato")
        #expect(bound.writes == 0, "\(variant): il binding e stato scritto \(bound.writes) volte")
    }
}

/// The frame of the layout fragment holding the note's last character, in the view's coordinates,
/// laid out first; nil for an empty note.
@MainActor
private func lastFragmentFrame(in view: NSTextView, note: String) -> CGRect? {
    let length = (note as NSString).length
    guard length > 0, let layout = view.textLayoutManager, let content = layout.textContentManager,
          let location = content.location(content.documentRange.location, offsetBy: length - 1)
    else { return nil }
    layout.ensureLayout(for: NSTextRange(location: location))
    guard let frame = layout.textLayoutFragment(for: location)?.layoutFragmentFrame else { return nil }
    return frame.offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
}
