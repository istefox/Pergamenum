import Foundation
import Testing
@testable import Pergamenum

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 7 -
// R-01, R-02, R-04, R-07, R-09, R-10; ADR §D9, §D15; UX-BLUEPRINT.md.
//
// Everything here is a value, never a view (the task's own boundary): `RecordingRow`'s,
// `RecordingsPane`'s and `ReviewSheet`'s `View` bodies do not exist yet and are not exercised
// by this suite at all - only the pure presentation types they will be built on top of
// (`RecordingRowPresentation`, `HealthBannerPresentation`, `ReviewSheetState` and its two
// nested types, all under `Sources/Features/Recordings/`). Every one of those types' bodies
// is a tester-declared stub (ADR-0155, following `RecordingsController`/`PlaudQuote`'s own
// precedent in this chain) - red first, per every task in this chain - until Task 7's coder
// builds the real per-status/per-theme mapping. A few assertions (documented inline) pass
// trivially against the stub; that is expected, not a sign the test is weak, exactly as
// `Tests/PlaudQuoteTests.swift`'s own header explains for the same pattern.

private func sampleProposal(
    themes: [PlaudTheme] = [],
    warnings: [String] = [],
    generatedAt: String = "2026-09-05T07:55:24.906Z"
) -> PlaudProposal {
    PlaudProposal(
        recording: PlaudProposalRecording(
            id: "rec-1", name: "Riunione", recordedAt: "2026-09-04T11:48:07", durationMs: 60_000
        ),
        recordingKind: .meeting,
        themes: themes,
        transcript: PlaudTranscript(language: "it", text: "Speaker 1: prova.", speakers: ["Speaker 1"]),
        warnings: warnings,
        generatedAt: generatedAt
    )
}

private func sampleTask(id: String, quote: String, dueHint: String? = nil) -> PlaudTask {
    PlaudTask(id: id, title: "Titolo \(id)", quote: quote, urgency: 4, importance: 5, dueHint: dueHint)
}

// MARK: - Row status -> badge + available actions (R-01, R-02, R-07, R-09)

@Test func aNewRecordingOffersOnlyElabora() {
    let row = RecordingRowPresentation.make(state: .new)
    #expect(row.badgeText == "nuova")
    #expect(!row.badgeSymbol.isEmpty)
    #expect(row.actions == [.elabora])
    #expect(row.errorMessage == nil)
}

@Test func aProcessingRowCarriesItsStepNameAndOffersNoAction() {
    let row = RecordingRowPresentation.make(state: .processing, stepName: "extract")
    #expect(row.badgeText == "in corso")
    #expect(row.actions.isEmpty)
    #expect(row.stepName == "extract")
}

@Test func aReadyRecordingOffersOnlyRivedi() {
    let row = RecordingRowPresentation.make(state: .ready)
    #expect(row.badgeText == "pronta")
    #expect(row.actions == [.rivedi])
}

@Test func aFailedRowShowsItsReadableErrorVerbatimAndOffersOnlyRiprova() {
    // R-07: the row must show the message the controller already mapped through
    // `PlaudError.readableLastError`, never re-derive or truncate it.
    let readable = "Il servizio non è riuscito a estrarre le attività dalla trascrizione. Riprova l'elaborazione."
    let row = RecordingRowPresentation.make(state: .failed, rowError: readable)
    #expect(row.badgeText == "fallita")
    #expect(row.actions == [.riprova])
    #expect(row.errorMessage == readable)
}

@Test func anImportedRowOffersApriNotaEliminaAndRielaboraInThatOrder() {
    let row = RecordingRowPresentation.make(state: .imported)
    #expect(row.badgeText == "importata")
    #expect(row.actions == [.apriNota, .elimina, .rielabora])
}

// MARK: - Health banner (R-02)

@Test func theHealthBannerCarriesTheExactCopyableLaunchctlCommand() {
    // Selectable text plus a copy button, never executed (SPEC, ADR §D2) - the banner must
    // carry the string a person can actually paste into a terminal, not a paraphrase of it.
    let banner = HealthBannerPresentation.make(message: "Plaud non è collegato.")
    #expect(banner.copyableCommand == HealthBannerPresentation.launchctlCommand)
    #expect(banner.message == "Plaud non è collegato.")
}

// MARK: - Review sheet initial checkbox state (R-04, ADR §D9)

@Test func everyTaskStartsCheckedWhenNothingIsSuppressed() {
    let theme = PlaudTheme(name: "Tema", tasks: [
        sampleTask(id: "t1", quote: "prima cosa da fare"),
        sampleTask(id: "t2", quote: "seconda cosa da fare"),
    ])
    let state = ReviewSheetState.makeInitial(proposal: sampleProposal(themes: [theme]), suppressedFingerprints: [])

    let tasks = state.themes.flatMap(\.tasks)
    #expect(tasks.count == 2)
    // Closure form, not `\.isInitiallyChecked`: `allSatisfy` is `rethrows`, and a keypath
    // passed directly inside `#expect`'s autoclosure trips "call can throw" here, the same
    // trap `Tests/CanvasStoreTests.swift`/`Tests/CompletionPanelTests.swift` already name.
    #expect(tasks.allSatisfy { $0.isInitiallyChecked })
    #expect(tasks.allSatisfy { !$0.isAlreadyImported })
}

@Test func aTaskWhoseFingerprintIsAlreadyImportedStartsUncheckedButIsStillShown() {
    // ADR §D9: shown with a «già importato» mark and unchecked by default, never hidden and
    // never forbidden - a person may still re-check it on purpose.
    let suppressedQuote = "seconda cosa da fare"
    let theme = PlaudTheme(name: "Tema", tasks: [
        sampleTask(id: "t1", quote: "prima cosa da fare"),
        sampleTask(id: "t2", quote: suppressedQuote),
    ])
    let state = ReviewSheetState.makeInitial(
        proposal: sampleProposal(themes: [theme]),
        suppressedFingerprints: [PlaudQuote.fingerprint(suppressedQuote)]
    )

    let byID = Dictionary(uniqueKeysWithValues: state.themes.flatMap(\.tasks).map { ($0.taskID, $0) })
    #expect(byID["t1"]?.isInitiallyChecked == true)
    #expect(byID["t1"]?.isAlreadyImported == false)
    #expect(byID["t2"]?.isInitiallyChecked == false)
    #expect(byID["t2"]?.isAlreadyImported == true)
    #expect(state.themes.flatMap(\.tasks).count == 2)
}

@Test func noActionItemsShowsItsBannerButLeavesImportEnabled() {
    // A live proposal has `themes: []` with `warnings: ["no_action_items"]` right now
    // (measured, ADR) - importing the transcript alone must still be offered.
    let state = ReviewSheetState.makeInitial(
        proposal: sampleProposal(themes: [], warnings: ["no_action_items"]), suppressedFingerprints: []
    )
    #expect(state.showsNoActionItemsBanner)
    // Passes trivially against the stub, which hard-codes `true`: this is the one field the
    // SPEC fixes as a constant regardless of input, so there is nothing for the coder to get
    // backwards here - re-asserted anyway so a future regression that computes it from
    // "anything checked" is caught.
    #expect(state.isImportEnabled)
}

// MARK: - R-10: reconstructing from a persisted draft

@Test func aMatchingDraftRestoresItsDecisionsAndSpeakerRenames() {
    let proposal = sampleProposal(
        themes: [PlaudTheme(name: "Tema", tasks: [sampleTask(id: "t1", quote: "una cosa")])],
        generatedAt: "2026-09-05T07:55:24.906Z"
    )
    let draft = PlaudVaultStore.Draft(
        generatedAt: "2026-09-05T07:55:24.906Z",
        decisions: ["t1": false],
        speakerRenames: ["Speaker 1": "Mario Rossi"]
    )

    let state = ReviewSheetState.restoring(proposal: proposal, suppressedFingerprints: [], draft: draft)

    #expect(state.themes.flatMap(\.tasks).first(where: { $0.taskID == "t1" })?.isInitiallyChecked == false)
    #expect(state.speakerRenames["Speaker 1"] == "Mario Rossi")
}

@Test func aDraftWhoseGeneratedAtDiffersIsDiscardedAndEveryTaskStartsFreshlyChecked() {
    // R-10's boundary (ADR §D12): task ids are stable only within one proposal, so a draft
    // taken against an older `generated_at` must not apply its decisions to a different run.
    let proposal = sampleProposal(
        themes: [PlaudTheme(name: "Tema", tasks: [sampleTask(id: "t1", quote: "una cosa")])],
        generatedAt: "2026-09-05T07:55:24.906Z"
    )
    let staleDraft = PlaudVaultStore.Draft(
        generatedAt: "2026-09-04T07:55:24.906Z", decisions: ["t1": false], speakerRenames: [:]
    )

    let state = ReviewSheetState.restoring(proposal: proposal, suppressedFingerprints: [], draft: staleDraft)

    #expect(state.themes.flatMap(\.tasks).first(where: { $0.taskID == "t1" })?.isInitiallyChecked == true)
    #expect(state.speakerRenames.isEmpty)
}
