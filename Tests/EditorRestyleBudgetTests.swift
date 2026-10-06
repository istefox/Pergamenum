import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0082 §D5, plan docs/plans/pg-385-n2-page.md, Task 1 (PG-385, R-15).
//
// What a keystroke costs in a long note, as a number measured every turn and guarded by a
// ceiling: one `insertText("x")` in the middle of a hosted `NoteTextView`, which runs
// `textDidChange`'s whole synchronous pipeline (styling, embeds, transclusions, renumbering,
// reveal, grow to fit). Thread CPU time, minimum of K runs after one warm-up. Wall time is
// printed beside it and never asserted. The deferred display pass is not included, and neither
// is the re-pass the SwiftUI update runs after the binding write (`runPasses`): a keystroke in
// the app costs about two pipelines, which ADR-0082 §D5 names as outside the measurement.
//
// The suite lives in `PergamenumTests`, so the Stop hook runs it every turn, where it asserts the
// two 50 KB rows; the 200 KB and 1 MB rows run behind `RESTYLE_BUDGET_200KB` and
// `RESTYLE_BUDGET_1MB` (`RestyleBudget.activeCases`, ADR-0082 §D9). `scripts/
// editor-restyle-bench.sh` runs it alone, with the 200 KB rows, and prints the lines as a table.

@MainActor
@Suite(.serialized) struct EditorRestyleBudgetTests {
    // MARK: Pure (seam 1)

    // (n2-page R-15)
    @Test func theProvisionalCeilingIsThreeTimesTheBeforeRoundedUpToAWholeMillisecond() {
        #expect(RestyleBudget.provisionalCeiling(before: 10) == 30)
        #expect(RestyleBudget.provisionalCeiling(before: 4.2) == 13)
        #expect(RestyleBudget.provisionalCeiling(before: 0.1) == 1)
        #expect(RestyleBudget.provisionalCeiling(before: 4.2, factor: 2) == 9)
    }

    // (n2-page R-15) The bench script greps this exact shape.
    @Test func theLineHasTheSixFieldsTheBenchScriptGreps() {
        let c = RestyleBudget.Case(bytes: 51_200, variant: .fences)
        #expect(
            RestyleBudget.line(c, cpuMs: 12.345, wallMs: 15.5, runs: 5)
                == "restyle-budget size=51200 variant=fences cpu_ms=12.35 wall_ms=15.50 runs=5"
        )
        #expect(
            RestyleBudget.line(.init(bytes: 1_048_576, variant: .prose), cpuMs: 0.004, wallMs: 1, runs: 3)
                == "restyle-budget size=1048576 variant=prose cpu_ms=0.00 wall_ms=1.00 runs=3"
        )
    }

    // (n2-page R-15) Size within 1% of the target, in UTF-8 bytes, for every case.
    @Test(arguments: RestyleBudget.Variant.allCases)
    func theSyntheticNoteIsWithinOnePercentOfItsTarget(_ variant: RestyleBudget.Variant) {
        for bytes in RestyleBudget.sizes {
            let note = RestyleBudget.syntheticNote(bytes: bytes, variant: variant)
            let size = note.utf8.count
            #expect(abs(size - bytes) * 100 <= bytes, "\(variant) \(bytes): \(size)")
        }
    }

    // (n2-page R-15) No randomness: two calls, the same bytes.
    @Test(arguments: RestyleBudget.Variant.allCases)
    func theSyntheticNoteIsDeterministic(_ variant: RestyleBudget.Variant) {
        let first = RestyleBudget.syntheticNote(bytes: 50 * 1024, variant: variant)
        let second = RestyleBudget.syntheticNote(bytes: 50 * 1024, variant: variant)
        #expect(first == second)
    }

    // (n2-page R-15) The variants differ in exactly the fences, and the prose carries the constructs.
    @Test func theVariantsDifferInTheFencesAndBothCarryTheConstructs() {
        let prose = RestyleBudget.syntheticNote(bytes: 50 * 1024, variant: .prose)
        let fences = RestyleBudget.syntheticNote(bytes: 50 * 1024, variant: .fences)
        #expect(!prose.contains("```"))
        #expect(fences.contains("```swift"))
        #expect(fences.contains("```pergamenum-view"))
        for text in [prose, fences] {
            for construct in ["# Titolo", "**grassetto**", "*corsivo*", "[[Nota", "](https://", "#project-av", ">2026-",
                              "!2026-", "- [ ]", "  - annidato", "1. uno", "> citazione", "~~barrato~~"] {
                #expect(text.contains(construct), "\(construct)")
            }
        }
    }

    // (n2-page R-15) Six ceilings, one per size and variant, all positive.
    @Test func thereAreSixCeilings() {
        #expect(RestyleBudget.ceilings.count == 6)
        for size in RestyleBudget.sizes {
            for variant in RestyleBudget.Variant.allCases {
                let ceiling = RestyleBudget.ceilings[.init(bytes: size, variant: variant)]
                #expect((ceiling ?? 0) > 0, "\(size) \(variant)")
            }
        }
    }

    // (n2-page R-15) Thread CPU time moves forward with work and is not the wall clock.
    @Test func threadCPUTimeAdvancesWithWork() {
        let before = RestyleBudget.threadCPUNanoseconds()
        var sink = 0
        for index in 0..<2_000_000 { sink &+= index }
        let after = RestyleBudget.threadCPUNanoseconds()
        #expect(after > before)
        #expect(sink != 0)
    }

    @Test func minimumTakesOneWarmUpAndThenTheSmallestOfKRuns() {
        var calls = 0
        let result = RestyleBudget.minimum(runs: 4) { calls += 1 }
        #expect(calls == 5)
        #expect(result.cpuMs >= 0 && result.wallMs >= 0)
        #expect(result.cpuMs.isFinite && result.wallMs.isFinite)
    }

    // MARK: Hosted

    /// The end of the first paragraph line at or after the middle of the note: a place where one
    /// `x` changes no construct, and the same place on every run.
    private static func insertionPoint(in note: String) -> Int {
        let nsNote = note as NSString
        let middle = nsNote.length / 2
        let line = nsNote.range(
            of: "Altro testo con", options: [], range: NSRange(location: middle, length: nsNote.length - middle)
        )
        guard line.location != NSNotFound else { return middle }
        return nsNote.lineRange(for: line).upperBound - 1
    }

    // (n2-page R-15) The fixture is the app's own wiring: a keystroke restyles, and reaches the text.
    @Test func theFixtureTypesThroughTheCoordinator() {
        let note = RestyleBudget.syntheticNote(bytes: 50 * 1024, variant: .fences)
        let fixture = ScrolledEditorFixture(text: note)
        defer { fixture.window.orderOut(nil) }
        let at = Self.insertionPoint(in: note)
        let before = (fixture.textView.string as NSString).length

        fixture.type("x", at: at)

        #expect((fixture.textView.string as NSString).length == before + 1)
        #expect(fixture.textView.selectedRange() == NSRange(location: at + 1, length: 0))
        #expect(fixture.coordinator.decorations.hiddenMarkerCount > 0, "the styling pass ran and hid markers")
        #expect(fixture.textView.undoManager?.canUndo == true, "the keystroke is an undo step of its own")
    }

    // (n2-page R-15) One keystroke in the middle of every size and variant stays under its ceiling.
    @Test(arguments: RestyleBudget.activeCases)
    func aKeystrokeInTheMiddleStaysUnderItsCeiling(_ c: RestyleBudget.Case) throws {
        let started = DispatchTime.now().uptimeNanoseconds
        let note = RestyleBudget.syntheticNote(bytes: c.bytes, variant: c.variant)
        let fixture = ScrolledEditorFixture(text: note)
        defer { fixture.window.orderOut(nil) }
        let at = Self.insertionPoint(in: note)
        let runs = RestyleBudget.runs(for: c)
        // The frame the app has when a person types: as tall as the note, not the 700 pt the
        // fixture was built with, so no measured keystroke pays the open pass's growth (R-17).
        fixture.openLikeTheApp()

        let measured = RestyleBudget.minimum(runs: runs, warmUp: RestyleBudget.warmsUp) { fixture.type("x", at: at) }

        print(RestyleBudget.line(c, cpuMs: measured.cpuMs, wallMs: measured.wallMs, runs: runs))
        let total = String(format: "%.0f", Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
        print("restyle-budget-total size=\(c.bytes) variant=\(c.variant.rawValue) total_wall_ms=\(total)")
        let ceiling = try #require(RestyleBudget.ceilings[c])
        #expect(measured.cpuMs <= ceiling, "\(c): \(measured.cpuMs) ms of thread CPU against a ceiling of \(ceiling)")
    }
}
