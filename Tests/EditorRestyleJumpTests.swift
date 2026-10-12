import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0094 §D1, plan docs/plans/sublinear-offset-state-pg-405.md, Task 1 (PG-405, R-06, R-11).
//
// The first keystroke after a caret jump, as a printed row: never asserted on time. The always-on tests
// assert the shape of the line the bench script greps and that the scenario really restyles by range at
// both places, so a printed row never measures a fallback. The measured rows run behind
// `RESTYLE_BUDGET_JUMP=1` (`scripts/editor-restyle-bench.sh --jump`).

@MainActor
@Suite(.serialized) struct EditorRestyleJumpTests {
    // The bench script greps this exact shape for its fourth table, and none of the other tables'
    // patterns may match it.
    @Test func theJumpLineHasTheSevenFieldsTheBenchScriptGreps() {
        let c = RestyleBudget.Case(bytes: 51_200, variant: .fences)
        let line = RestyleBudget.jumpLine(c, cpuMs: 4.1, wallMs: 5.2, crossed: 640, runs: 5)
        #expect(line == "restyle-budget-jump size=51200 variant=fences cpu_ms=4.10 wall_ms=5.20 crossed=640 runs=5")
        #expect(
            !line.hasPrefix("restyle-budget size=") && !line.hasPrefix("restyle-budget-fallback size=")
                && !line.hasPrefix("restyle-budget-structural size=")
        )
    }

    @Test(arguments: RestyleBudget.Variant.allCases)
    func theJumpPointIsNearTheTopAndAboveTheInsertionPoint(_ variant: RestyleBudget.Variant) {
        let note = RestyleBudget.syntheticNote(bytes: 50 * 1024, variant: variant)
        let ns = note as NSString
        let jump = RestyleBudget.jumpPoint(in: note)
        let middle = RestyleBudget.insertionPoint(in: note)

        #expect(jump < ns.length / 10, "\(variant): the jump point is not near the top")
        #expect(jump < middle, "\(variant): the jump point is not above the insertion point")
        for place in [jump, middle] {
            let line = ns.lineRange(for: NSRange(location: place, length: 0))
            #expect(
                ns.substring(with: line).hasPrefix("Altro testo con"), "\(variant): not on an `Altro testo con` line"
            )
            #expect(NSMaxRange(line) - 1 == place, "\(variant): not at the end of the line")
        }
    }

    // Each call is one ranged restyle at its place, and the middle paragraph ends with the characters
    // typed into it so far. Always on, at the size the per-turn suite can afford.
    @Test func theJumpScenarioTypesIncrementallyAtBothPlaces() {
        let scenario = JumpScenario(.init(bytes: 50 * 1024, variant: .fences))
        defer { scenario.fixture.window.orderOut(nil) }
        let coordinator = scenario.fixture.coordinator
        #expect(scenario.crossed > 0)

        for round in 1...3 {
            let beforeJump = coordinator.restyleLog
            scenario.jumpAway()
            let afterJump = coordinator.restyleLog
            #expect(
                afterJump.incremental == beforeJump.incremental + 1,
                "round \(round): jumpAway: \(beforeJump) then \(afterJump)"
            )
            #expect(
                afterJump.full == beforeJump.full,
                "round \(round): jumpAway restyled the note: \(beforeJump) then \(afterJump)"
            )

            scenario.keystroke()
            let afterKey = coordinator.restyleLog
            #expect(
                afterKey.incremental == afterJump.incremental + 1,
                "round \(round): keystroke: \(afterJump) then \(afterKey)"
            )
            #expect(
                afterKey.full == afterJump.full,
                "round \(round): keystroke restyled the note: \(afterJump) then \(afterKey)"
            )
        }

        let text = scenario.fixture.textView.string as NSString
        let line = text.lineRange(for: NSRange(location: scenario.middle - 1, length: 0))
        #expect(text.substring(with: line).hasSuffix("xxx\n"), "the middle paragraph lost a typed character")
        #expect(scenario.middle == NSMaxRange(line) - 1)
    }

    // One printed row per case: size, variant, the CPU and wall minima of the keystroke back at the
    // middle paragraph after a jump to the top, and the lines between. Opt-in with `RESTYLE_BUDGET_JUMP=1`.
    @Test(.enabled(if: RestyleBudget.includesJumpRows), arguments: RestyleBudget.activeCases)
    func aKeystrokeAfterACaretJumpIsPrinted(_ c: RestyleBudget.Case) {
        let scenario = JumpScenario(c)
        defer { scenario.fixture.window.orderOut(nil) }
        let runs = RestyleBudget.runs(for: c)

        let measured = RestyleBudget.minimum(
            runs: runs, warmUp: RestyleBudget.warmsUp, prepare: { scenario.jumpAway() }
        ) { scenario.keystroke() }

        print(RestyleBudget.jumpLine(
            c, cpuMs: measured.cpuMs, wallMs: measured.wallMs, crossed: scenario.crossed, runs: runs
        ))
    }
}
