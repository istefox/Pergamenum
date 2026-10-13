import Foundation
import Testing
@testable import Pergamenum

// ADR-0096 §D6 and §D7, plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 4 (PG-406,
// R-06, R-07).
//
// The store is the observable half of the outline: the map that moves with the edits, the rows the sidebar
// reads, a generation that moves when the rows do, the revision the map was last stamped with, and the
// tally the counter tests read. The rows are compared with the parse (`OutlineOracle.rows`), never with a
// hand-written list. Red until Task 5: the red-phase store never changes.

private let noteWithSections = "intro\n# Uno\ncorpo uno\n## Due\ncorpo due\n![[foto.png]]\n# Tre\n"

/// One edit performed on a store the way the coordinator performs it, and on the text beside it.
@MainActor
private struct StoreRun {
    private(set) var text: String
    private(set) var scope: RestyleScope
    let store: OutlineStore

    init(text: String) {
        self.text = text
        scope = RestyleScope(text: text)
        store = OutlineStore(text: text)
    }

    /// Replaces `range` with `replacement`: shift the store, take the scope's decision, splice or rebuild.
    mutating func edit(_ replacement: String, over range: NSRange) {
        let new = (text as NSString).replacingCharacters(in: range, with: replacement)
        let length = (replacement as NSString).length
        let storage = StorageEdit(
            range: NSRange(location: range.location, length: length), delta: length - range.length
        )
        scope.record(storage, in: new as NSString)
        store.apply(storage)
        text = new
        switch scope.take() {
        case .lines(let dirty)?:
            scope.absorb(StructureMap(text: (new as NSString).substring(with: dirty)), at: dirty.location, replacing: dirty)
            store.splice(new as NSString, in: dirty, fences: scope.map.fences)
        case .full?:
            store.rebuild(text: new)
            scope = RestyleScope(text: new)
        case nil:
            break
        }
    }

    /// An edit at the first occurrence of `anchor`, `offset` units into it.
    mutating func type(_ replacement: String, at anchor: String, offset: Int = 0, deleting: Int = 0) {
        let location = (text as NSString).range(of: anchor).location + offset
        edit(replacement, over: NSRange(location: location, length: deleting))
    }
}

@MainActor
@Suite struct OutlineStoreRows {
    @Test func theRowsAreTheParsesRowsFromTheStart() {
        let store = OutlineStore(text: noteWithSections)
        let expected = OutlineOracle.rows(noteWithSections)
        #expect(expected.count == 4)
        #expect(store.rows == expected)
        #expect(store.map == OutlineMap(text: noteWithSections))
    }

    @Test func aNewStoreIsEmptyAndDescribesNothing() {
        let store = OutlineStore()
        #expect(store.rows.isEmpty)
        #expect(store.describes == nil)
        #expect(store.tally == OutlineTally(rebuilds: 0, splices: 0, shifts: 0))
        store.rebuild(text: noteWithSections)
        #expect(store.rows == OutlineOracle.rows(noteWithSections))
    }

    @Test func theRowsFollowEveryEditOfARandomSequence() {
        var pooledSteps = 0
        var pooledWithRows = 0
        for seed: UInt64 in [1, 2, 3, 5, 8] {
            var run = StoreRun(text: noteWithSections)
            var generator = EditGenerator(
                seed: seed &+ 400,
                atoms: EditGenerator.structuralAtoms + ["#", "\n"],
                tokens: EditGenerator.structuralTokens + ["# ", "## ", "```\n", "![[a.png]]\n"]
            )
            var steps = 0
            var withRows = 0
            for step in 0..<60 {
                let edit = generator.next(for: run.text)
                run.edit(edit.replacement, over: edit.range)
                steps += 1
                let expected = OutlineOracle.rows(run.text)
                if !expected.isEmpty { withRows += 1 }
                #expect(run.store.rows == expected, "seed \(seed) step \(step): \(run.text.debugDescription)")
                #expect(run.store.map.items == OutlineOracle.items(run.text), "seed \(seed) step \(step)")
            }
            // Restated non-vacuity floor (Task 6, R-09). The equality checks above are untouched. The
            // red-phase floor was "half of the steps of EACH seed hold a row"; the measured distribution
            // (seeds are fixed, so these are exact, not statistical) is rows in 36, 59, 60, 30 and 28 of 60
            // steps for seeds 1, 2, 3, 5, 8, i.e. 47% for seed 8. A seed that opens a fence early parks the
            // rest of its run inside it (every heading below is skipped), which is the structural case the
            // generator is there to produce, so a per-seed 50% asks the generator to avoid what the test
            // wants. The floor keeps its meaning at the right grain: every seed still reaches a non-empty
            // outline in at least a quarter of its steps, and pooled over the five seeds at least half
            // of the 300 steps compare a non-empty outline (measured 213, 71%).
            #expect(withRows * 4 >= steps, "seed \(seed): fewer than a quarter of the steps held a row (\(withRows) of \(steps))")
            pooledSteps += steps
            pooledWithRows += withRows
        }
        #expect(pooledWithRows * 2 >= pooledSteps, "most steps held no row (\(pooledWithRows) of \(pooledSteps))")
    }

    @Test func theGenerationMovesExactlyWhenTheRowsDo() {
        var run = StoreRun(text: noteWithSections)
        var generator = EditGenerator(
            seed: 77, atoms: EditGenerator.structuralAtoms + ["#", "\n"], tokens: EditGenerator.structuralTokens + ["# ", "![[a.png]]\n"]
        )
        var moved = 0
        var stayed = 0
        for step in 0..<150 {
            let rowsBefore = run.store.rows
            let generationBefore = run.store.generation
            let edit = generator.next(for: run.text)
            run.edit(edit.replacement, over: edit.range)
            if run.store.rows != rowsBefore {
                moved += 1
                #expect(run.store.generation > generationBefore, "step \(step): the rows changed and the generation did not")
            } else {
                stayed += 1
                #expect(run.store.generation == generationBefore, "step \(step): the generation moved for equal rows")
            }
        }
        #expect(moved > 0, "no edit changed the rows")
        #expect(stayed > 0, "every edit changed the rows")
    }

    @Test func typingInsideAParagraphLeavesTheGenerationAlone() {
        var run = StoreRun(text: noteWithSections)
        let generation = run.store.generation
        let rows = run.store.rows
        #expect(!rows.isEmpty)
        for _ in 0..<5 { run.type("x", at: "corpo uno", offset: 9) }
        #expect(run.store.rows == rows)
        #expect(run.store.generation == generation)
        // Typing in the heading's own title changes its row, so the generation moves.
        run.type("x", at: "Uno", offset: 1)
        #expect(run.store.rows.map(\.title).contains("Uxno"))
        #expect(run.store.generation > generation)
    }

    @Test func aHeadingTypedAboveMovesTheRowsBelowWithoutRebuilding() {
        var run = StoreRun(text: noteWithSections)
        let before = run.store.tally
        run.type("# Nuovo\n", at: "intro\n", offset: 6)
        #expect(run.store.rows.map(\.title) == ["Nuovo", "Uno", "Due", "foto.png", "Tre"])
        #expect(run.store.rows == OutlineOracle.rows(run.text))
        #expect(run.store.tally.rebuilds == before.rebuilds, "a line-local edit rebuilt the store")
    }
}

@MainActor
@Suite struct OutlineStoreTally {
    @Test func theTallyCountsOneShiftPerApplyOneSplicePerSpliceAndOneRebuildPerRebuild() {
        let store = OutlineStore(text: noteWithSections)
        let start = store.tally

        let text = "intro\n# Uno\ncorpo uno x\n## Due\ncorpo due\n![[foto.png]]\n# Tre\n"
        let edit = StorageEdit(range: NSRange(location: 21, length: 2), delta: 2)
        store.apply(edit)
        #expect(store.tally == OutlineTally(rebuilds: start.rebuilds, splices: start.splices, shifts: start.shifts + 1))

        let dirty = NSRange(location: 12, length: 12)
        store.splice(text as NSString, in: dirty, fences: StructureMap(text: text).fences)
        #expect(store.tally == OutlineTally(rebuilds: start.rebuilds, splices: start.splices + 1, shifts: start.shifts + 1))

        store.rebuild(text: text)
        #expect(store.tally == OutlineTally(rebuilds: start.rebuilds + 1, splices: start.splices + 1, shifts: start.shifts + 1))

        store.apply(edit)
        store.apply(edit)
        #expect(store.tally.shifts == start.shifts + 3)
    }
}

@MainActor
@Suite struct OutlineStoreRevision {
    @Test func stampingRecordsTheRevisionTheMapDescribes() {
        let store = OutlineStore(text: noteWithSections)
        let revision = TextRevision.next()
        store.stamp(revision)
        #expect(store.describes == revision)
        store.stamp(nil)
        #expect(store.describes == nil)
    }

    @Test func aStampedStoreAnswersItsOwnRowsAndNamesItself() {
        let store = OutlineStore(text: noteWithSections)
        let revision = TextRevision.next()
        store.stamp(revision)

        // The text passed in is ignored while the stamp matches: it is the store that is asked.
        let answer = store.rows(describing: revision, text: "something else\n")
        #expect(answer.rows == store.rows)
        #expect(!answer.rows.isEmpty)
        #expect(answer.source == .store(ObjectIdentifier(store), generation: store.generation))
    }

    @Test func aStoreThatDescribesAnotherRevisionParsesTheTextItWasGiven() {
        let store = OutlineStore(text: noteWithSections)
        store.stamp(TextRevision.next())
        let asked = TextRevision.next()
        let text = "# Altro\ncorpo\n## Ancora\nfine\n"

        let rowsBefore = store.rows
        let generationBefore = store.generation
        let describesBefore = store.describes
        let tallyBefore = store.tally

        let answer = store.rows(describing: asked, text: text)
        #expect(answer.rows == OutlineOracle.rows(text))
        #expect(!answer.rows.isEmpty)
        #expect(answer.source == .fresh(asked))
        // And asking changed nothing in the store, the stamp included.
        #expect(store.rows == rowsBefore)
        #expect(store.generation == generationBefore)
        #expect(store.describes == describesBefore)
        #expect(store.tally == tallyBefore)
    }

    @Test func anUnstampedStoreParsesToo() {
        let store = OutlineStore(text: noteWithSections)
        let asked = TextRevision.next()
        let answer = store.rows(describing: asked, text: noteWithSections)
        #expect(answer.source == .fresh(asked))
        #expect(answer.rows == OutlineOracle.rows(noteWithSections))
    }

    @Test func theFoldedOrdinalsComeFromTheMapWhenTheStampMatchesAndFromTheTextWhenItDoesNot() {
        let store = OutlineStore(text: noteWithSections)
        let revision = TextRevision.next()
        store.stamp(revision)
        let uno = (noteWithSections as NSString).range(of: "# Uno").location
        let due = (noteWithSections as NSString).range(of: "## Due").location
        let offsets: Set<Int> = [uno, due, 3]

        #expect(
            store.foldedOrdinals(ofOffsets: offsets, describing: revision, text: noteWithSections)
                == foldedOrdinals(ofOffsets: offsets, in: noteWithSections)
        )
        #expect(store.foldedOrdinals(ofOffsets: offsets, describing: revision, text: "").count == 2)

        // Another revision with another text: the translation is the text's, the store's map is not read.
        let other = "## Zero\n# Uno\n"
        let unoInOther = (other as NSString).range(of: "# Uno").location
        let expected = foldedOrdinals(ofOffsets: [unoInOther], in: other)
        #expect(expected == [1])
        #expect(store.foldedOrdinals(ofOffsets: [unoInOther], describing: TextRevision.next(), text: other) == expected)
        #expect(store.describes == revision)
    }

    @Test func nothingFoldedAsksNothing() {
        let store = OutlineStore(text: noteWithSections)
        #expect(store.foldedOrdinals(ofOffsets: [], describing: TextRevision.next(), text: noteWithSections).isEmpty)
    }
}

@MainActor
@Suite struct OutlineStoreEntries {
    @Test func aFoldableHeadingAnswersItsOwnOffset() {
        let store = OutlineStore(text: noteWithSections)
        let uno = (noteWithSections as NSString).range(of: "# Uno").location
        #expect(store.foldableOffset(ofEntry: 0) == uno)
    }

    @Test func anEmbedAndAHeadingWithNothingUnderItAnswerNil() {
        let embeds = OutlineStore(text: "# Uno\n![[foto.png]]\n")
        #expect(embeds.foldableOffset(ofEntry: 0) != nil)
        #expect(embeds.foldableOffset(ofEntry: 1) == nil)

        let last = OutlineStore(text: "# Uno\ncorpo\n## Due")
        #expect(last.foldableOffset(ofEntry: 0) != nil)
        #expect(last.foldableOffset(ofEntry: 1) == nil)
    }

    @Test func anOrdinalOutsideTheListAnswersNil() {
        let store = OutlineStore(text: noteWithSections)
        #expect(store.foldableOffset(ofEntry: 99) == nil)
        #expect(store.foldableOffset(ofEntry: -1) == nil)
        #expect(store.lineRange(ofEntry: 99) == nil)
        #expect(store.lineRange(ofEntry: -1) == nil)
    }

    @Test func theLineRangeIsTheLineWithoutItsTerminator() {
        // What `OutlinePane`'s click handed `onSelect` before this: `NSRange(entry.range, in: text)`.
        let store = OutlineStore(text: noteWithSections)
        let expected = OutlineOracle.items(noteWithSections).map(\.range)
        #expect(expected.count == 4)
        for ordinal in expected.indices {
            #expect(store.lineRange(ofEntry: ordinal) == expected[ordinal], "entry \(ordinal)")
        }
    }

    @Test func theLineRangeFollowsAnEditAbove() {
        var run = StoreRun(text: noteWithSections)
        run.type("nuova riga\n", at: "intro\n", offset: 6)
        let expected = OutlineOracle.items(run.text).map(\.range)
        #expect(expected.count == 4)
        for ordinal in expected.indices {
            #expect(run.store.lineRange(ofEntry: ordinal) == expected[ordinal], "entry \(ordinal)")
        }
    }
}
