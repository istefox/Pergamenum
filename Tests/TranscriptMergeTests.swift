import Foundation
import Testing
@testable import Pergamenum

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 5 -
// R-08; ADR §D9, §D11.
//
// `TranscriptNote.render`'s merge path - the same function as `Tests/TranscriptNoteTests.swift`,
// exercised here with a non-nil `existingNoteText`. Production body is a tester-declared
// stub, so every test below is red until the coder implements the real merge.

private func makeTask(
    id: String, title: String, quote: String, urgency: Int = 3, importance: Int = 4, dueHint: String? = nil
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

@Test func reimportingTheIdenticalProposalProducesAByteIdenticalNote() {
    let proposal = makeProposal(themes: [
        PlaudTheme(name: "Azioni", tasks: [
            makeTask(id: "t1", title: "Uno", quote: "prima quote"),
            makeTask(id: "t2", title: "Due", quote: "seconda quote"),
        ]),
    ])
    let accepted: Set<String> = ["t1", "t2"]

    let first = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: accepted, speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: nil
    )
    let second = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: accepted, speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: first
    )

    #expect(second == first)
}

@Test func reimportingWithOneNewAcceptedTaskAppendsExactlyOneLine() {
    let proposal = makeProposal(themes: [
        PlaudTheme(name: "Azioni", tasks: [
            makeTask(id: "t1", title: "Uno", quote: "prima quote"),
            makeTask(id: "t2", title: "Due", quote: "seconda quote"),
        ]),
    ])
    let firstRun = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: ["t1"], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: nil
    )
    let secondRun = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: ["t1", "t2"], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: firstRun
    )

    let firstLines = Set(firstRun.components(separatedBy: "\n"))
    let addedLines = secondRun.components(separatedBy: "\n").filter { !firstLines.contains($0) }

    #expect(addedLines.count == 1, "\(addedLines)")
    #expect(addedLines.first?.contains("Due") == true)
}

@Test func aTaskDeletedFromTheNoteButStillInTheLedgerDoesNotReturn() {
    let proposal = makeProposal(themes: [
        PlaudTheme(name: "Azioni", tasks: [
            makeTask(id: "t1", title: "Uno", quote: "prima quote"),
            makeTask(id: "t2", title: "Due", quote: "seconda quote"),
        ]),
    ])
    let originalNote = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: ["t1", "t2"], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: nil
    )
    // The person deleted "Due"'s line from the note by hand - the note itself no longer
    // carries its fingerprint.
    let editedByHand = originalNote.components(separatedBy: "\n")
        .filter { !$0.contains("Due") }
        .joined(separator: "\n")

    // The ledger still remembers it (it only ever grows, ADR §D9), so a forced re-run
    // with the task still accepted must not bring it back.
    let ledgerFingerprints = [PlaudQuote.fingerprint("seconda quote")]
    let rerun = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: ["t1", "t2"], speakerRenames: [:],
        ledgerFingerprints: ledgerFingerprints, existingNoteText: editedByHand
    )

    #expect(!rerun.contains("Due"))
    #expect(rerun.contains("Uno"))
}

@Test func anEditedQuoteReturnsAsADuplicateOnlyWhenTheLedgerHasAlsoLostIt() {
    let proposal = makeProposal(themes: [
        PlaudTheme(name: "Azioni", tasks: [makeTask(id: "t1", title: "Uno", quote: "quote originale")]),
    ])
    let originalNote = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: ["t1"], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: nil
    )
    // The person hand-edits the quote inside the note: reading the note back no longer
    // finds this task's original fingerprint.
    let editedByHand = originalNote.replacingOccurrences(of: "quote originale", with: "quote modificata a mano")
    let originalFingerprint = PlaudQuote.fingerprint("quote originale")

    // The ledger still remembers the original fingerprint: still suppressed, no
    // duplicate line is added.
    let stillSuppressed = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: ["t1"], speakerRenames: [:],
        ledgerFingerprints: [originalFingerprint], existingNoteText: editedByHand
    )
    #expect(!stillSuppressed.contains("quote originale"))
    #expect(stillSuppressed.components(separatedBy: "quote modificata a mano").count == 2)

    // The ledger has also lost it (e.g. a fresh ledger): not suppressed, and the task
    // comes back, creating a duplicate line beside the hand-edited one.
    let duplicated = TranscriptNote.render(
        proposal: proposal, acceptedTaskIDs: ["t1"], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: editedByHand
    )
    #expect(duplicated.contains("quote modificata a mano"))
    #expect(duplicated.contains("quote originale"))
}

@Test func aNewThemeAddsANewSectionWithoutDisturbingTheOthers() throws {
    let proposalV1 = makeProposal(themes: [
        PlaudTheme(name: "Tema A", tasks: [makeTask(id: "t1", title: "Uno", quote: "quote uno")]),
    ])
    let noteV1 = TranscriptNote.render(
        proposal: proposalV1, acceptedTaskIDs: ["t1"], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: nil
    )

    let proposalV2 = makeProposal(themes: [
        PlaudTheme(name: "Tema A", tasks: [makeTask(id: "t1", title: "Uno", quote: "quote uno")]),
        PlaudTheme(name: "Tema B", tasks: [makeTask(id: "t2", title: "Due", quote: "quote due")]),
    ])
    let noteV2 = TranscriptNote.render(
        proposal: proposalV2, acceptedTaskIDs: ["t1", "t2"], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: noteV1
    )

    let temaA = try #require(noteV2.range(of: "## Tema A"))
    let temaB = try #require(noteV2.range(of: "## Tema B"))
    let trascrizione = try #require(noteV2.range(of: "## Trascrizione"))
    #expect(temaA.lowerBound < temaB.lowerBound)
    #expect(temaB.lowerBound < trascrizione.lowerBound)
    #expect(noteV2.contains("quote uno"), "Tema A's own line must survive untouched")
}

@Test func trascrizioneIsReplacedWholesaleNeverMerged() {
    // The asymmetry ADR §D11 pins: theme sections merge, the transcript does not - a
    // forced re-run may produce a better transcript.
    let proposalV1 = makeProposal(themes: [], transcriptText: "Speaker 1: prima versione della trascrizione.")
    let noteV1 = TranscriptNote.render(
        proposal: proposalV1, acceptedTaskIDs: [], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: nil
    )
    #expect(noteV1.contains("prima versione della trascrizione."))

    let proposalV2 = makeProposal(themes: [], transcriptText: "Speaker 1: seconda versione, migliore, della trascrizione.")
    let noteV2 = TranscriptNote.render(
        proposal: proposalV2, acceptedTaskIDs: [], speakerRenames: [:],
        ledgerFingerprints: [], existingNoteText: noteV1
    )

    #expect(noteV2.contains("seconda versione, migliore, della trascrizione."))
    #expect(!noteV2.contains("prima versione della trascrizione."))
}
