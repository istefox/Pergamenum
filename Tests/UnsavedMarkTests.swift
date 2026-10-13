import Foundation
import Testing
@testable import Pergamenum

// ADR-0095 §D1 to §D3 (planned), plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 2
// (PG-406). R-03: every assignment to a buffer's text draws a new revision, and two buffers that differ in
// text never share one. R-08: the unsaved mark is on as soon as the revisions differ, never reads clean
// while the texts differ, and is cleared by `settleUnsavedMark()`, which is what the typing pause calls.
//
// The buffer is a plain value here, so nothing waits on a timer and nothing touches a disk.

private func buffer(text: String, saved: String) -> VaultController.OpenNote {
    VaultController.OpenNote(relativePath: "N.md", title: "N", text: text, savedText: saved)
}

@Suite struct UnsavedMarkTests {
    // MARK: R-03, the revision

    @Test func everyAssignmentToTheTextMakesANewRevision() {
        var note = buffer(text: "a", saved: "a")
        var seen = [note.revision]

        note.text = "b"
        #expect(!seen.contains(note.revision), "a different text kept the revision")
        seen.append(note.revision)

        note.text = "b"
        #expect(!seen.contains(note.revision), "the same string assigned again kept the revision")
        seen.append(note.revision)

        // Restated (Task 6, R-09). The red-phase step called `catchUp(to: .text("c"))` on this DIRTY buffer
        // ("b" against saved "a") and required a new revision. Departure 15 (ADR-0073, kept by ADR-0095 §D3)
        // says a dirty buffer is asked, not overwritten, when the incoming text is not its own: `.asked`
        // assigns nothing, so the revision correctly stays. The property this test guards is "every
        // assignment draws a revision", so the dirty step now asserts the opposite fact (no assignment, no
        // new revision) and the catch-ups that DO assign (a clean buffer; a dirty one whose text is exactly
        // the incoming one, which is `.adopted`) are the ones that must draw.
        let beforeAsked = note.revision
        #expect(note.catchUp(to: .text("c")) == .asked)
        #expect(note.revision == beforeAsked, "an `.asked` catch-up assigned the text")
        #expect(note.text == "b")

        #expect(note.catchUp(to: .text("b")) == .adopted, "a dirty buffer given exactly its own text")
        #expect(!seen.contains(note.revision), "catchUp(to: .text) on a dirty buffer holding it kept the revision")
        seen.append(note.revision)

        #expect(!note.differsFromSaved)
        #expect(note.catchUp(to: .text("c")) == .adopted)
        #expect(!seen.contains(note.revision), "catchUp(to: .text) on a clean buffer kept the revision")
        seen.append(note.revision)

        note.adopt("d")
        #expect(!seen.contains(note.revision), "adopt kept the revision")
    }

    // The split-editor shape: one note in two columns, each copy edited on its own.
    @Test func twoBuffersThatDifferInTextNeverShareARevision() {
        let original = buffer(text: "a", saved: "a")
        var left = original
        var right = original
        left.text = "left"
        right.text = "right"

        #expect(left.revision != right.revision)
        #expect(left.revision != original.revision)
        #expect(right.revision != original.revision)

        let first = buffer(text: "same", saved: "same")
        let second = buffer(text: "same", saved: "same")
        #expect(first.revision != second.revision, "two buffers built separately share a revision")
    }

    @Test func equalityReadsTheRevisionNotTheText() {
        let original = buffer(text: "a", saved: "a")
        var copy = original
        #expect(copy == original)

        let same = copy.text
        copy.text = same
        #expect(copy != original, "an assignment left the copy equal to the original")

        let separate = buffer(text: "a", saved: "a")
        #expect(separate != original, "two buffers built separately with equal fields compare equal")
    }

    // MARK: R-08, the mark

    @Test func aBufferBuiltWithEqualTextsIsClean() {
        let note = buffer(text: "a", saved: "a")
        #expect(!note.hasUnsavedChanges)
        #expect(!note.differsFromSaved)
    }

    @Test func aBufferBuiltWithDifferentTextsIsDirty() {
        let note = buffer(text: "a", saved: "b")
        #expect(note.hasUnsavedChanges)
        #expect(note.differsFromSaved)
    }

    // ADR-0073 departure 15 at the keystroke: the mark turns on with the first edit and an undo back to
    // the saved text does not turn it off until the pause settles it.
    @Test func anUndoBackKeepsTheMarkOnUntilSettled() {
        var note = buffer(text: "a", saved: "a")
        note.text = "b"
        #expect(note.hasUnsavedChanges)

        note.text = note.savedText
        #expect(note.hasUnsavedChanges, "the mark went off without the pause")
        #expect(!note.differsFromSaved)

        #expect(note.settleUnsavedMark() == true)
        #expect(!note.hasUnsavedChanges)
    }

    @Test func settlingADirtyBufferChangesNothing() {
        var note = buffer(text: "a", saved: "a")
        note.text = "b"
        let revision = note.revision
        let savedRevision = note.savedRevision

        #expect(note.settleUnsavedMark() == false)
        #expect(note.hasUnsavedChanges)
        #expect(note.revision == revision)
        #expect(note.savedRevision == savedRevision)
    }

    // ADR-0095 §D4: the writer links its saved text to the buffer only when the buffer holds exactly the
    // string that was written; anything typed after the text was read stays marked.
    @Test func recordWriteLinksOnlyWhenTheBufferHoldsTheWrittenText() {
        var held = buffer(text: "a", saved: "a")
        held.text = "b"
        held.recordWrite("b")
        #expect(!held.hasUnsavedChanges)
        #expect(held.savedRevision == held.revision, "the written text did not link the revisions")

        var moved = buffer(text: "a", saved: "a")
        moved.text = "b"
        moved.text = "c"
        moved.recordWrite("b")
        #expect(moved.hasUnsavedChanges, "a buffer edited after the text was read reads clean")
        #expect(moved.savedRevision != moved.revision)
        #expect(moved.differsFromSaved)
    }

    // The invariant behind the whole design: the mark may read dirty late, never clean while the text
    // differs. A seeded random sequence of every operation that touches either text or either revision.
    @Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8] as [UInt64])
    func theMarkNeverReadsCleanWhileTheTextDiffers(seed: UInt64) {
        var generator = SplitMix64(seed: seed)
        let alphabet = ["", "a", "b", "c", "d"]
        func pick() -> String { alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] }

        var note = buffer(text: "a", saved: "a")
        var log: [String] = []
        for step in 0..<200 {
            switch Int.random(in: 0..<8, using: &generator) {
            case 0:
                let next = pick()
                log.append("text = \(next)")
                note.text = next
            case 1:
                log.append("undo back")
                note.text = note.savedText
            case 2:
                let next = pick()
                log.append("adopt \(next)")
                note.adopt(next)
            case 3:
                log.append("recordWrite(text)")
                note.recordWrite(note.text)
            case 4:
                let next = pick()
                log.append("recordWrite \(next)")
                note.recordWrite(next)
            case 5:
                log.append("savedText = \"\"")
                note.savedText = ""
            case 6:
                let next = pick()
                log.append("catchUp \(next)")
                note.catchUp(to: .text(next))
            default:
                log.append("settle")
                note.settleUnsavedMark()
            }
            let context = "seed \(seed) step \(step) after \(log.suffix(4))"
            if !note.hasUnsavedChanges {
                #expect(note.text == note.savedText, "read clean while the text differs: \(context)")
            }
            #expect(note.differsFromSaved == (note.text != note.savedText), "\(context)")
            #expect(note.hasUnsavedChanges == (note.revision != note.savedRevision), "\(context)")
        }
    }

    // ADR-0073 departure 15. `catchUp` decides on the exact answer and never on the mark, so a buffer
    // undone back to its saved text but not yet settled takes the incoming text instead of asking.
    // Green on today's code, and the guard that keeps `catchUp` off the mark.
    @Test func catchUpDecidesOnTheExactAnswer() {
        var undone = buffer(text: "a", saved: "a")
        undone.text = "b"
        undone.text = "a"
        #expect(undone.catchUp(to: .text("other")) == .adopted)
        #expect(undone.text == "other")
        #expect(undone.externalChangePending == nil)

        var dirty = buffer(text: "a", saved: "a")
        dirty.text = "b"
        #expect(dirty.catchUp(to: .text("other")) == .asked)
        #expect(dirty.text == "b")
        #expect(dirty.externalChangePending == .text("other"))
    }
}
