import Foundation
import Testing
@testable import Pergamenum

// R-10 (PG-442): a write keeps the precondition it computed, and a section is found by its
// heading line rather than by the heading's text.

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-08-21\ntags:\n  - type-note\n---\n\n\(body)\n"
}

// MARK: - S02-02: an undo carries the hash its preflight checked

/// The preflight runs before the first `await`; a save that lands after it and before the write
/// must be refused, not overwritten with the journal's older text.
@MainActor
@Test func anUndoRefusesAFileSavedBetweenItsPreflightAndItsWrite() async throws {
    let vault = try TemporaryVault()
    try vault.write(note("Prima."), to: "A.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    session.journal = session.journalOnDisk

    try await session.transaction("modifica") {
        try await session.write(note("Dopo."), to: "A.md")
    }
    let operationID = try #require(session.journalOnDisk.entries().first?.operation)
    let entries = session.journalOnDisk.entries(operation: operationID)
    #expect(session.preflightUndo(entries).isEmpty)

    // The save that lands in the window the preflight cannot see.
    try vault.write(note("Salvato nel frattempo."), to: "A.md")
    let outcome = await session.performUndo(entries)

    #expect(outcome.changed.isEmpty)
    #expect(outcome.failures.count == 1)
    let text = try String(contentsOf: vault.root.appending(path: "A.md"), encoding: .utf8)
    #expect(text.contains("Salvato nel frattempo."), "the save that landed is kept, not replaced by the journal's text")
}

// MARK: - S06-03: the timeline is the `## Timeline` line, nothing that merely contains it

@Test func aTimeBlockWriteLeavesALookAlikeTimelineSectionUntouched() throws {
    let day = try #require(CalendarDate(year: 2026, month: 10, day: 31))
    let body = """
    ## Timeline riunione

    - 10:00-11:00 Kick-off cliente

    ### Timeline

    - 12:00-13:00 Pranzo
    """
    #expect(TimeBlockSection.parse(from: body, day: day).isEmpty, "neither heading is the plan")

    let block = TimeBlock(
        day: day, startMinutes: 9 * 60, durationMinutes: 60, title: "Sopralluogo",
        sourceTaskID: nil, isPublished: false
    )
    let written = TimeBlockSection.write([block], into: body)

    #expect(written.hasPrefix(body), "both look-alike sections stay exactly as they were")
    #expect(written.hasSuffix("## Timeline\n\n- 09:00-10:00 Sopralluogo"))
    #expect(TimeBlockSection.parse(from: written, day: day).map(\.title) == ["Sopralluogo"])
}

@Test func aTimeBlockWriteReplacesOnlyTheRealSectionAndKeepsTheNextHeading() throws {
    let day = try #require(CalendarDate(year: 2026, month: 10, day: 31))
    let body = "## Timeline riunione\n\n- 10:00-11:00 Kick-off\n\n"
        + "## Timeline\n\n- 08:00-09:00 Vecchio\n\n## Altro\n\ntesto\n"
    let block = TimeBlock(
        day: day, startMinutes: 9 * 60, durationMinutes: 60, title: "Nuovo",
        sourceTaskID: nil, isPublished: false
    )

    let written = TimeBlockSection.write([block], into: body)

    #expect(written.hasPrefix("## Timeline riunione\n\n- 10:00-11:00 Kick-off\n\n## Timeline\n\n- 09:00-10:00 Nuovo\n\n"))
    #expect(written.hasSuffix("## Altro\n\ntesto\n"))
    #expect(!written.contains("Vecchio"))
}

@Test func aTimeBlockWriteKeepsABlockListedAfterAFencedHashLine() throws {
    let day = try #require(CalendarDate(year: 2026, month: 10, day: 31))
    let body = "## Timeline\n\n- 08:00-09:00 Prima\n\n```sh\n# commento\n```\n\n"
        + "- 14:00-15:00 Dopo\n\n## Altro\n\ntesto\n"

    let parsed = TimeBlockSection.parse(from: body, day: day)
    #expect(parsed.map(\.title) == ["Prima", "Dopo"], "the fenced # line does not end the plan")

    let added = TimeBlock(
        day: day, startMinutes: 11 * 60, durationMinutes: 60, title: "Nuovo",
        sourceTaskID: nil, isPublished: false
    )
    let written = TimeBlockSection.write(parsed + [added], into: body)

    #expect(TimeBlockSection.parse(from: written, day: day).map(\.title) == ["Prima", "Nuovo", "Dopo"])
    #expect(written.contains("- 14:00-15:00 Dopo"), "the block after the fence survives the write")
    #expect(written.hasSuffix("## Altro\n\ntesto\n"), "the next real heading keeps its line")
    #expect(written.contains("```sh\n# commento\n```"), "the fence itself survives the write")
}

@Test func aBlockLineInsideAFenceUnderTheTimelineIsNotABlock() throws {
    let day = try #require(CalendarDate(year: 2026, month: 10, day: 31))
    let body = "## Timeline\n\n- 08:00-09:00 Vero\n\n```\n- 09:00-10:00 Esempio\n```\n\n"
        + "~~~\n- 11:00-12:00 Altro esempio\n~~~\n\n## Altro\n"

    #expect(TimeBlockSection.parse(from: body, day: day).map(\.title) == ["Vero"])
}

@Test func aTimeBlockWriteKeepsTheProseAndTheFencesOfTheSection() throws {
    let day = try #require(CalendarDate(year: 2026, month: 10, day: 31))
    let body = "## Timeline\n\nGiornata in trasferta.\n\n- 08:00-09:00 Vecchio\n\n"
        + "```\n- 09:00-10:00 Esempio\n```\n\n## Altro\n\ntesto\n"
    let block = TimeBlock(
        day: day, startMinutes: 10 * 60, durationMinutes: 60, title: "Nuovo",
        sourceTaskID: nil, isPublished: false
    )

    let written = TimeBlockSection.write([block], into: body)

    #expect(written == "## Timeline\n\nGiornata in trasferta.\n\n- 10:00-11:00 Nuovo\n\n"
        + "```\n- 09:00-10:00 Esempio\n```\n\n## Altro\n\ntesto\n")
    #expect(TimeBlockSection.parse(from: written, day: day).map(\.title) == ["Nuovo"])

    // The last block goes, the heading stays: the section still holds what the person wrote.
    let emptied = TimeBlockSection.write([], into: body)
    #expect(emptied == "## Timeline\n\nGiornata in trasferta.\n\n```\n- 09:00-10:00 Esempio\n```\n\n## Altro\n\ntesto\n")
    #expect(TimeBlockSection.parse(from: emptied, day: day).isEmpty)
}

@Test func aCRLFTimelineWriteKeepsItsProseInTheNotesOwnBreak() throws {
    let day = try #require(CalendarDate(year: 2026, month: 10, day: 31))
    let body = "## Timeline\r\n\r\n- 08:00-09:00 Vecchio\r\n\r\nNota a margine.\r\n\r\n## Altro\r\n"
    let block = TimeBlock(
        day: day, startMinutes: 9 * 60, durationMinutes: 60, title: "Nuovo",
        sourceTaskID: nil, isPublished: false
    )

    let written = TimeBlockSection.write([block], into: body)

    #expect(written == "## Timeline\r\n\r\n- 09:00-10:00 Nuovo\r\n\r\nNota a margine.\r\n\r\n## Altro\r\n")
}

@Test func aMixedEndingTimelineWriteLeavesTheProseAndTheFenceByteIdentical() throws {
    let day = try #require(CalendarDate(year: 2026, month: 10, day: 31))
    // The note is LF by majority; one prose line and the fence's lines are CRLF, one prose line is LF.
    let prose = "Giornata in trasferta.\r\n"
    let fence = "```\r\n- 09:00-10:00 Esempio\r\n```\n"
    let tail = "Nota a margine.\r\n"
    let body = "## Timeline\n\n" + prose + "\n- 08:00-09:00 Vecchio\n\n" + fence + tail + "\n## Altro\n\ntesto\n"
    let block = TimeBlock(
        day: day, startMinutes: 10 * 60, durationMinutes: 60, title: "Nuovo",
        sourceTaskID: nil, isPublished: false
    )

    let written = TimeBlockSection.write([block], into: body)

    #expect(written == "## Timeline\n\n" + prose + "\n- 10:00-11:00 Nuovo\n\n" + fence + tail + "\n## Altro\n\ntesto\n")
    #expect(written.contains(prose + "\n- 10:00"), "the CRLF prose line keeps its own ending")
    #expect(written.contains(fence + tail), "the fence and the line after it keep their own endings")
    #expect(TimeBlockSection.parse(from: written, day: day).map(\.title) == ["Nuovo"])
}

// MARK: - S03-02: the event link goes under `## Note`, never under `## Note correlate`

@Test func anEventLinkOpensItsOwnSectionBesideNoteCorrelate() {
    let body = "Testo.\n\n## Note correlate\n\n- [[Altra]] — motivo\n"

    let added = EventNoteSection.adding("Riunione", to: body)

    #expect(added == body + "\n## Note\n\n- [[Riunione]]\n")
}

// MARK: - S03-03: the quoted `related:` pass stays inside the frontmatter's `related:` key

@Test func aRenameLeavesAQuotedBodyBulletAlone() {
    let text = "---\nrelated:\n  - \"Vecchio\"\naliases:\n  - \"Vecchio\"\n---\n\n- \"Vecchio\"\n"

    let updated = NoteRename.rewritingLinks(in: text, from: "Vecchio", to: "Nuovo")

    #expect(updated == "---\nrelated:\n  - \"Nuovo\"\naliases:\n  - \"Vecchio\"\n---\n\n- \"Vecchio\"\n")
}
