import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0095 (planned), plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 1 (PG-406, R-01).
//
// A keystroke through SwiftUI's update, as a printed row: never asserted on time until G-ceiling-406. The
// always-on tests assert the shape of the line the bench script greps and that the fixture really makes
// SwiftUI run its update after every key, so a printed row never measures a keystroke that skipped it.
// The measured rows run behind `RESTYLE_BUDGET_UPDATE=1` (`scripts/editor-restyle-bench.sh --update`).

@MainActor
@Suite(.serialized) struct EditorUpdatePathBudgetTests {
    // The bench script greps this exact shape for its fifth table, and none of the other tables'
    // patterns may match it.
    @Test func theUpdateLineHasTheSixFieldsTheBenchScriptGreps() {
        let c = RestyleBudget.Case(bytes: 51_200, variant: .fences)
        let line = RestyleBudget.updateLine(c, cpuMs: 4.1, wallMs: 5.2, runs: 5)
        #expect(line == "restyle-budget-update size=51200 variant=fences cpu_ms=4.10 wall_ms=5.20 runs=5")
        #expect(
            !line.hasPrefix("restyle-budget size=") && !line.hasPrefix("restyle-budget-fallback size=")
                && !line.hasPrefix("restyle-budget-structural size=") && !line.hasPrefix("restyle-budget-jump size=")
        )
    }

    // Each key is one incremental restyle (textDidChange) and one skipped one (updateNSView's passes), never
    // a full one, and the model ends the middle paragraph with the characters typed so far.
    @Test func theFixtureRunsSwiftUIsUpdateAfterEveryKeystroke() async throws {
        let fixture = try await UpdatePathFixture(.init(bytes: 50 * 1024, variant: .fences))
        defer { fixture.tearDown() }
        #expect(fixture.host.neverShown)
        #expect(fixture.host.refusals.isEmpty)

        // The first keystroke after the note opens restyles in full (measured 2026-10-13: full 1 -> 2, no
        // incremental one) and the bench's own warm-up absorbs it; the three keys below are the steady state.
        fixture.keystroke()
        print("update-path-first-key \(fixture.coordinator.restyleLog)")

        for key in 1...3 {
            let before = fixture.coordinator.restyleLog
            fixture.keystroke()
            let after = fixture.coordinator.restyleLog
            #expect(after.incremental == before.incremental + 1, "key \(key): \(before) then \(after)")
            #expect(
                after.skipped == before.skipped + 1, "key \(key): SwiftUI's update did not run: \(before) then \(after)"
            )
            #expect(after.full == before.full, "key \(key): restyled the note: \(before) then \(after)")
        }
        #expect(fixture.missedUpdates == 0)
        print("update-path-forcing layout=\(fixture.forcedByLayout) runloop=\(fixture.forcedByRunLoop)")

        let text = try #require(fixture.vault.openNote?.text) as NSString
        let end = RestyleBudget.insertionPoint(in: text as String)
        let line = text.lineRange(for: NSRange(location: end - 1, length: 0))
        #expect(text.substring(with: line).hasSuffix("xxxx\n"), "the middle paragraph lost a typed character")
        #expect(fixture.vault.openNote?.text == fixture.textView.string)
        #expect(fixture.host.neverShown)
        #expect(fixture.host.refusals.isEmpty)
    }

    // One printed row per case: size, variant, the CPU and wall minima of a keystroke through SwiftUI's
    // update. Opt-in with `RESTYLE_BUDGET_UPDATE=1`.
    @Test(.enabled(if: RestyleBudget.includesUpdateRows), arguments: RestyleBudget.activeCases)
    func aKeystrokeThroughSwiftUIsUpdateIsPrinted(_ c: RestyleBudget.Case) async throws {
        let fixture = try await UpdatePathFixture(c)
        defer { fixture.tearDown() }
        let runs = RestyleBudget.runs(for: c)

        let measured = RestyleBudget.minimum(runs: runs, warmUp: RestyleBudget.warmsUp) { fixture.keystroke() }

        #expect(fixture.missedUpdates == 0, "SwiftUI's update did not run after \(fixture.missedUpdates) keystrokes")
        print(RestyleBudget.updateLine(c, cpuMs: measured.cpuMs, wallMs: measured.wallMs, runs: runs))
        print(
            "update-path-forcing size=\(c.bytes) variant=\(c.variant.rawValue) "
                + "layout=\(fixture.forcedByLayout) runloop=\(fixture.forcedByRunLoop)"
        )
    }
}
