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

private func sampleRecording(
    id: String = "rec-1", name: String = "Registrazione", recordedAt: String = "2026-09-04T11:00:00",
    state: PlaudRecordingState = .new
) -> PlaudRecording {
    PlaudRecording(
        id: id, name: name, recordedAt: recordedAt, durationMs: 60_000,
        deviceSerial: "device-1", state: state, lastError: nil
    )
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

// MARK: - Row's effective state while a poll is in progress (Task 10 bug-fix follow-up)
//
// Task 10's live HITL walkthrough of ADR-0032: `RecordingsPane.row(_:)` built its presentation
// straight off the recording's own cached wire `state`, never consulting
// `RecordingsController.pollingRecordingIDs` - a recording being polled showed its stale
// "fallita"/"nuova" badge for the whole poll instead of "in corso". `effectiveState` is the
// pure function `row(_:)` must be rewritten to call; its body is still a tester-declared stub
// (ignores `pollingIDs` unconditionally), so the first assertion below is red until the coder
// implements it.

@Test func aRecordingBeingPolledShowsProcessingRegardlessOfItsOwnCachedState() {
    let stale = sampleRecording(state: .failed)
    let effective = RecordingsPane.effectiveState(recording: stale, pollingIDs: [stale.id])
    #expect(effective == .processing)
}

@Test func aRecordingNotBeingPolledKeepsItsOwnCachedState() {
    // Passes trivially against the stub, which always returns `recording.state`: kept anyway
    // so a future fix that always reports `.processing` regardless of `pollingIDs` is caught,
    // the same reasoning `noActionItemsShowsItsBannerButLeavesImportEnabled` documents above.
    let ready = sampleRecording(state: .ready)
    let effective = RecordingsPane.effectiveState(recording: ready, pollingIDs: ["some-other-id"])
    #expect(effective == .ready)
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

// MARK: - List order (newest first / oldest first)

// The wire order is never trusted: `RecordingFormat.ordered` reads `recorded_at` itself, through
// the same `PlaudTimestamp` the row's date goes through, so a sort and the date beside it cannot
// disagree.

private let unorderedRecordings = [
    sampleRecording(id: "mid", name: "Centrale", recordedAt: "2026-09-04T11:00:00"),
    sampleRecording(id: "new", name: "Recente", recordedAt: "2026-09-05T09:00:00"),
    sampleRecording(id: "old", name: "Vecchia", recordedAt: "2026-09-03T08:00:00")
]

@Test func recordingsSortNewestFirstByTheirRecordingInstant() {
    let ordered = RecordingFormat.ordered(unorderedRecordings, by: .newestFirst)

    #expect(ordered.map(\.id) == ["new", "mid", "old"])
}

@Test func recordingsSortOldestFirstWhenAsked() {
    let ordered = RecordingFormat.ordered(unorderedRecordings, by: .oldestFirst)

    #expect(ordered.map(\.id) == ["old", "mid", "new"])
}

@Test func mixedWireShapesFallIntoOneTimeline() {
    // The three shapes `PlaudTimestamp` reads: zone-less UTC, plain `Z`, fractional-second `Z`.
    let mixed = [
        sampleRecording(id: "zoneless", recordedAt: "2026-09-04T11:00:00"),
        sampleRecording(id: "plainZ", recordedAt: "2026-09-04T12:00:00Z"),
        sampleRecording(id: "fractional", recordedAt: "2026-09-04T10:00:00.500Z")
    ]

    #expect(RecordingFormat.ordered(mixed, by: .oldestFirst).map(\.id) == ["fractional", "zoneless", "plainZ"])
}

@Test func anUnreadableRecordedAtSortsLastInBothDirections() {
    let withUnknown = unorderedRecordings + [
        sampleRecording(id: "unknown-b", name: "B", recordedAt: "ieri"),
        sampleRecording(id: "unknown-a", name: "A", recordedAt: "")
    ]

    // Neither old nor new: after every dated recording whichever way the list runs, and the
    // unreadable block itself in name order both times.
    #expect(RecordingFormat.ordered(withUnknown, by: .newestFirst).map(\.id)
        == ["new", "mid", "old", "unknown-a", "unknown-b"])
    #expect(RecordingFormat.ordered(withUnknown, by: .oldestFirst).map(\.id)
        == ["old", "mid", "new", "unknown-a", "unknown-b"])
}

@Test func recordingsSharingAnInstantKeepTheirNameThenIdOrderInBothDirections() {
    let sameInstant = [
        sampleRecording(id: "3", name: "B", recordedAt: "2026-09-04T11:00:00"),
        sampleRecording(id: "2", name: "A", recordedAt: "2026-09-04T11:00:00"),
        sampleRecording(id: "1", name: "A", recordedAt: "2026-09-04T11:00:00")
    ]

    // The tie-break is a determinism device and never inverts with the direction.
    #expect(RecordingFormat.ordered(sameInstant, by: .newestFirst).map(\.id) == ["1", "2", "3"])
    #expect(RecordingFormat.ordered(sameInstant, by: .oldestFirst).map(\.id) == ["1", "2", "3"])
}

@Test func orderingNoRecordingsReturnsNone() {
    #expect(RecordingFormat.ordered([], by: .newestFirst).isEmpty)
}
