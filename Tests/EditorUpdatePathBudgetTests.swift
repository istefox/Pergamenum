import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0096 (planned), plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 1 (PG-406, R-01).
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

    // Plan N5, Realignments 5 and 7 (ADR-0087 §D8 under ADR-0096 §D7): callouts above and below the middle
    // paragraph, one of each block folded. A keystroke that reaches none of them reads the note for none of
    // them and leaves the folded bodies hidden; a keystroke on a header is read, and its fold applied.
    @Test func aKeystrokeThatReachesNoCalloutReadsNothingForThem() async throws {
        let c = RestyleBudget.Case(bytes: 50 * 1024, variant: .prose)
        let callouts = "> [!faq]- Domanda\n> risposta nascosta\n> seconda riga\n\n"
            + "> [!note]+ Aperta\n> corpo aperto\n\n> [!tip] Fissa\n> corpo fisso\n\n"
        let synthetic = RestyleBudget.syntheticNote(bytes: c.bytes, variant: c.variant)
        let fixture = try await UpdatePathFixture(c, note: callouts + synthetic + "\n" + callouts)
        defer { fixture.tearDown() }
        let folding = fixture.coordinator.folding
        try #require(fixture.coordinator.decorations.foldsCallouts, "the column wires no callout toggle")

        // The first keystroke restyles in full, which reads the callouts once (the fixture's own test).
        fixture.keystroke()
        let readsBefore = folding.textReads
        for key in 1...3 {
            let before = fixture.coordinator.restyleLog
            fixture.keystroke()
            #expect(fixture.coordinator.restyleLog.full == before.full, "key \(key) restyled the note")
        }
        #expect(fixture.missedUpdates == 0)
        #expect(folding.textReads == readsBefore, "a keystroke that reached no callout read the note for them")
        let hidden = CalloutFold.hiddenLines(in: fixture.textView.string, toggled: [])
        #expect(hidden.count == 4, "the two folded callouts' bodies")
        #expect(folding.lastFoldLayout.hiddenLineOffsets == hidden, "the shifted fold is not the note's")

        // `-` typed after the first `[!tip]`: the header's line is restyled, so the callouts are read again.
        let header = (fixture.textView.string as NSString).range(of: "[!tip]")
        try #require(header.location != NSNotFound)
        fixture.type("-", at: NSMaxRange(header))
        #expect(folding.textReads > readsBefore, "a header edit did not read the callouts")
        let refolded = CalloutFold.hiddenLines(in: fixture.textView.string, toggled: [])
        #expect(refolded.count == 5, "the edited callout's body is not hidden")
        #expect(folding.lastFoldLayout.hiddenLineOffsets == refolded)
        #expect(fixture.missedUpdates == 0)
    }

    // The same note, typed in inside the callouts: a fixed callout's body and a folded one's title. The
    // restyle re-reads the quote run it typed in and the folds are spliced from it, so neither keystroke
    // reads the note whole for the callouts or the fold layout (PG-406, ADR-0096 §D7).
    @Test func aKeystrokeInsideACalloutReadsNothingWholeNote() async throws {
        let c = RestyleBudget.Case(bytes: 50 * 1024, variant: .prose)
        let callouts = "> [!faq]- Domanda\n> risposta nascosta\n> seconda riga\n\n"
            + "> [!note]+ Aperta\n> corpo aperto\n\n> [!tip] Fissa\n> corpo fisso\n\n"
        let synthetic = RestyleBudget.syntheticNote(bytes: c.bytes, variant: c.variant)
        let fixture = try await UpdatePathFixture(c, note: callouts + synthetic + "\n" + callouts)
        defer { fixture.tearDown() }
        let folding = fixture.coordinator.folding
        try #require(fixture.coordinator.decorations.foldsCallouts, "the column wires no callout toggle")

        // The first keystroke restyles in full, which reads the callouts once (the fixture's own test).
        fixture.keystroke()
        let readsBefore = folding.textReads
        for target in ["corpo fisso", "Domanda"] {
            let found = (fixture.textView.string as NSString).range(of: target)
            try #require(found.location != NSNotFound)
            for key in 0..<3 {
                let before = fixture.coordinator.restyleLog
                fixture.type("x", at: NSMaxRange(found) + key)
                let after = fixture.coordinator.restyleLog
                #expect(after.full == before.full, "\(target), key \(key): restyled the note")
                #expect(after.incremental == before.incremental + 1, "\(target), key \(key): \(before) then \(after)")
            }
        }
        #expect(fixture.missedUpdates == 0)
        #expect(folding.textReads == readsBefore, "a keystroke inside a callout read the note for the callouts")
        let hidden = CalloutFold.hiddenLines(in: fixture.textView.string, toggled: [])
        #expect(hidden.count == 4, "the two folded callouts' bodies")
        #expect(folding.lastFoldLayout.hiddenLineOffsets == hidden, "the spliced fold is not the note's")
    }

    // An edit that reaches a folded callout and takes the last `[!` out of the note, through a restyle of the
    // whole note (a wikilink token leaving the title line is what makes the scope decline an incremental
    // one). The callout is gone, so the layout it hid must be gone with it: a memo kept without that callout
    // would let the folding pass see nothing to recompute and leave its body lines hidden for good.
    @Test func removingTheLastCalloutHeaderFromAFoldedCalloutUnhidesItsBody() async throws {
        let note = "> [!faq]- Domanda [[altra]]\n> risposta nascosta\n> seconda riga\n\nTesto di chiusura.\n"
        let fixture = try await UpdatePathFixture(.init(bytes: note.utf8.count, variant: .prose), note: note)
        defer { fixture.tearDown() }
        let folding = fixture.coordinator.folding
        try #require(fixture.coordinator.decorations.foldsCallouts, "the column wires no callout toggle")
        let folded = CalloutFold.hiddenLines(in: fixture.textView.string, toggled: [])
        try #require(folded.count == 2, "the folded callout's two body lines")
        #expect(folding.lastFoldLayout.hiddenLineOffsets == folded, "the callout does not start folded")

        let title = (fixture.textView.string as NSString).range(of: "[!faq]- Domanda [[altra]]")
        try #require(title.location != NSNotFound)
        let before = fixture.coordinator.restyleLog
        fixture.type("", at: title.location, replacing: title.length)
        let after = fixture.coordinator.restyleLog
        #expect(after.full == before.full + 1, "the edit did not restyle the note: \(before) then \(after)")
        #expect(!fixture.textView.string.contains("[!"))

        let remaining = CalloutFold.hiddenLines(in: fixture.textView.string, toggled: [])
        #expect(remaining.isEmpty, "no callout is left to fold")
        #expect(folding.lastFoldLayout.hiddenLineOffsets == remaining, "the body of the callout stayed hidden")
        #expect(fixture.missedUpdates == 0)
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
