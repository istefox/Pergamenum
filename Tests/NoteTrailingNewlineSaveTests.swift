import AppKit
import Foundation
import Testing
@testable import Pergamenum

// PG-424: pins only, not a fix and not a reproduction. The first save of a note whose text ends in
// a trailing newline was seen once to remove it (50455 to 50454 bytes), and a click was seen to
// leave the editor reading «Non salvato». The cause is unattributed and neither symptom reproduces
// here, so these pin what the save path must hold whatever the cause was: the buffer reaches the
// disk byte for byte, a trailing newline included, and a note nobody edited is neither dirty nor
// written. The click test proves only that the styling and reveal passes do not write the binding.
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
