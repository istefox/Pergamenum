import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0093 §D7 (R-03, R-04), plan docs/plans/scoped-layout-followup.md, Task 1.
//
// Undo, redo and composed text, driven through the real operation with no update pass called by hand.
// The full twin is the oracle and gets the pass by hand; the incremental editor gets only the one
// SwiftUI would run, which is the one `textDidChange`'s binding write schedules. An operation that
// never reaches `textDidChange` leaves the incremental editor unstyled and the test red.
//
// Each test prints one `real-edit-path` line per operation: R-04's evidence, quoted in the ADR.

@MainActor
@Suite(.serialized) struct RealEditPath {
    /// The checks every operation owes, in the order the plan lists them: before any pass, then after
    /// the pass SwiftUI would run.
    private func expectEqualToTheTwin(
        _ outcome: RealEditOutcome, _ op: String, _ twin: RestyleTwin, composing: Bool = false
    ) {
        print(outcome.line(op: op))
        // Before any pass.
        #expect(outcome.boundValue == outcome.text, "\(op): the binding holds \(outcome.boundValue?.count ?? -1) characters, the view \(outcome.text.count)")
        #expect(!outcome.hasUnstyledEdits, "\(op): the storage reported an edit that nothing styled")
        // After the pass, if one would have run.
        #expect(twin.incremental.textView.string == twin.full.textView.string, "\(op): text differs from the twin's")
        if let left = twin.incremental.textView.textStorage, let right = twin.full.textView.textStorage {
            #expect(StorageComparison.firstDifference(left, right) == nil, "\(op): \(StorageComparison.firstDifference(left, right) ?? "")")
        }
        #expect(twin.differences().isEmpty, "\(op): \(twin.differences())")
        #expect(twin.incremental.textView.selectedRange() == twin.full.textView.selectedRange(), "\(op): selection")
        if composing {
            #expect(twin.incremental.textView.hasMarkedText() == twin.full.textView.hasMarkedText(), "\(op): hasMarkedText")
            #expect(twin.incremental.textView.markedRange() == twin.full.textView.markedRange(), "\(op): markedRange")
        }
    }

    // MARK: Undo and redo

    // (R-03, R-04) A keystroke in the prose, then a keystroke that renumbers the list, then two undos
    // and two redos by the undo manager: after every one the incremental editor equals its twin, the
    // binding holds the text, and nothing is left unstyled before the pass.
    @Test func undoAndRedoStyleLikeAFullRestyleWithoutAHandCalledPass() async throws {
        let twin = try await RestyleTwin.rich(bindsIncremental: true)
        defer { twin.tearDown() }
        let original = twin.incremental.textView.string

        twin.realEdit { $0.type("x", at: 5) }
        let typed = twin.incremental.textView.string
        // Found after the first keystroke: it moved everything below it by one.
        let digit = (typed as NSString).range(of: "1. uno")
        try #require(digit.location != NSNotFound)
        twin.realEdit { $0.type("3", over: NSRange(location: digit.location, length: 1)) }
        let renumbered = twin.incremental.textView.string
        #expect(renumbered.contains("3. uno"), "the keystroke did not land on the list marker")
        #expect(renumbered.contains("4. due"), "the run was not renumbered after the keystroke")
        #expect(twin.differences().isEmpty, "\(twin.differences())")

        // One undo takes back the keystroke and its renumbering together.
        expectEqualToTheTwin(twin.realUndo(), "undo", twin)
        #expect(twin.incremental.textView.string == typed, "one undo did not take back the keystroke and its renumbering")
        expectEqualToTheTwin(twin.realUndo(), "undo", twin)
        #expect(twin.incremental.textView.string == original)

        // And one redo puts both back.
        expectEqualToTheTwin(twin.realRedo(), "redo", twin)
        #expect(twin.incremental.textView.string == typed)
        expectEqualToTheTwin(twin.realRedo(), "redo", twin)
        #expect(twin.incremental.textView.string == renumbered, "one redo did not put back the keystroke and its renumbering")
        #expect(twin.incremental.coordinator.restyleLog.incremental > 0, "no styling took the incremental path")
    }

    // MARK: Composed text

    // (R-03, R-04) A composition: a character set as marked text, replaced by two, then committed. The
    // marked range and the selection are the twin's after each, and the composition stands until the
    // commit ends it.
    @Test func composedTextStylesLikeAFullRestyleWithoutAHandCalledPass() async throws {
        let twin = try await RestyleTwin.rich(bindsIncremental: true)
        defer { twin.tearDown() }
        let word = (RichNote.text as NSString).range(of: "prosa")
        try #require(word.location != NSNotFound)
        let middle = word.location + 2
        // The caret goes there first, with its own pass: it is not the operation under test.
        twin.both { $0.textView.setSelectedRange(NSRange(location: middle, length: 0)) }
        twin.both { $0.runPasses() }
        #expect(twin.differences().isEmpty, "before the composition: \(twin.differences())")

        let set = twin.realEdit { fixture in
            fixture.textView.setMarkedText(
                "ñ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: middle, length: 0)
            )
        }
        expectEqualToTheTwin(set, "mark-set", twin, composing: true)
        #expect(twin.incremental.textView.hasMarkedText(), "mark-set: composition ended")
        #expect(twin.incremental.textView.markedRange() == NSRange(location: middle, length: 1))

        let replace = twin.realEdit { fixture in
            fixture.textView.setMarkedText(
                "ñé", selectedRange: NSRange(location: 2, length: 0), replacementRange: fixture.textView.markedRange()
            )
        }
        expectEqualToTheTwin(replace, "mark-replace", twin, composing: true)
        #expect(twin.incremental.textView.hasMarkedText(), "mark-replace: composition ended")
        #expect(twin.incremental.textView.markedRange() == NSRange(location: middle, length: 2))

        let commit = twin.realEdit { fixture in
            fixture.textView.insertText("ñé", replacementRange: fixture.textView.markedRange())
        }
        expectEqualToTheTwin(commit, "mark-commit", twin, composing: true)
        #expect(!twin.incremental.textView.hasMarkedText(), "mark-commit: composition did not end")
        #expect((twin.incremental.textView.string as NSString).substring(with: NSRange(location: middle, length: 2)) == "ñé")
        #expect(twin.incremental.coordinator.restyleLog.incremental > 0, "no styling took the incremental path")
    }

    // MARK: The probe

    // (R-04) The line's shape is the one the ADR quotes and a script can grep.
    @Test func theProbeLineHasTheFiveFields() {
        #expect(
            RealEditProbe.line(op: "undo", didChange: true, undoNotice: false, storageEdits: 2, styled: "incremental")
                == "real-edit-path op=undo did_change=1 undo_notice=0 storage_edits=2 styled=incremental"
        )
        #expect(
            RealEditProbe.line(op: "mark-set", didChange: false, undoNotice: true, storageEdits: 0, styled: "none")
                == "real-edit-path op=mark-set did_change=0 undo_notice=1 storage_edits=0 styled=none"
        )
    }
}
