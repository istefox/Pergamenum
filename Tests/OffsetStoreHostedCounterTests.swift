import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0094 §D5 and §D6, plan docs/plans/sublinear-offset-state-pg-405.md, Task 4 (PG-405, R-05, R-06,
// R-07, R-09).
//
// The touched-entries counter on the real editor: what one keystroke costs each store the coordinator and
// the structure map keep, read from the tallies the stores carry. Every test is skipped where the counting
// is compiled out (a Release test bundle). One rule for all of them: no snapshot, map or store binding
// stays alive across a measured keystroke, because it shares the storage and `copies` would count it. What
// a test needs of one is taken into plain integers inside a `do { }` block first.
//
// The cases are 50 KB in both variants always, 200 KB when `RESTYLE_BUDGET_200KB=1` and 1 MB when
// `RESTYLE_BUDGET_1MB` is `1` or `only` (`scripts/editor-restyle-bench.sh` sets them). Each prints one
// `offset-store-counter` line per store, which the bench script collects into a table.

extension RestyleBudget {
    /// The cases the counter tests run: 50 KB always, 200 KB and 1 MB where the bench asks for them.
    static var counterCases: [Case] {
        ceilings.keys
            .filter { c in
                if c.bytes >= 1024 * kilobyte { return includesLargeNotes }
                if c.bytes >= 200 * kilobyte { return includesMediumNotes }
                return true
            }
            .sorted { ($0.bytes, $0.variant.rawValue) < ($1.bytes, $1.variant.rawValue) }
    }
}

/// The two groups of stores the counters read: the three the coordinator and the delegate keep, and the
/// seven the structure map keeps (ADR-0094 §D6).
enum CounterGroup: String, CaseIterable, Sendable {
    case stores, map

    var keys: [String] {
        switch self {
        case .stores:
            ["hiddenMarkers", "unspellable", "embedRuns"]
        case .map:
            [
                "map.lines", "map.fences", "map.tableRuns", "map.viewBlockRuns", "map.oddFenceLines",
                "map.bracketLines", "map.closingLines",
            ]
        }
    }
}

@MainActor
@Suite(.serialized) struct OffsetStoreHostedCounterTests {
    /// The constant of ADR-0094 §D5: entries per store per keystroke, the shift and the splice together.
    static let constant = 64

    private func editor(for c: RestyleBudget.Case) -> (fixture: ScrolledEditorFixture, note: String) {
        let note = RestyleBudget.syntheticNote(bytes: c.bytes, variant: c.variant)
        let fixture = ScrolledEditorFixture(text: note)
        fixture.openLikeTheApp()
        return (fixture, note)
    }

    private func report(_ c: RestyleBudget.Case, _ key: String, _ tally: StepTally) {
        Swift.print(
            "offset-store-counter size=\(c.bytes) variant=\(c.variant.rawValue) store=\(key) "
                + "touched=\(tally.touched) copies=\(tally.copies)"
        )
    }

    /// Whether `range` intersects `span` as `OffsetRanges.indices(intersecting:)` reads it.
    private static func intersects(_ range: NSRange, _ span: NSRange) -> Bool {
        range.location < NSMaxRange(span) && NSMaxRange(range) > span.location
    }

    // MARK: R-05

    // (R-05) A keystroke at the place of the previous one: each of the three stores shifted and spliced,
    // touched a handful of entries and copied nothing, and the restyle was a ranged one.
    @Test(.enabled(if: StepTally.isCounting), arguments: RestyleBudget.counterCases)
    func theThreeStoresStayLocal(_ c: RestyleBudget.Case) throws {
        let (fixture, note) = editor(for: c)
        defer { fixture.window.orderOut(nil) }
        let at = RestyleBudget.insertionPoint(in: note)
        fixture.type("x", at: at)
        fixture.coordinator.resetOffsetStoreTallies()
        let before = fixture.coordinator.restyleLog

        fixture.type("x", at: at + 1)

        let after = fixture.coordinator.restyleLog
        let tallies = fixture.coordinator.offsetStoreTallies()
        for key in CounterGroup.stores.keys {
            let tally = try #require(tallies[key], "\(c): no tally for \(key)")
            report(c, key, tally)
            #expect(tally.shifts >= 1, "\(c) \(key): \(tally)")
            #expect(tally.splices >= 1, "\(c) \(key): \(tally)")
            #expect(tally.touched <= Self.constant, "\(c) \(key): \(tally)")
            #expect(tally.copies == 0, "\(c) \(key): \(tally)")
        }
        #expect(after.incremental == before.incremental + 1, "\(c): \(before) then \(after)")
        #expect(after.full == before.full, "\(c): \(before) then \(after)")
    }

    // MARK: R-07

    // (R-07) The same keystrokes, and the same assertions, for the seven stores of the structure map.
    @Test(.enabled(if: StepTally.isCounting), arguments: RestyleBudget.counterCases)
    func theMapStaysLocal(_ c: RestyleBudget.Case) throws {
        let (fixture, note) = editor(for: c)
        defer { fixture.window.orderOut(nil) }
        let at = RestyleBudget.insertionPoint(in: note)
        fixture.type("x", at: at)
        // ADR-0094 §D6 leaves `codeBlocks` an array on the assumption that neither bench variant has any.
        let codeBlocksAreEmpty = fixture.coordinator.derivedStateSnapshot().map?.codeBlocks.isEmpty
        #expect(codeBlocksAreEmpty == true, "\(c): the bench note holds a code block the fence list does not")
        fixture.coordinator.resetOffsetStoreTallies()
        let before = fixture.coordinator.restyleLog

        fixture.type("x", at: at + 1)

        let after = fixture.coordinator.restyleLog
        let tallies = fixture.coordinator.offsetStoreTallies()
        for key in CounterGroup.map.keys {
            let tally = try #require(tallies[key], "\(c): no tally for \(key)")
            report(c, key, tally)
            #expect(tally.shifts >= 1, "\(c) \(key): \(tally)")
            #expect(tally.splices >= 1, "\(c) \(key): \(tally)")
            #expect(tally.touched <= Self.constant, "\(c) \(key): \(tally)")
            #expect(tally.copies == 0, "\(c) \(key): \(tally)")
        }
        #expect(after.incremental == before.incremental + 1, "\(c): \(before) then \(after)")
        #expect(after.full == before.full, "\(c): \(before) then \(after)")
    }

    // MARK: R-06

    /// How many entries of each key lie between the two places, counted with `filter` and `count` on what the
    /// snapshot holds, so that this compiles against today's arrays and tomorrow's buffers.
    private func entriesBetween(
        in group: CounterGroup, span: NSRange, of fixture: ScrolledEditorFixture
    ) -> [String: Int] {
        let snapshot = fixture.coordinator.derivedStateSnapshot()
        switch group {
        case .stores:
            return [
                "hiddenMarkers": snapshot.decorations.hiddenMarkerKeys.filter { NSLocationInRange($0, span) }.count,
                "unspellable": snapshot.unspellable.filter { Self.intersects($0, span) }.count,
                "embedRuns": snapshot.embedRuns.filter { Self.intersects($0, span) }.count,
            ]
        case .map:
            guard let map = snapshot.map else { return [:] }
            let starting = map.lines.filter { NSLocationInRange($0.start, span) }
            return [
                "map.lines": starting.count,
                "map.fences": map.fences.filter { Self.intersects($0.range, span) }.count,
                "map.tableRuns": map.tableRuns.filter { Self.intersects($0, span) }.count,
                "map.viewBlockRuns": map.viewBlockRuns.filter { Self.intersects($0, span) }.count,
                "map.oddFenceLines": starting.filter { $0.listFacts.fenceDelimiters % 2 == 1 }.count,
                "map.bracketLines": starting.filter { !$0.signature.brackets.isEmpty }.count,
                "map.closingLines": starting.filter { $0.signature.brackets.contains(.close) }.count,
            ]
        }
    }

    // (R-06) The first keystroke after a jump from the top of the note to the middle: each store touches no
    // more than the entries between the two places, plus the constant.
    @Test(.enabled(if: StepTally.isCounting), arguments: RestyleBudget.counterCases, CounterGroup.allCases)
    func aJumpCrossesOnce(_ c: RestyleBudget.Case, _ group: CounterGroup) throws {
        let (fixture, note) = editor(for: c)
        defer { fixture.window.orderOut(nil) }
        let jump = RestyleBudget.jumpPoint(in: note)
        let middle = RestyleBudget.insertionPoint(in: note)
        fixture.type("x", at: jump)
        let between = entriesBetween(in: group, span: NSRange(location: jump, length: middle + 1 - jump), of: fixture)
        fixture.coordinator.resetOffsetStoreTallies()

        fixture.type("x", at: middle + 1)

        let tallies = fixture.coordinator.offsetStoreTallies()
        for key in group.keys {
            let tally = try #require(tallies[key], "\(c): no tally for \(key)")
            let crossed = try #require(between[key], "\(c): the snapshot holds nothing to count \(key) against")
            #expect(tally.touched <= crossed + Self.constant, "\(c) \(key): \(tally), crossed \(crossed)")
            #expect(tally.copies == 0, "\(c) \(key): \(tally)")
        }
    }

    // MARK: R-09

    // (R-09) With the full-restyle switch on, no store shifts or splices, and there is no scope to count in.
    @Test(.enabled(if: StepTally.isCounting))
    func theKillSwitchShiftsNothing() throws {
        let c = RestyleBudget.Case(bytes: 50 * RestyleBudget.kilobyte, variant: .fences)
        let note = RestyleBudget.syntheticNote(bytes: c.bytes, variant: c.variant)
        let fixture = ScrolledEditorFixture(text: note, forcesFullRestyle: true)
        defer { fixture.window.orderOut(nil) }
        fixture.openLikeTheApp()
        let at = RestyleBudget.insertionPoint(in: note)
        fixture.coordinator.resetOffsetStoreTallies()
        let before = fixture.coordinator.restyleLog

        fixture.type("x", at: at)
        fixture.type("x", at: at + 1)

        let after = fixture.coordinator.restyleLog
        let tallies = fixture.coordinator.offsetStoreTallies()
        for key in CounterGroup.stores.keys {
            let tally = try #require(tallies[key], "no tally for \(key)")
            #expect(tally.shifts == 0, "\(key): \(tally)")
            #expect(tally.splices == 0, "\(key): \(tally)")
        }
        #expect(tallies.keys.allSatisfy { !$0.hasPrefix("map.") }, "\(tallies.keys.sorted())")
        #expect(after.full == before.full + 2, "\(before) then \(after)")
    }
}
