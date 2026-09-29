import Foundation
import Testing
@testable import Pergamenum

/// PG-320: the capture route appends to a note through `VaultSession.append(text:to:)`, after one
/// blank line in the note's own break, whatever the note's closing breaks are.

@MainActor
@Test func aCaptureIsAppendedAfterOneBlankLineInTheNotesOwnBreak() async throws {
    let cases: [(note: String, expected: String)] = [
        ("a\nb\n", "a\nb\n\nRiga\n"),
        ("a\nb", "a\nb\n\nRiga\n"),
        ("a\r\nb\r\n", "a\r\nb\r\n\r\nRiga\r\n"),
        ("a\r\nb\r\n\r\n", "a\r\nb\r\n\r\nRiga\r\n"),
        ("a\r\nb", "a\r\nb\r\n\r\nRiga\r\n"),
        // Mixed: the closing breaks give way to the first line break's kind.
        ("a\nb\r\n", "a\nb\n\nRiga\n"),
        ("a\r\nb\n\n", "a\r\nb\r\n\r\nRiga\r\n"),
    ]
    for (note, expected) in cases {
        let vault = try TemporaryVault()
        try vault.write(note, to: "Giorno.md")
        let session = VaultSession(
            root: vault.root,
            stateBase: vault.stateBase,
            bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
        )
        await session.rescan()
        guard case .written(let result) = await session.append(text: "Riga", to: "Giorno.md") else {
            Issue.record("expected .written for \(note.debugDescription)")
            continue
        }
        #expect(result.text == expected)
    }
}

@MainActor
@Test func aCaptureIntoAnEmptyNoteIsJustTheTextAndABreak() async throws {
    let vault = try TemporaryVault()
    try vault.write("", to: "Vuota.md")
    let session = VaultSession(
        root: vault.root,
        stateBase: vault.stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    await session.rescan()
    guard case .written(let result) = await session.append(text: "Riga", to: "Vuota.md") else {
        Issue.record("expected .written")
        return
    }
    #expect(result.text == "Riga\n")
}
