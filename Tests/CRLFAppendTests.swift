import Foundation
import Testing
@testable import Pergamenum

/// PG-317 and PG-318: the residuals of PG-316. A reader that split a note on `.newlines` counted
/// a `"\r\n"` pair twice, and an appender that tested `hasSuffix("\n")` never saw a CRLF note's
/// last line break, so it added a second one and wrote a bare LF. Each test writes its note once
/// in LF and derives the CRLF twin, so the two outputs can only differ by their ending.

private func crlf(_ lf: String) -> String { lf.replacingOccurrences(of: "\n", with: "\r\n") }

// MARK: - Readers that split a note into lines (PG-317)

@Test func aCRLFNoteReadsAsTheSameBlocksAsItsLFTwin() {
    let lf = """
    # Titolo
    una riga
    e la seguente

    | a | b |
    |---|---|
    | 1 | 2 |

    - uno
    - due

    ```pergamenum-view
    from: #type-note
    render: table
    ```
    """
    #expect(MarkdownBlockParser.blocks(in: crlf(lf)) == MarkdownBlockParser.blocks(in: lf))
}

@Test func aViewBlockErrorInACRLFBodyNamesTheSameLine() {
    let lf = "from: #type-note\nrender: table\nsenza chiave"
    #expect(throws: ViewBlockError(line: 3, reason: "riga senza «chiave: valore»")) {
        try ViewBlock.parse(crlf(lf))
    }
    #expect(throws: ViewBlockError(line: 3, reason: "riga senza «chiave: valore»")) {
        try ViewBlock.parse(lf)
    }
}

/// The error card numbers the lines it shows with the same split the parser reports against, so
/// the highlighted line is the one the error names.
@Test func aCRLFViewSourceShowsTheSameLinesAsItsLFTwin() {
    let lf = "from: #type-note\n\nrender: table"
    #expect(ViewBlock.lines(of: lf) == ["from: #type-note", "", "render: table"])
    #expect(ViewBlock.lines(of: crlf(lf)) == ViewBlock.lines(of: lf))
}

// MARK: - Appenders at the end of a note (PG-318)

@MainActor
@Test func aQuickCaptureIntoACRLFInboxAddsOneCRLFLine() async throws {
    let vault = try TemporaryVault()
    let inbox = "---\ndate: 2026-09-29\n---\n\n- [ ] Prima\n"
    try vault.write(crlf(inbox), to: VaultSession.TaskDestination.inboxPath)
    let session = VaultSession(
        root: vault.root,
        stateBase: vault.stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    await session.rescan()

    let result = try #require(await session.captureTask(VaultSession.TaskDraft(text: "Seconda")))

    #expect(result.text == crlf(inbox + "- [ ] Seconda\n"))
}

@Test func theDailyNoteMirrorAppendsOneCRLFLineToACRLFNote() throws {
    let entry = DailyNoteMirror.Entry(praticaTitle: "Offerta 2026", kind: .call, counterpart: "Mario Rossi")
    for lf in ["# Giorno\n\ncorpo\n", "# Giorno\n\ncorpo"] {
        let lfResult = try #require(DailyNoteMirror.appending(entry, to: lf, isEnabled: true))
        #expect(DailyNoteMirror.appending(entry, to: crlf(lf), isEnabled: true) == crlf(lfResult))
    }
}

@Test func anEventNoteLinkLandsInACRLFDailyNoteAsInItsLFTwin() {
    let notes = [
        // No section yet: the section is created at the end, after one, two or no line breaks.
        // Every fixture has a line break of its own, or its CRLF twin would have none to keep.
        "titolo\ncorpo",
        "titolo\ncorpo\n",
        "titolo\ncorpo\n\n",
        // The section closes the note.
        "corpo\n\n## Note\n\n- [[prima]]\n",
        // The section is followed by another one, which the link must not land in.
        "corpo\n\n## Note\n\n- [[prima]]\n\n## Timeline\n\n- 09:00-10:00 Qualcosa\n",
    ]
    for lf in notes {
        let lfResult = EventNoteSection.adding("seconda", to: lf)
        #expect(EventNoteSection.adding("seconda", to: crlf(lf)) == crlf(lfResult))
    }
}

private let timelineDay = CalendarDate(iso: "2026-09-29")!

private func block(_ start: Int, _ title: String) -> TimeBlock {
    TimeBlock(
        day: timelineDay, startMinutes: start, durationMinutes: 60, title: title,
        sourceTaskID: nil, isPublished: false
    )
}

@Test func aCRLFTimelineReadsAsItsLFTwin() {
    let lf = "corpo\n\n## Timeline\n\n- 09:00-10:00 Sopralluogo\n- 11:00-12:00 Calcolo\n\n"
        + "## Altro\n\n- 13:00-14:00 No\n"
    let blocks = TimeBlockSection.parse(from: crlf(lf), day: timelineDay)
    #expect(blocks == TimeBlockSection.parse(from: lf, day: timelineDay))
    #expect(blocks.map(\.title) == ["Sopralluogo", "Calcolo"])
}

@Test func writingTheTimelineOfACRLFNoteMatchesItsLFTwin() {
    let notes = [
        // No section yet: created at the end of the note.
        "titolo\ncorpo",
        "titolo\ncorpo\n",
        // A section followed by another one, which the rewrite must leave where it is.
        "corpo\n\n## Timeline\n\n- 09:00-10:00 Vecchio\n\n## Altro\n\ntesto\n",
        // A section that closes the note.
        "corpo\n\n## Timeline\n\n- 09:00-10:00 Vecchio\n",
    ]
    for lf in notes {
        for blocks in [[block(540, "Nuovo"), block(660, "Altro blocco")], []] {
            let lfResult = TimeBlockSection.write(blocks, into: lf)
            #expect(TimeBlockSection.write(blocks, into: crlf(lf)) == crlf(lfResult))
        }
    }
}

@Test func aPraticaEntryOnACRLFNoteMatchesItsLFTwin() {
    let timestamp = Date(timeIntervalSinceReferenceDate: 0)
    for lf in ["titolo\ncorpo", "titolo\ncorpo\n", "titolo\ncorpo\n\n"] {
        let lfInsertion = PraticaEntry.insert(kind: .call, at: timestamp, counterpart: "Mario Rossi", in: lf)
        let crlfInsertion = PraticaEntry.insert(kind: .call, at: timestamp, counterpart: "Mario Rossi", in: crlf(lf))
        #expect(crlfInsertion.text == crlf(lfInsertion.text))
        // The caret sits at the start of the empty body line, past the heading's own line break.
        let text = crlfInsertion.text as NSString
        #expect(text.substring(from: crlfInsertion.cursorRange.location) == "\r\n")
        #expect(crlfInsertion.cursorRange.length == 0)
    }
}

// MARK: - Explicit expectations, LF pins and mixed notes
//
// The twin tests above compare CRLF against the LF result, so a wrong LF result would pass them
// both. These pin the bytes, for LF and CRLF, and cover notes whose endings disagree: the app
// writes the first line break's kind and leaves every existing line as it was.

@MainActor
@Test func aQuickCaptureAddsOneLineInTheInboxsOwnBreakWhateverHowItEnds() async throws {
    let cases: [(inbox: String, expected: String)] = [
        // LF, closed and unclosed.
        ("---\ndate: 2026-09-29\n---\n\n- [ ] Prima\n", "---\ndate: 2026-09-29\n---\n\n- [ ] Prima\n- [ ] Seconda\n"),
        ("---\ndate: 2026-09-29\n---\n\n- [ ] Prima", "---\ndate: 2026-09-29\n---\n\n- [ ] Prima\n- [ ] Seconda\n"),
        // CRLF, closed and unclosed.
        (crlf("---\ndate: 2026-09-29\n---\n\n- [ ] Prima\n"), crlf("---\ndate: 2026-09-29\n---\n\n- [ ] Prima\n- [ ] Seconda\n")),
        (crlf("---\ndate: 2026-09-29\n---\n\n- [ ] Prima"), crlf("---\ndate: 2026-09-29\n---\n\n- [ ] Prima\n- [ ] Seconda\n")),
        // Mixed: LF first, last line CRLF. Already closed, so nothing extra; the new line is LF.
        ("---\ndate: 2026-09-29\n---\n\n- [ ] Prima\r\n", "---\ndate: 2026-09-29\n---\n\n- [ ] Prima\r\n- [ ] Seconda\n"),
        // Mixed: CRLF first, last line LF.
        ("---\r\ndate: 2026-09-29\r\n---\r\n\r\n- [ ] Prima\n", "---\r\ndate: 2026-09-29\r\n---\r\n\r\n- [ ] Prima\n- [ ] Seconda\r\n"),
    ]
    for (inbox, expected) in cases {
        let vault = try TemporaryVault()
        try vault.write(inbox, to: VaultSession.TaskDestination.inboxPath)
        let session = VaultSession(
            root: vault.root,
            stateBase: vault.stateBase,
            bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
        )
        await session.rescan()
        let result = try #require(await session.captureTask(VaultSession.TaskDraft(text: "Seconda")))
        #expect(result.text == expected)
    }
}

@Test func theDailyNoteMirrorAddsExactlyOneLineInTheNotesOwnBreak() throws {
    let entry = DailyNoteMirror.Entry(praticaTitle: "Offerta 2026", kind: .call, counterpart: "Mario Rossi")
    let line = DailyNoteMirror.line(for: entry)
    let cases: [(String, String)] = [
        ("# G\n\ncorpo\n", "# G\n\ncorpo\n" + line + "\n"),
        ("# G\n\ncorpo", "# G\n\ncorpo\n" + line + "\n"),
        ("# G\r\n\r\ncorpo\r\n", "# G\r\n\r\ncorpo\r\n" + line + "\r\n"),
        ("# G\r\n\r\ncorpo", "# G\r\n\r\ncorpo\r\n" + line + "\r\n"),
        // Mixed: a closing CRLF in an LF note, and a closing LF in a CRLF note.
        ("# G\n\ncorpo\r\n", "# G\n\ncorpo\r\n" + line + "\n"),
        ("# G\r\n\r\ncorpo\n", "# G\r\n\r\ncorpo\n" + line + "\r\n"),
    ]
    for (existing, expected) in cases {
        #expect(DailyNoteMirror.appending(entry, to: existing, isEnabled: true) == expected)
    }
}

@Test func anEventNoteLinkIsWrittenInTheNotesOwnBreakAndStaysInItsSection() {
    let link = "seconda"
    let cases: [(String, String)] = [
        // No section: created at the end, with one blank line before it.
        ("corpo\n", "corpo\n\n## Note\n\n- [[seconda]]\n"),
        ("corpo\r\n", "corpo\r\n\r\n## Note\r\n\r\n- [[seconda]]\r\n"),
        // A section followed by another heading: the link stays in its own section (LF, CRLF).
        ("a\n\n## Note\n\n- [[prima]]\n\n## Timeline\n\n- x\n",
         "a\n\n## Note\n\n- [[prima]]\n- [[seconda]]\n\n## Timeline\n\n- x\n"),
        ("a\r\n\r\n## Note\r\n\r\n- [[prima]]\r\n\r\n## Timeline\r\n\r\n- x\r\n",
         "a\r\n\r\n## Note\r\n\r\n- [[prima]]\r\n- [[seconda]]\r\n\r\n## Timeline\r\n\r\n- x\r\n"),
        // Mixed: the section is CRLF, the heading after it LF.
        ("a\r\n\r\n## Note\r\n\r\n- [[prima]]\n\n## Timeline\n\n- x\n",
         "a\r\n\r\n## Note\r\n\r\n- [[prima]]\r\n- [[seconda]]\r\n\n## Timeline\n\n- x\n"),
    ]
    for (note, expected) in cases {
        #expect(EventNoteSection.adding(link, to: note) == expected)
    }
}

/// The CRLF rewrite used to find no next heading, so the section ran to the end of the note and
/// the rewrite replaced every heading after it.
@Test func rewritingATimelineKeepsEveryLaterHeadingWhateverTheBreak() {
    let later = "## Altro\n\ntesto\n\n## Ancora\n\nfine\n"
    for lineBreak in ["\n", "\r\n"] {
        let note = "corpo\n\n## Timeline\n\n- 09:00-10:00 Vecchio\n\n".replacingOccurrences(of: "\n", with: lineBreak)
            + later.replacingOccurrences(of: "\n", with: lineBreak)
        for blocks in [[block(540, "Nuovo")], []] {
            let written = TimeBlockSection.write(blocks, into: note)
            #expect(written.contains(later.replacingOccurrences(of: "\n", with: lineBreak)))
            #expect(!written.contains("Vecchio"))
            #expect(blocks.isEmpty == !written.contains("Nuovo"))
        }
    }
    // A mixed note: CRLF section, LF heading after it.
    let mixed = "corpo\r\n\r\n## Timeline\r\n\r\n- 09:00-10:00 Vecchio\n\n## Altro\n\ntesto\n"
    let rewritten = TimeBlockSection.write([block(540, "Nuovo")], into: mixed)
    #expect(rewritten.hasPrefix("corpo\r\n\r\n## Timeline\r\n\r\n- 09:00-10:00 Nuovo"))
    #expect(rewritten.hasSuffix("## Altro\n\ntesto\n"))
}

@Test func aNewTimelineTakesTheNotesOwnBreakAndNoBlockTitleCarriesACarriageReturn() {
    #expect(TimeBlockSection.write([block(540, "Nuovo")], into: "corpo\n")
        == "corpo\n\n## Timeline\n\n- 09:00-10:00 Nuovo")
    #expect(TimeBlockSection.write([block(540, "Nuovo")], into: "corpo\r\n")
        == "corpo\r\n\r\n## Timeline\r\n\r\n- 09:00-10:00 Nuovo")
    let mixed = "corpo\r\n\r\n## Timeline\r\n\r\n- 09:00-10:00 Uno\n- 11:00-12:00 Due\r\n\r\n## Altro\r\n"
    let blocks = TimeBlockSection.parse(from: mixed, day: timelineDay)
    #expect(blocks.map(\.title) == ["Uno", "Due"])
    #expect(blocks.allSatisfy { !$0.title.contains("\r") })
}

@Test func aPraticaEntryPinsItsSeparatorsAndCaretInLFCRLFAndMixedNotes() {
    let timestamp = Date(timeIntervalSinceReferenceDate: 0)
    let cases: [(source: String, prefix: String, lineBreak: String)] = [
        ("", "", "\n"),
        ("t\nc", "t\nc\n\n", "\n"),
        ("t\nc\n", "t\nc\n\n", "\n"),
        ("t\nc\n\n", "t\nc\n\n", "\n"),
        ("t\r\nc", "t\r\nc\r\n\r\n", "\r\n"),
        ("t\r\nc\r\n", "t\r\nc\r\n\r\n", "\r\n"),
        ("t\r\nc\r\n\r\n", "t\r\nc\r\n\r\n", "\r\n"),
        // Mixed: CRLF first, LF last; LF first, CRLF last.
        ("t\r\nc\n", "t\r\nc\n\r\n", "\r\n"),
        ("t\nc\r\n", "t\nc\r\n\n", "\n"),
    ]
    for (source, prefix, lineBreak) in cases {
        let insertion = PraticaEntry.insert(kind: .call, at: timestamp, counterpart: "Mario Rossi", in: source)
        #expect(insertion.text.hasPrefix(prefix + "## "))
        #expect(insertion.text.hasSuffix(lineBreak + lineBreak))
        #expect(!insertion.text.hasSuffix(lineBreak + lineBreak + lineBreak))
        let text = insertion.text as NSString
        #expect(text.substring(from: insertion.cursorRange.location) == lineBreak)
    }
}

@Test func aBlankLineOnlyBodyReadsAsTheSameBlocksInAMixedNote() {
    let mixed = "# Titolo\r\nuna riga\n\n| a | b |\r\n|---|---|\n| 1 | 2 |\r\n"
    let lf = mixed.replacingOccurrences(of: "\r\n", with: "\n")
    #expect(MarkdownBlockParser.blocks(in: mixed) == MarkdownBlockParser.blocks(in: lf))
}
