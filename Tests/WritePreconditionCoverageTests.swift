import Foundation
import Testing
@testable import Pergamenum

// R-10 (PG-442), the cases `WritePreconditionSectionTests` leaves: the removal and canvas legs of
// `performUndo`, the fence/CRLF/look-alike behaviour of the shared `MarkdownSection` walk through
// each of its callers, and the frontmatter-only scope of the quoted `related:` rewrite.
// Tests marked (coverage) pin logic the diff touches that no requirement test reaches.

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-08-21\ntags:\n  - type-note\n---\n\n\(body)\n"
}

@MainActor
private func armedSession(_ vault: borrowing TemporaryVault, files: [String]) async throws -> VaultSession {
    for file in files { try vault.write(note(), to: file) }
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    session.journal = session.journalOnDisk
    return session
}

// MARK: - performUndo: the removal leg and the canvas leg

@MainActor
@Test func anUndoOfARemovalRefusesAFileThatReappearedBetweenItsPreflightAndItsWrite() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault, files: ["Uno.md"])
    try await session.trashFile(at: "Uno.md")
    let entries = Array(session.journalOnDisk.entries().suffix(1))
    #expect(entries.first?.kind == .removal)
    #expect(session.preflightUndo(entries).isEmpty)

    // Somebody puts a file at that path after the preflight and before the write.
    try vault.write(note("Tornato da solo."), to: "Uno.md")
    let outcome = await session.performUndo(entries)

    #expect(outcome.changed.isEmpty)
    #expect(outcome.failures.count == 1)
    #expect(outcome.failures.first?.contains("Uno.md") == true)
    #expect(outcome.failures.first?.contains("non lo tocco") == true, "the refusal's own sentence")
    #expect(outcome.failures == [VaultWriteRefusal.movedOn("Uno.md").description], "the path is named once")
    let text = try String(contentsOf: vault.root.appending(path: "Uno.md"), encoding: .utf8)
    #expect(text.contains("Tornato da solo."), "the file that appeared is kept")
}

@MainActor
@Test func anUndoOfARemovalStillRestoresTheFileWhenNothingMovedOn() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault, files: ["Uno.md"])
    try await session.trashFile(at: "Uno.md")
    let entries = Array(session.journalOnDisk.entries().suffix(1))

    let outcome = await session.performUndo(entries)

    #expect(outcome.failures.isEmpty)
    #expect(outcome.changed == ["Uno.md"])
    let text = try String(contentsOf: vault.root.appending(path: "Uno.md"), encoding: .utf8)
    #expect(text.contains("Corpo."))
}

@MainActor
@Test func anUndoOfATextWriteStillRestoresTheOldTextWhenNothingMovedOn() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault, files: ["A.md"])
    try await session.transaction("modifica") {
        try await session.write(note("Dopo."), to: "A.md")
    }
    let operationID = try #require(session.journalOnDisk.entries().last?.operation)
    let entries = session.journalOnDisk.entries(operation: operationID)

    let outcome = await session.performUndo(entries)

    #expect(outcome.failures.isEmpty)
    #expect(outcome.changed == ["A.md"])
    let text = try String(contentsOf: vault.root.appending(path: "A.md"), encoding: .utf8)
    #expect(text.contains("Corpo.") && !text.contains("Dopo."))
}

@MainActor
@Test func anUndoOfACanvasWriteRefusesABoardSavedBetweenItsPreflightAndItsWrite() async throws {
    let vault = try TemporaryVault()
    let original = "{\"nodes\":[],\"edges\":[]}"
    try vault.write(original, to: "Lavagna.canvas")
    let session = try await armedSession(vault, files: [])
    try await session.transaction("sposta") {
        try await session.writeFile("{\"nodes\":[],\"edges\":[],\"x\":1}", to: "Lavagna.canvas")
    }
    let operationID = try #require(session.journalOnDisk.entries().last?.operation)
    let entries = session.journalOnDisk.entries(operation: operationID)
    #expect(entries.first?.kind == .textReplacement)
    #expect(session.preflightUndo(entries).isEmpty)

    let saved = "{\"nodes\":[],\"edges\":[],\"salvata\":true}"
    try vault.write(saved, to: "Lavagna.canvas")
    let outcome = await session.performUndo(entries)

    #expect(outcome.changed.isEmpty)
    #expect(outcome.failures.count == 1)
    #expect(try String(contentsOf: vault.root.appending(path: "Lavagna.canvas"), encoding: .utf8) == saved)
}

// MARK: - TimeBlockSection through MarkdownSection

private func block(_ title: String, at hour: Int, on day: CalendarDate) -> TimeBlock {
    TimeBlock(
        day: day, startMinutes: hour * 60, durationMinutes: 60, title: title,
        sourceTaskID: nil, isPublished: false
    )
}

@Test func aTimelineHeadingInsideACodeFenceIsNotThePlan() throws {
    let day = try #require(CalendarDate(year: 2026, month: 10, day: 31))
    let body = "Esempio:\n\n```\n## Timeline\n\n- 08:00-09:00 Finto\n```\n"
    #expect(TimeBlockSection.parse(from: body, day: day).isEmpty)

    let written = TimeBlockSection.write([block("Vero", at: 9, on: day)], into: body)

    #expect(written.hasPrefix(body), "the fenced example stays exactly as it was")
    #expect(written.hasSuffix("## Timeline\n\n- 09:00-10:00 Vero"))
    #expect(TimeBlockSection.parse(from: written, day: day).map(\.title) == ["Vero"])
}

@Test func aCRLFTimelineIsReplacedInPlaceAndTheNextHeadingKeepsItsLine() throws {
    let day = try #require(CalendarDate(year: 2026, month: 10, day: 31))
    let body = "## Timeline\r\n\r\n- 08:00-09:00 Vecchio\r\n\r\n## Altro\r\n\r\ntesto\r\n"
    #expect(TimeBlockSection.parse(from: body, day: day).map(\.title) == ["Vecchio"])

    let written = TimeBlockSection.write([block("Nuovo", at: 10, on: day)], into: body)

    #expect(!written.contains("Vecchio"))
    #expect(written.hasPrefix("## Timeline\r\n"))
    #expect(written.contains("- 10:00-11:00 Nuovo"))
    #expect(written.hasSuffix("## Altro\r\n\r\ntesto\r\n"))
    #expect(TimeBlockSection.parse(from: written, day: day).map(\.title) == ["Nuovo"])
}

@Test func deletingTheLastBlockRemovesOnlyTheRealTimelineSection() throws {
    let day = try #require(CalendarDate(year: 2026, month: 10, day: 31))
    let body = "## Timeline riunione\n\n- 10:00-11:00 Kick-off\n\n"
        + "## Timeline\n\n- 08:00-09:00 Vecchio\n\n## Altro\n\ntesto\n"

    let written = TimeBlockSection.write([], into: body)

    #expect(written.contains("## Timeline riunione\n\n- 10:00-11:00 Kick-off"))
    #expect(!written.contains("Vecchio"))
    #expect(!written.contains("\n## Timeline\n"))
    #expect(written.contains("## Altro\n\ntesto"))
}

// MARK: - EventNoteSection through MarkdownSection

@Test func anEventLinkGoesUnderTheRealNoteSectionBeyondANoteCorrelateOne() {
    let body = "Testo.\n\n## Note correlate\n\n- [[Altra]] — motivo\n\n## Note\n\n- [[Prima]]\n\n## Dopo\n\ntesto\n"

    let added = EventNoteSection.adding("Riunione", to: body)

    let correlate = "## Note correlate\n\n- [[Altra]] — motivo\n\n"
    #expect(added.hasPrefix("Testo.\n\n" + correlate + "## Note\n\n- [[Prima]]\n- [[Riunione]]"))
    #expect(added.hasSuffix("## Dopo\n\ntesto\n"))
    #expect(added.components(separatedBy: "[[Riunione]]").count == 2)
}

@Test func anEventLinkIgnoresANoteHeadingInsideACodeFence() {
    let body = "Testo.\n\n```\n## Note\n\n- [[Finto]]\n```\n"

    let added = EventNoteSection.adding("Riunione", to: body)

    #expect(added.hasPrefix(body), "the fenced example is untouched")
    #expect(added.hasSuffix("## Note\n\n- [[Riunione]]\n"))
}

@Test func anEventLinkIntoACRLFNoteSectionKeepsTheNextHeading() {
    let body = "Testo.\r\n\r\n## Note\r\n\r\n- [[Prima]]\r\n\r\n## Dopo\r\n\r\ntesto\r\n"

    let added = EventNoteSection.adding("Riunione", to: body)

    #expect(added.contains("- [[Prima]]\r\n- [[Riunione]]\r\n"))
    #expect(added.hasSuffix("## Dopo\r\n\r\ntesto\r\n"))
}

// MARK: - MarkdownSection itself (coverage)

@Test func theSectionRunsFromItsHeadingLineToTheNextHashLine() throws {
    let body = "Intro.\n## Note\nuno\ndue\n### Sotto\nfine\n"

    let range = try #require(MarkdownSection.range(under: "## Note", in: body))

    #expect(String(body[range]) == "## Note\nuno\ndue\n")
}

@Test func theSectionRunsToTheEndOfTheBodyWhenNoHeadingFollows() throws {
    let body = "## Note\nuno\ndue"

    let range = try #require(MarkdownSection.range(under: "## Note", in: body))

    #expect(String(body[range]) == body)
    #expect(MarkdownSection.contentEnd(in: body, section: range) == body.endIndex)
}

@Test func theHeadingToleratesTrailingBlanksAndACarriageReturnOnly() {
    #expect(MarkdownSection.range(under: "## Note", in: "## Note  \t\nx\n") != nil)
    #expect(MarkdownSection.range(under: "## Note", in: "## Note\r\nx\r\n") != nil)
    #expect(MarkdownSection.range(under: "## Note", in: "## Notes\nx\n") == nil)
    #expect(MarkdownSection.range(under: "## Note", in: "### Note\nx\n") == nil)
    #expect(
        MarkdownSection.range(under: "## Note", in: "  ## Note\nx\n") == nil,
        "an indented heading is not the heading"
    )
    #expect(MarkdownSection.range(under: "## Note", in: "Vedi ## Note qui\n") == nil)
    #expect(MarkdownSection.range(under: "## Note", in: "") == nil)
}

@Test func aHashLineInsideAFenceDoesNotEndTheSection() throws {
    let body = "## Note\n```sh\n# commento\n```\nresto\n## Altro\nx\n"

    let range = try #require(MarkdownSection.range(under: "## Note", in: body))

    #expect(String(body[range]) == "## Note\n```sh\n# commento\n```\nresto\n")
}

@Test func theFirstRealHeadingWinsOverAFencedOneAbove() throws {
    let body = "```\n## Note\nfinto\n```\n## Note\nvero\n"

    let range = try #require(MarkdownSection.range(under: "## Note", in: body))

    #expect(String(body[range]) == "## Note\nvero\n")
}

@Test func headingEndAndContentEndBracketTheSectionsBody() throws {
    let body = "## Note\r\nuno\r\n## Altro\r\n"
    let range = try #require(MarkdownSection.range(under: "## Note", in: body))

    let headingEnd = MarkdownSection.headingEnd(of: "## Note", in: body, section: range)
    let contentEnd = MarkdownSection.contentEnd(in: body, section: range)

    #expect(String(body[body.startIndex..<headingEnd]) == "## Note")
    #expect(String(body[headingEnd..<contentEnd]) == "\r\nuno")
}

@Test func isHeadingMatchesTheLineExactly() {
    #expect(MarkdownSection.isHeading("## Trascrizione", "## Trascrizione"))
    #expect(MarkdownSection.isHeading("## Trascrizione\r", "## Trascrizione"))
    #expect(MarkdownSection.isHeading("## Trascrizione \t", "## Trascrizione"))
    #expect(!MarkdownSection.isHeading("## Trascrizione finale", "## Trascrizione"))
    #expect(!MarkdownSection.isHeading(" ## Trascrizione", "## Trascrizione"))
}

// MARK: - NoteRename: the quoted pass stays inside `related:`

@Test func aQuotedEntryUnderAnotherKeyIsNotRenamed() {
    let text = "---\ntags:\n  - \"Vecchio\"\nrelated:\n  - \"Vecchio\"\n---\n"

    let updated = NoteRename.rewritingLinks(in: text, from: "Vecchio", to: "Nuovo")

    #expect(updated == "---\ntags:\n  - \"Vecchio\"\nrelated:\n  - \"Nuovo\"\n---\n")
}

@Test func aQuotedBulletInANoteWithoutFrontmatterIsNotRenamed() {
    let text = "# Titolo\n\n- \"Vecchio\"\n\n```\n- \"Vecchio\"\n```\n"

    // Nothing to change is reported as nil, not as an unchanged copy.
    #expect(NoteRename.rewritingLinks(in: text, from: "Vecchio", to: "Nuovo") == nil)
}

@Test func aCRLFNoteStillRenamesItsQuotedRelatedEntryAndNothingBelowTheFrontmatter() {
    let text = "---\r\nrelated:\r\n  - \"Vecchio\"\r\n---\r\n\r\n- \"Vecchio\"\r\n"

    let updated = NoteRename.rewritingLinks(in: text, from: "Vecchio", to: "Nuovo")

    #expect(updated == "---\r\nrelated:\r\n  - \"Nuovo\"\r\n---\r\n\r\n- \"Vecchio\"\r\n")
}

@Test func everyQuotedEntryOfTheRelatedListIsRenamedAndTheOthersKept() {
    let text = "---\nrelated:\n  - \"vecchio\"\n  - \"Altra\"\n  - \"Vecchio\"\naliases:\n  - \"Vecchio\"\n---\n"

    let updated = NoteRename.rewritingLinks(in: text, from: "Vecchio", to: "Nuovo")

    #expect(updated == "---\nrelated:\n  - \"Nuovo\"\n  - \"Altra\"\n  - \"Nuovo\"\naliases:\n  - \"Vecchio\"\n---\n")
}

// MARK: - TranscriptNote through MarkdownSection

private func proposal(transcript: String) -> PlaudProposal {
    PlaudProposal(
        recording: PlaudProposalRecording(
            id: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6", name: "Riunione di prova",
            recordedAt: "2026-09-04T11:48:07", durationMs: 1_236_000
        ),
        recordingKind: .meeting,
        themes: [PlaudTheme(name: "Azioni", tasks: [])],
        transcript: PlaudTranscript(language: "it", text: transcript, speakers: ["Speaker 1"]),
        warnings: [],
        generatedAt: "2026-09-05T07:55:24.906Z"
    )
}

private func render(_ transcript: String, over existing: String?) -> String {
    TranscriptNote.render(
        proposal: proposal(transcript: transcript), acceptedTaskIDs: [], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: existing
    )
}

@Test func reimportingIntoACRLFNoteReplacesTheTranscriptInsteadOfAppendingASecond() {
    let first = render("Speaker 1: Prima versione.", over: nil)
    let crlf = first.replacingOccurrences(of: "\n", with: "\r\n")

    let second = render("Speaker 1: Seconda versione.", over: crlf)

    #expect(second.components(separatedBy: "## Trascrizione").count == 2, "one transcript section")
    #expect(second.contains("Seconda versione."))
    #expect(!second.contains("Prima versione."))
}

@Test func aTranscriptHeadingInsideACodeFenceIsNotASectionOfTheNote() {
    let first = render("Speaker 1: Prima versione.", over: nil)
    let fence = "```\n## Trascrizione\nesempio da non toccare\n```\n\n"
    let existing = first.replacingOccurrences(of: "## Trascrizione", with: fence + "## Trascrizione")

    let second = render("Speaker 1: Seconda versione.", over: existing)

    #expect(second.contains("```\n## Trascrizione\nesempio da non toccare\n```"), "the fenced example survives")
    #expect(second.components(separatedBy: "## Trascrizione").count == 3, "the fence and the real section")
    #expect(second.contains("Seconda versione."))
    #expect(!second.contains("Prima versione."))
}
