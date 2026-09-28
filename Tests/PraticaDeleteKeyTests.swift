import Foundation
import Testing
@testable import Pergamenum

// PG-298, ADR-0070 §D2 (`docs/plans/pg-298-timeline-backspace-exclude.md`, Task 2) - R-01,
// R-04, R-06.
//
// Pins two things: the pure rule (`PraticaTimelineModel.deleteKeyTarget`) and the door built
// over it (`PraticheController.takeDeleteKeyTarget`), which is what Backspace calls (Task 5).
// The GUI witnesses in `UITests/PraticheUITests.swift` (Task 4) are what prove a real key
// reaches this door at all - in-process cannot deliver a `List`'s Backspace (ADR-0070 F10).
//
// Expected red until Task 5: "is the target" and "returns that entry" - both bodies are still
// `nil` stubs declared by Task 2.

private let seedDate = Date(timeIntervalSince1970: 1_749_557_170)

private func message(_ id: String) -> PraticaTimelineEntry {
    PraticaTimelineEntry(
        id: id, kind: .message, date: seedDate, direction: .received, senderDisplayName: "Mario Rossi",
        subject: "Oggetto", bodyPreview: "Corpo", hasAttachments: false, messageID: "<\(id)@rossi-spa.it>",
        isInMail: true
    )
}

private func manualEntry(_ id: String, kind: PraticaTimelineEntry.Kind) -> PraticaTimelineEntry {
    PraticaTimelineEntry(
        id: id, kind: kind, date: seedDate, direction: nil, senderDisplayName: "",
        subject: "", bodyPreview: "", hasAttachments: false, messageID: nil, isInMail: true
    )
}

@MainActor
private func newController() -> PraticheController {
    PraticheController(probe: { .granted }, performSync: { _, _ in })
}

// MARK: - The pure rule

@Suite struct PraticaDeleteKeyRuleTests {
    @Test func aSelectedMessagePresentInTheEntriesIsTheTarget() {
        let entries = [message("a"), message("b")]
        let target = PraticaTimelineModel.deleteKeyTarget(selectedID: "b", in: entries)
        #expect(target?.id == "b")
    }

    @Test func aSelectedManualEntryAnswersNilForEachKind() {
        let entries = [manualEntry("note-1", kind: .note), manualEntry("call-1", kind: .call)]
        #expect(PraticaTimelineModel.deleteKeyTarget(selectedID: "note-1", in: entries) == nil)
        #expect(PraticaTimelineModel.deleteKeyTarget(selectedID: "call-1", in: entries) == nil)
    }

    @Test func noSelectionAnswersNil() {
        let entries = [message("a")]
        #expect(PraticaTimelineModel.deleteKeyTarget(selectedID: nil, in: entries) == nil)
    }

    @Test func anIdAbsentFromTheEntriesAnswersNil() {
        let entries = [message("a")]
        #expect(PraticaTimelineModel.deleteKeyTarget(selectedID: "other-pratica/email/x.md", in: entries) == nil)
    }
}

// MARK: - The door

@MainActor
@Suite struct PraticaDeleteKeyDoorTests {
    @Test func withAVisibleMessageSelectedItReturnsThatEntryAndClearsTheSelection() {
        let pratiche = newController()
        pratiche.timeline = [message("a"), message("b")]
        pratiche.selectedEntryID = "b"

        let target = pratiche.takeDeleteKeyTarget()

        #expect(target?.id == "b")
        #expect(pratiche.selectedEntryID == nil)
    }

    @Test func calledTwiceInARowTheSecondCallAnswersNil() {
        let pratiche = newController()
        pratiche.timeline = [message("a")]
        pratiche.selectedEntryID = "a"

        let first = pratiche.takeDeleteKeyTarget()
        let second = pratiche.takeDeleteKeyTarget()

        #expect(first?.id == "a")
        #expect(second == nil)
    }

    @Test func withAManualEntrySelectedItAnswersNilAndLeavesTheSelectionUnchanged() {
        let pratiche = newController()
        pratiche.timeline = [manualEntry("note-1", kind: .note)]
        pratiche.selectedEntryID = "note-1"

        let target = pratiche.takeDeleteKeyTarget()

        #expect(target == nil)
        #expect(pratiche.selectedEntryID == "note-1")
    }

    @Test func withTheFilterHidingTheSelectedMessageItAnswersNilAndLeavesTheSelectionUnchanged() {
        let pratiche = newController()
        pratiche.timeline = [message("a"), message("b")]
        pratiche.selectedEntryID = "b"
        pratiche.filter = PraticaTimelineFilter(text: "nothing matches this")

        let target = pratiche.takeDeleteKeyTarget()

        #expect(target == nil)
        #expect(pratiche.selectedEntryID == "b")
    }
}
