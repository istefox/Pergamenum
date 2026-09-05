import Foundation
import Testing
@testable import Pergamenum

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 4 -
// R-05; ADR §D6, §D7, §D9, §D10, §D11.
//
// `TranscriptNote.render` is a pure function; its production body is a tester-declared
// stub (see `Sources/Features/Recordings/TranscriptNote.swift`), so every positive
// assertion below is red until the coder implements it - the one named exception is the
// linter test at the bottom, which is expected to stay red until Task 9 lands the
// frontmatter allowance, independent of `render` itself.

private func makeTask(
    id: String,
    title: String,
    quote: String,
    urgency: Int = 3,
    importance: Int = 4,
    dueHint: String? = nil
) -> PlaudTask {
    PlaudTask(id: id, title: title, quote: quote, urgency: urgency, importance: importance, dueHint: dueHint)
}

private func makeProposal(
    recordingID: String = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",
    name: String = "Riunione di prova",
    recordedAt: String = "2026-09-04T11:48:07",
    durationMs: Int = 1_236_000,
    kind: PlaudRecordingKind = .meeting,
    themes: [PlaudTheme],
    transcriptText: String = "Speaker 1: Prova di trascrizione.",
    speakers: [String] = ["Speaker 1"],
    warnings: [String] = [],
    generatedAt: String = "2026-09-05T07:55:24.906Z"
) -> PlaudProposal {
    PlaudProposal(
        recording: PlaudProposalRecording(
            id: recordingID, name: name, recordedAt: recordedAt, durationMs: durationMs
        ),
        recordingKind: kind,
        themes: themes,
        transcript: PlaudTranscript(language: "it", text: transcriptText, speakers: speakers),
        warnings: warnings,
        generatedAt: generatedAt
    )
}

/// Pulls the quote out of a rendered task line's `(urgenza N/5, importanza N/5 — "…")`
/// suffix - the same shape `TranscriptNote.suppressionSet` has to read back (ADR §D9).
private func extractedQuote(fromLine line: String) -> String? {
    guard let openQuote = line.range(of: "— \""), let close = line.range(of: "\")", options: .backwards)
    else { return nil }
    return String(line[openQuote.upperBound..<close.lowerBound])
}

// MARK: - Frontmatter (D6)

@Test func buildsFrontmatterThroughTheRealSerializerNeverByHand() throws {
    let proposal = makeProposal(themes: [
        PlaudTheme(name: "Azioni", tasks: [makeTask(id: "t1", title: "Fare qualcosa", quote: "una citazione di prova")]),
    ])
    let text = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: ["t1"], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: nil
    )

    // If the frontmatter were hand-written YAML rather than built through
    // `FrontmatterSerializer.render`, parsing it back and re-serializing would not be
    // guaranteed to reproduce the same bytes.
    let document = NoteDocument.parse(text)
    #expect(document.hasFrontmatterBlock)
    #expect(document.serialized() == text)

    #expect(document.frontmatter.date == CalendarDate(iso: "2026-09-04"))
    let foreignNames = document.frontmatter.foreignKeys.map(\.name)
    #expect(foreignNames.contains("pergamenum-plaud-id"))
    #expect(foreignNames.contains("pergamenum-plaud-recorded-at"))
    #expect(foreignNames.contains("pergamenum-plaud-duration-ms"))

    let idLines = document.frontmatter.foreignKeys.first { $0.name == "pergamenum-plaud-id" }?.lines ?? []
    #expect(idLines.contains { $0.contains("a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6") })
    let recordedAtLines = document.frontmatter.foreignKeys.first { $0.name == "pergamenum-plaud-recorded-at" }?.lines ?? []
    #expect(recordedAtLines.contains { $0.contains("2026-09-04T11:48:07") })
    let durationLines = document.frontmatter.foreignKeys.first { $0.name == "pergamenum-plaud-duration-ms" }?.lines ?? []
    #expect(durationLines.contains { $0.contains("1236000") })
}

// MARK: - Tags (D7)

@Test func writesTheThreeTagsOnlyForAMeetingRecording() {
    let proposal = makeProposal(kind: .meeting, themes: [])
    let text = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: [], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: nil
    )
    let tags = NoteDocument.parse(text).frontmatter.tags.map(\.description)
    #expect(tags.contains("type-note"))
    #expect(tags.contains("topic-trascrizione"))
    #expect(tags.contains("source-meeting"))
}

@Test(arguments: [PlaudRecordingKind.lecture, .update, .personal])
func omitsSourceMeetingForAnyOtherKind(_ kind: PlaudRecordingKind) {
    let proposal = makeProposal(kind: kind, themes: [])
    let text = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: [], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: nil
    )
    let tags = NoteDocument.parse(text).frontmatter.tags.map(\.description)
    #expect(tags.contains("type-note"))
    #expect(tags.contains("topic-trascrizione"))
    #expect(!tags.contains("source-meeting"))
}

// MARK: - Body order (D11)

@Test func ordersThemesBeforeTrascrizioneWhichComesLast() throws {
    let proposal = makeProposal(themes: [
        PlaudTheme(name: "Tema A", tasks: [makeTask(id: "t1", title: "Uno", quote: "quote uno")]),
        PlaudTheme(name: "Tema B", tasks: [makeTask(id: "t2", title: "Due", quote: "quote due")]),
    ])
    let text = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: ["t1", "t2"], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: nil
    )

    let temaA = try #require(text.range(of: "## Tema A"))
    let temaB = try #require(text.range(of: "## Tema B"))
    let trascrizione = try #require(text.range(of: "## Trascrizione"))
    #expect(temaA.lowerBound < temaB.lowerBound)
    #expect(temaB.lowerBound < trascrizione.lowerBound)
}

// MARK: - Task line shape (C7, D9, D10)

@Test func writesTheDueMarkerOnlyWhenDueHintIsPresent() throws {
    let proposal = makeProposal(themes: [
        PlaudTheme(name: "Azioni", tasks: [
            makeTask(id: "t1", title: "Con scadenza", quote: "prima citazione", dueHint: "2026-09-10"),
            makeTask(id: "t2", title: "Senza scadenza", quote: "seconda citazione", dueHint: nil),
        ]),
    ])
    let text = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: ["t1", "t2"], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: nil
    )

    let lines = text.components(separatedBy: "\n")
    let withDue = try #require(lines.first { $0.contains("Con scadenza") })
    let withoutDue = try #require(lines.first { $0.contains("Senza scadenza") })

    let dueTask = try #require(TaskParser.parse(line: withDue, sourcePath: "x", lineIndex: 0))
    #expect(dueTask.scheduled == CalendarDate(iso: "2026-09-10"))

    let noDueTask = try #require(TaskParser.parse(line: withoutDue, sourcePath: "x", lineIndex: 0))
    #expect(noDueTask.scheduled == nil)
}

@Test func writesUrgencyImportanceAndTheQuoteVerbatim() throws {
    let proposal = makeProposal(themes: [
        PlaudTheme(name: "Azioni", tasks: [
            makeTask(id: "t1", title: "Fare la cosa", quote: "una citazione precisa", urgency: 5, importance: 2),
        ]),
    ])
    let text = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: ["t1"], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: nil
    )
    let line = try #require(text.components(separatedBy: "\n").first { $0.contains("Fare la cosa") })
    #expect(line.contains("(urgenza 5/5, importanza 2/5 — \"una citazione precisa\")"))
}

@Test func sanitizesForbiddenCharactersAndNewlinesOutOfTheWrittenQuoteWithoutChangingItsFingerprint() throws {
    // ADR §D10: `>`, `#`, `^`, `[`, `]` and any newline become a space in the written
    // quote, and the invariant this rests on is that sanitation is invisible to the
    // fingerprint.
    let rawQuote = "Testo > con # marcatori ^ e [parentesi] quadre\ne una nuova riga"
    let proposal = makeProposal(themes: [
        PlaudTheme(name: "Azioni", tasks: [makeTask(id: "t1", title: "Task", quote: rawQuote)]),
    ])
    let text = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: ["t1"], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: nil
    )
    let line = try #require(text.components(separatedBy: "\n").first { $0.contains("Task") && $0.contains("—") })
    let writtenQuote = try #require(extractedQuote(fromLine: line))

    for forbidden in [">", "#", "^", "[", "]"] {
        #expect(!writtenQuote.contains(forbidden), "written quote still contains \(forbidden)")
    }
    #expect(!writtenQuote.contains("\n"))
    #expect(PlaudQuote.fingerprint(writtenQuote) == PlaudQuote.fingerprint(rawQuote))
}

@Test func quoteIsNeverTruncated() throws {
    let longQuote = String(repeating: "parola ", count: 40).trimmingCharacters(in: .whitespaces)
    let proposal = makeProposal(themes: [
        PlaudTheme(name: "Azioni", tasks: [makeTask(id: "t1", title: "Task", quote: longQuote)]),
    ])
    let text = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: ["t1"], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: nil
    )
    let line = try #require(text.components(separatedBy: "\n").first { $0.contains("Task") && $0.contains("—") })
    let writtenQuote = try #require(extractedQuote(fromLine: line))
    #expect(writtenQuote == longQuote)
}

// MARK: - Speaker rename (C6)

@Test func renamesOnlyTheLineWhoseTrimmedPrefixIsExactlyTheLabel() {
    let proposal = makeProposal(
        themes: [],
        transcriptText: "Speaker 1: Buongiorno a tutti.\nSpeaker 10: Anche a te buongiorno.",
        speakers: ["Speaker 1", "Speaker 10"]
    )
    let text = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: [], speakerRenames: ["Speaker 1": "Mario Rossi"],
        ledgerFingerprints: [], existingNoteText: nil
    )

    #expect(text.contains("Mario Rossi: Buongiorno a tutti."))
    // "Speaker 1" must not match inside "Speaker 10".
    #expect(text.contains("Speaker 10: Anche a te buongiorno."))
    #expect(!text.contains("Mario Rossi0:"))
}

@Test func leavesAnAlreadyResolvedSpeakerAloneWithNoRenameSupplied() {
    let proposal = makeProposal(
        themes: [],
        transcriptText: "Nome Cognome A: Il servizio ha già risolto questo speaker.",
        speakers: ["Nome Cognome A"]
    )
    let text = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: [], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: nil
    )
    #expect(text.contains("Nome Cognome A: Il servizio ha già risolto questo speaker."))
}

// MARK: - The linter (D6/D7, Task 9)

@MainActor
@Test func aRenderedNoteIsExpectedToFailTheLinterUntilTask9LandsTheFrontmatterAllowance() async throws {
    // INTENTIONALLY RED, per this dispatch's brief: `pergamenum-plaud-*` keys are still
    // reported as `.foreignKey` findings until Task 9 (ADR §D6). This is not a mistake -
    // it is the "#30 standard" (the app must not generate a file its own linter flags)
    // pinned as a test before the fix exists, so Task 9 has something concrete to make
    // green.
    let vault = try TemporaryVault()
    let proposal = makeProposal(themes: [
        PlaudTheme(name: "Azioni", tasks: [makeTask(id: "t1", title: "Fare una cosa", quote: "una prova")]),
    ])
    let text = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: ["t1"], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: nil
    )
    let path = "Registrazioni/Nota di prova.md"
    try vault.write(text, to: path)

    let session = VaultSession(
        root: vault.root, stateBase: vault.stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    await session.rescan()
    let violations = try #require(session.violations(forRecordAt: path))
    #expect(violations.isEmpty, "\(violations)")
}
