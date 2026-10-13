import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0096 §D5 to §D10, plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 4 (PG-406,
// R-02, R-04, R-05, R-06, R-07).
//
// Counters, not clocks: a keystroke through SwiftUI's update (`UpdatePathFixture` hosts the real
// `EditorColumnView` and makes the update run) must compare no text, parse no outline and run no find while
// the bar is closed. Each counter is a seam the red phase declares and leaves at zero; the assertions that
// read "moved by N" are red until Task 5 moves them. The first keystroke after the note opens restyles in
// full (`EditorUpdatePathBudgetTests`), so every test types one before it measures.
//
// The cases are `RestyleBudget.activeCases`: the two 50 KB cases by default, and the 200 KB and 1 MB ones
// when the bench switches are set.

/// What a test reads before and after a keystroke.
@MainActor
private struct Counters {
    var compares: Int
    var rebuilds: Int
    var splices: Int
    var shifts: Int
    var findUpdates: Int
    var markChecks: Int
    var skipped: Int
    var full: Int
    var incremental: Int

    init(_ fixture: UpdatePathFixture, store: OutlineStore) {
        compares = fixture.coordinator.modelSync.compares
        rebuilds = store.tally.rebuilds
        splices = store.tally.splices
        shifts = store.tally.shifts
        findUpdates = fixture.find.updates
        markChecks = fixture.vault.unsavedMarkChecks
        skipped = fixture.coordinator.restyleLog.skipped
        full = fixture.coordinator.restyleLog.full
        incremental = fixture.coordinator.restyleLog.incremental
    }
}

@MainActor
private func columnStore(of fixture: UpdatePathFixture) -> OutlineStore {
    fixture.vault.outlineStore(forColumn: fixture.vault.columns[0].id)
}

@MainActor
@Suite(.serialized) struct UpdatePathCounters {
    // (R-02, R-04) Five plain keystrokes: nothing compared, the outline spliced once per key and never
    // rebuilt, no find update, no unsaved-mark check; SwiftUI's update ran for each; the mark is on and
    // the pause waits to fire.
    @Test(arguments: RestyleBudget.activeCases)
    func aPlainKeystrokeComparesNoTextAndParsesNoOutline(_ c: RestyleBudget.Case) async throws {
        let fixture = try await UpdatePathFixture(c)
        defer { fixture.tearDown() }
        let pause = try #require(fixture.typingPause as? ManualPauseScheduler)
        let store = columnStore(of: fixture)

        fixture.keystroke()
        let before = Counters(fixture, store: store)
        let restartsBefore = pause.restarts
        for _ in 0..<5 { fixture.keystroke() }
        let after = Counters(fixture, store: store)

        #expect(fixture.missedUpdates == 0, "SwiftUI's update did not run after \(fixture.missedUpdates) keystrokes")
        #expect(after.skipped - before.skipped == 5, "restyleLog.skipped should move by 1 per key")
        #expect(after.full == before.full, "a plain keystroke restyled the note")
        #expect(after.compares - before.compares == 0, "the update compared the whole text")
        #expect(after.rebuilds - before.rebuilds == 0, "the outline store was rebuilt")
        #expect(after.splices - before.splices == 5, "the outline store should splice once per key")
        #expect(after.findUpdates - before.findUpdates == 0, "the closed find bar ran")
        #expect(after.markChecks - before.markChecks == 0, "an exact unsaved check ran while typing")
        #expect(fixture.vault.openNote?.hasUnsavedChanges == true)
        #expect(pause.isPending, "the pause is waiting to settle the mark")
        #expect(pause.restarts - restartsBefore == 5, "each key restarts the pause")
    }

    // (R-02) The keystroke that opens a fence is the one case the store rebuilds for, and it does so once.
    @Test(arguments: RestyleBudget.activeCases)
    func aFenceKeystrokeRebuildsTheStoreOnce(_ c: RestyleBudget.Case) async throws {
        let fixture = try await UpdatePathFixture(c)
        defer { fixture.tearDown() }
        let store = columnStore(of: fixture)
        let note = try #require(fixture.vault.openNote?.text)

        // `RestyleBudget`'s fallback shape: a line holding two backticks, then the third typed at its start.
        let at = fixture.location
        fixture.type("\n\n``", at: at)
        let before = Counters(fixture, store: store)
        fixture.type("`", at: at + 2)
        let after = Counters(fixture, store: store)

        #expect(after.full - before.full >= 1, "the keystroke did not restyle in full, so it is not a fence opening")
        #expect(after.incremental == before.incremental, "a ranged restyle ran for a fence opening")
        #expect(after.rebuilds - before.rebuilds == 1, "the store should rebuild exactly once for a fence opening")
        #expect(after.compares - before.compares == 0)
        let text = try #require(fixture.vault.openNote?.text)
        #expect(text != note)
        #expect(store.map.items == OutlineOracle.items(text), "the rebuilt store is not the parse of the note")
    }

    // (R-02) ADR-0094 §D9's meaning, kept: a model replaced from outside is found by the one compare the
    // update still makes, and the view takes the new text.
    @Test(arguments: RestyleBudget.activeCases)
    func aModelReplacedFromOutsideCountsOneCompare(_ c: RestyleBudget.Case) async throws {
        let fixture = try await UpdatePathFixture(c)
        defer { fixture.tearDown() }
        let store = columnStore(of: fixture)
        fixture.keystroke()
        fixture.keystroke()
        let current = try #require(fixture.vault.openNote?.text)
        let other = "# Rimpiazzata da fuori\n\n" + current

        let before = Counters(fixture, store: store)
        fixture.vault.updateOpenNoteText(other)
        await fixture.host.settle()
        let after = Counters(fixture, store: store)

        #expect(after.compares - before.compares == 1, "the replaced model should cost exactly one compare")
        #expect(fixture.textView.string == other, "the view did not take the replaced text")
        #expect(fixture.vault.openNote?.text == other)
    }

    // (R-05) With the bar open the find keeps its linear recompute: one update per keystroke, and the
    // matches are what `NoteFind.run` finds in the model's text.
    @Test(arguments: RestyleBudget.activeCases)
    func withTheBarOpenEachKeystrokeRecomputesTheMatches(_ c: RestyleBudget.Case) async throws {
        let find = FindSession()
        let fixture = try await UpdatePathFixture(c, find: find)
        defer { fixture.tearDown() }
        let store = columnStore(of: fixture)
        let text = try #require(fixture.vault.openNote?.text)

        find.open(replacing: false, over: nil, in: text)
        find.query = "Altro testo con"
        find.update(in: text)
        #expect(find.isOpen)
        #expect(!find.matches.isEmpty, "the note holds the query, so the bar has matches")

        fixture.keystroke()
        for key in 1...3 {
            let before = Counters(fixture, store: store)
            fixture.keystroke()
            let after = Counters(fixture, store: store)
            let model = try #require(fixture.vault.openNote?.text)
            #expect(after.findUpdates - before.findUpdates == 1, "key \(key): the open bar should update once")
            #expect(
                find.matches == NoteFind.run(find.currentQuery, in: model, within: find.scope).ranges,
                "key \(key): the matches are not a fresh search of the model's text"
            )
        }
    }

    // (R-06) The column's store is the parse of the note after each keystroke.
    @Test(arguments: RestyleBudget.activeCases)
    func theStoreEqualsTheParseAfterEachKeystroke(_ c: RestyleBudget.Case) async throws {
        let fixture = try await UpdatePathFixture(c)
        defer { fixture.tearDown() }
        let store = columnStore(of: fixture)
        fixture.keystroke()
        let initial = OutlineOracle.items(try #require(fixture.vault.openNote?.text))
        #expect(!initial.isEmpty)
        for key in 1...5 {
            fixture.keystroke()
            let text = try #require(fixture.vault.openNote?.text)
            #expect(store.map.items == OutlineOracle.items(text), "key \(key)")
        }
        #expect(store.rows == OutlineOracle.rows(try #require(fixture.vault.openNote?.text)))
    }

    // (R-07) Typing `# ` at the start of a paragraph makes a heading, and the entry the caret is in is
    // reported without a further caret move: the store answers after the splice, not before it.
    @Test(arguments: RestyleBudget.activeCases)
    func theCaretEntryIsReportedAfterAKeystrokeThatMakesAHeading(_ c: RestyleBudget.Case) async throws {
        let fixture = try await UpdatePathFixture(c)
        defer { fixture.tearDown() }
        fixture.keystroke()
        let reportedBefore = fixture.vault.currentOutlineEntry

        let note = try #require(fixture.vault.openNote?.text) as NSString
        let line = note.range(of: "Altro testo con").location
        try #require(line != NSNotFound)
        // `# ` in one insertion, as a paste or a text replacement makes it. Typed as two keys, the `#`
        // alone makes `#Altro`, a tag, and opens the tag completion panel on screen over the hosted
        // window (R-15; the fixture now fails a keystroke that opens it). The heading, the splice and the
        // caret's position after it are the same either way.
        fixture.type("# ", at: line)

        let text = try #require(fixture.vault.openNote?.text)
        let caret = fixture.textView.selectedRange().location
        let entries = OutlineOracle.items(text)
        let expected = entries.lastIndex { $0.range.location <= caret }
        let index = try #require(expected, "the caret is in no entry")
        #expect(entries[index].title.hasPrefix("Altro testo con"), "the new heading is not the caret's entry")
        #expect(
            fixture.vault.currentOutlineEntry == expected,
            "reported \(String(describing: fixture.vault.currentOutlineEntry)), the caret is in entry \(String(describing: expected))"
        )
        #expect(fixture.vault.currentOutlineEntry != reportedBefore)
    }
}

// MARK: - The seams on their own

@MainActor
@Suite struct UpdatePathSeams {
    @Test func modelSyncCountsEachCompareItIsToldAbout() {
        var sync = ModelSync()
        #expect(sync.compares == 0)
        sync.countCompare()
        sync.countCompare()
        #expect(sync.compares == 2)
        // The count is a tally: it does not change what the record answers.
        sync.wrote("a")
        #expect(sync.viewHolds("a"))
        #expect(sync.compares == 2)
    }

    @Test func aClosedFindBarCountsNothingAndAnOpenOneCountsEachUpdate() {
        let find = FindSession()
        find.query = "uno"
        find.update(in: "uno due uno")
        find.update(in: "uno due uno tre")
        #expect(find.updates == 0, "a closed bar ran")

        find.open(replacing: false, over: nil, in: "uno due uno")
        let afterOpen = find.updates
        #expect(afterOpen == 1, "opening updates once")
        find.update(in: "uno due uno")
        find.update(in: "uno due uno tre")
        #expect(find.updates == afterOpen + 2)
        #expect(find.matches.count == 2)

        find.close()
        find.update(in: "uno")
        #expect(find.updates == afterOpen + 2, "a closed bar ran again")
    }
}
