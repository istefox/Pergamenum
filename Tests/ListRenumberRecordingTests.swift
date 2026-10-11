import AppKit
import Testing
@testable import Pergamenum

// ADR-0082 §D6, plan docs/plans/pg-385-n2-page.md, Task 4 (PG-385, R-16). (coverage)
//
// The scoped renumber is only as good as the range it is handed. `NoteListEditingTests` proves a
// real delete ends in the right text, caret and undo step; this file pins the recording itself,
// which that test reaches with one range and no replacement arithmetic: the post-edit range of a
// multi-range change, an absent `replacementStrings`, nothing recorded while undoing, and the
// record being consumed by `textDidChange` so a later change never inherits it.

@MainActor
@Suite struct ListRenumberRecording {
    private func fixture(_ text: String = "uno\ndue\ntre\nquattro\ncinque") -> ScrolledEditorFixture {
        ScrolledEditorFixture(text: text, width: 600, height: 300)
    }

    private func record(
        _ fixture: ScrolledEditorFixture, _ ranges: [NSRange], _ replacements: [String]?
    ) -> NSRange? {
        fixture.coordinator.renumbering.editedRange = nil
        _ = fixture.coordinator.textView(
            fixture.textView, shouldChangeTextInRanges: ranges.map { NSValue(range: $0) }, replacementStrings: replacements
        )
        return fixture.coordinator.renumbering.editedRange
    }

    // (n2-page R-16) A single replacement is recorded where it will stand after the change:
    // its own location, the replacement's length.
    @Test func aSingleRangeIsRecordedAsItWillStandAfterTheChange() {
        let fixture = fixture()
        defer { fixture.window.orderOut(nil) }

        #expect(record(fixture, [NSRange(location: 4, length: 3)], ["ab"]) == NSRange(location: 4, length: 2))
        #expect(record(fixture, [NSRange(location: 4, length: 0)], ["xyz"]) == NSRange(location: 4, length: 3))
        #expect(record(fixture, [NSRange(location: 4, length: 3)], [""]) == NSRange(location: 4, length: 0), "a deletion")
    }

    // (n2-page R-16) Several ranges: each one's location moves by the length changes before it, and
    // the record is their union, so the widening sees the whole change.
    @Test func severalRangesAreRecordedAsTheUnionOfTheirPostEditRanges() {
        let fixture = fixture()
        defer { fixture.window.orderOut(nil) }

        // 5..<7 becomes "x" (-1), so the second range, 20..<21 becomes "abc" at 19..<22.
        let union = record(fixture, [NSRange(location: 5, length: 2), NSRange(location: 20, length: 1)], ["x", "abc"])

        #expect(union == NSRange(location: 5, length: 17), "5..<6 and 19..<22 unite as 5..<22")
    }

    // (n2-page R-16) With no replacement strings the change keeps each range's own length.
    @Test func withoutReplacementStringsEachRangeKeepsItsLength() {
        let fixture = fixture()
        defer { fixture.window.orderOut(nil) }

        #expect(record(fixture, [NSRange(location: 8, length: 4)], nil) == NSRange(location: 8, length: 4))
        // 2..<3 becomes the 14-character string (+13), so the second range, with no string, stays
        // 2 long and lands at 22..<24; the union with 2..<16 is 2..<24.
        #expect(record(fixture, [NSRange(location: 2, length: 1), NSRange(location: 9, length: 2)], ["only the first"])
            == NSRange(location: 2, length: 22), "a missing string falls back to its range's length")
    }

    // (n2-page R-16) The delegate only watches: it always lets the change through.
    @Test func recordingAlwaysAllowsTheChange() {
        let fixture = fixture()
        defer { fixture.window.orderOut(nil) }

        let allowed = fixture.coordinator.textView(
            fixture.textView, shouldChangeTextInRanges: [NSValue(range: NSRange(location: 0, length: 1))],
            replacementStrings: ["z"]
        )

        #expect(allowed)
    }

    // (n2-page R-16) A change made while the undo manager is undoing records nothing and clears a
    // stale record, so an undo takes the whole-text fallback.
    @Test func nothingIsRecordedWhileUndoing() throws {
        let fixture = fixture()
        defer { fixture.window.orderOut(nil) }
        let undo = try #require(fixture.textView.undoManager)
        fixture.coordinator.renumbering.editedRange = NSRange(location: 1, length: 1)

        undo.beginUndoGrouping()
        undo.registerUndo(withTarget: fixture.coordinator) { target in
            MainActor.assumeIsolated {
                guard let textView = target.textView else { return }
                _ = target.textView(
                    textView, shouldChangeTextInRanges: [NSValue(range: NSRange(location: 2, length: 3))],
                    replacementStrings: ["abc"]
                )
            }
        }
        undo.endUndoGrouping()
        undo.undo()

        #expect(fixture.coordinator.renumbering.editedRange == nil, "an undo leaves no record, stale or new")
    }

    // (n2-page R-16) `textDidChange` consumes the record: after a keystroke nothing is left for the
    // next, programmatic change to inherit.
    @Test func aKeystrokeLeavesNoRecordBehind() {
        let fixture = fixture()
        defer { fixture.window.orderOut(nil) }

        fixture.type("x", at: 3)

        #expect(fixture.coordinator.renumbering.editedRange == nil)
    }

    // (n2-page R-16) `take()` returns the record once and clears it.
    @Test func takingTheRecordClearsIt() {
        let ledger = ListRenumberLedger()
        ledger.editedRange = NSRange(location: 4, length: 2)

        #expect(ledger.take() == NSRange(location: 4, length: 2))
        #expect(ledger.take() == nil)
        #expect(ledger.editedRange == nil)
    }
}
