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

/// PG-322: the caller's own line breaks take the note's break when the note is CRLF, and go in
/// untouched when it is LF.

@MainActor
private func appended(_ text: String, toNote note: String) async throws -> String? {
    let vault = try TemporaryVault()
    try vault.write(note, to: "Giorno.md")
    let session = VaultSession(
        root: vault.root,
        stateBase: vault.stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    await session.rescan()
    guard case .written(let result) = await session.append(text: text, to: "Giorno.md") else { return nil }
    return result.text
}

@MainActor
@Test func aMultiLineCaptureIntoACRLFNoteHasOnlyCRLFBreaks() async throws {
    let text = try #require(await appended("uno\ndue\ntre", toNote: "a\r\nb\r\n"))
    #expect(text == "a\r\nb\r\n\r\nuno\r\ndue\r\ntre\r\n")
    let scalars = Array(text.unicodeScalars)
    for (index, scalar) in scalars.enumerated() where scalar == "\n" {
        #expect(index > 0 && scalars[index - 1] == "\r", "bare LF at scalar \(index)")
    }
}

@MainActor
@Test func aMixedCaptureIntoACRLFNoteIsAllCRLF() async throws {
    let text = try #require(await appended("a\r\nb\nc", toNote: "x\r\ny\r\n"))
    #expect(text == "x\r\ny\r\n\r\na\r\nb\r\nc\r\n")
}

@MainActor
@Test func aLoneCarriageReturnInACaptureIsKeptInACRLFNote() async throws {
    let text = try #require(await appended("a\rb\nc", toNote: "x\r\ny\r\n"))
    #expect(text == "x\r\ny\r\n\r\na\rb\r\nc\r\n")
}

/// Compared by unicode scalars, not `Character`s, so "\r" + "\r\n" and "\r\r\n" cannot be
/// mistaken for one another by grapheme clustering.
@MainActor
@Test func aCaptureEndingInALoneCarriageReturnKeepsItBeforeTheClosingCRLF() async throws {
    let text = try #require(await appended("a\r", toNote: "x\r\n"))
    #expect(Array(text.unicodeScalars) == Array("x\r\n\r\na\r\r\n".unicodeScalars))
}

@MainActor
@Test func aCaptureEndingInABreakIntoACRLFNoteLeavesABlankLine() async throws {
    let text = try #require(await appended("a\n", toNote: "x\r\n"))
    #expect(Array(text.unicodeScalars) == Array("x\r\n\r\na\r\n\r\n".unicodeScalars))
}

@MainActor
@Test func aCaptureIntoAnLFNoteIsGivenVerbatim() async throws {
    let multi = try #require(await appended("uno\ndue", toNote: "a\nb\n"))
    #expect(multi == "a\nb\n\nuno\ndue\n")
    let withCRLF = try #require(await appended("x\r\ny\nz", toNote: "a\nb\n"))
    #expect(withCRLF == "a\nb\n\nx\r\ny\nz\n")
}

@Test func normalisingToCRLFWritesEveryBreakAsCRLF() {
    #expect(LineBreak.crlf.normalised("") == "")
    #expect(LineBreak.crlf.normalised("abc") == "abc")
    #expect(LineBreak.crlf.normalised("a\nb") == "a\r\nb")
    #expect(LineBreak.crlf.normalised("a\r\nb") == "a\r\nb")
    #expect(LineBreak.crlf.normalised("a\r\nb\nc") == "a\r\nb\r\nc")
    #expect(LineBreak.crlf.normalised("a\n") == "a\r\n")
    #expect(LineBreak.crlf.normalised("a\r\n") == "a\r\n")
    #expect(LineBreak.crlf.normalised("\n\n") == "\r\n\r\n")
    #expect(LineBreak.crlf.normalised("a\rb") == "a\rb")
}

@Test func normalisingToLFWritesEveryBreakAsLF() {
    #expect(LineBreak.lf.normalised("") == "")
    #expect(LineBreak.lf.normalised("abc") == "abc")
    #expect(LineBreak.lf.normalised("a\r\nb") == "a\nb")
    #expect(LineBreak.lf.normalised("a\nb") == "a\nb")
    #expect(LineBreak.lf.normalised("a\r\n") == "a\n")
    #expect(LineBreak.lf.normalised("a\rb") == "a\rb")
}

/// The documented edge: "\r" + "\r\n" is a lone "\r" then one CRLF grapheme; the CRLF becomes
/// "\n", the "\r" is kept, and the two meet as a CRLF again.
@Test func normalisingToLFTurnsCRCRLFIntoOneCRLF() {
    #expect(LineBreak.lf.normalised("\r\r\n") == "\r\n")
}
