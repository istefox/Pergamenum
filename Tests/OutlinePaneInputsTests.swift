import Foundation
import Testing
@testable import Pergamenum

// ADR-0096 §D7, plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 4 (PG-406, R-07).
//
// `OutlinePaneInputs` is what the sidebar's index is drawn from, and its `==` is what lets
// `.equatable()` skip the pane on a keystroke that changed no row: the rows are the same when their
// source is the same, so the comparison reads a store's identity and generation and never the rows
// themselves. `==` is declared by the tester (it is the semantics, not logic), so the first three tests
// are green already; `hiddenByFold` is the walk that moves out of the pane and is red until Task 5.

private let nested = "# A\n## A1\n### A11\ntexto\n![[x.png]]\n## A2\n# B\n![[y.png]]\n"

@MainActor
private func inputs(
    rows: [OutlineRow] = OutlineOracle.rows(nested),
    source: OutlineRowsSource,
    notePath: String = "nota.md",
    currentEntry: Int? = 1,
    folded: Set<Int> = []
) -> OutlinePaneInputs {
    OutlinePaneInputs(rows: rows, source: source, notePath: notePath, currentEntry: currentEntry, foldedOrdinals: folded)
}

@MainActor
@Suite struct OutlinePaneInputsEquality {
    @Test func equalWhenOnlyTheRowsDifferUnderOneSource() {
        let store = OutlineStore(text: nested)
        let source = OutlineRowsSource.store(ObjectIdentifier(store), generation: 3)
        let rows = OutlineOracle.rows(nested)
        let other = OutlineOracle.rows("# Altro\n")
        #expect(rows != other)
        // The rows are not read: the generation says whether they moved.
        #expect(inputs(rows: rows, source: source) == inputs(rows: other, source: source))
    }

    @Test func unequalWhenTheStoreDiffersWithTheSameGeneration() {
        // The two columns' stores: generation 0 in each, so only the identity tells them apart.
        let left = OutlineStore(text: nested)
        let right = OutlineStore(text: nested)
        #expect(left.generation == right.generation)
        let one = inputs(source: .store(ObjectIdentifier(left), generation: 0))
        let two = inputs(source: .store(ObjectIdentifier(right), generation: 0))
        #expect(one != two)
    }

    @Test func unequalWhenAnythingElseDiffers() {
        let store = OutlineStore(text: nested)
        let id = ObjectIdentifier(store)
        let base = inputs(source: .store(id, generation: 1), folded: [0])
        #expect(base == inputs(source: .store(id, generation: 1), folded: [0]))
        #expect(base != inputs(source: .store(id, generation: 2), folded: [0]))
        #expect(base != inputs(source: .store(id, generation: 1), notePath: "altra.md", folded: [0]))
        #expect(base != inputs(source: .store(id, generation: 1), currentEntry: 2, folded: [0]))
        #expect(base != inputs(source: .store(id, generation: 1), currentEntry: nil, folded: [0]))
        #expect(base != inputs(source: .store(id, generation: 1), folded: [0, 1]))
        let revision = TextRevision.next()
        #expect(inputs(source: .fresh(revision)) == inputs(source: .fresh(revision)))
        #expect(inputs(source: .fresh(revision)) != inputs(source: .store(id, generation: 1)))
    }
}

/// The walk `OutlinePane.hiddenByFold` ran over the entries (`OutlinePane.swift:202-215` on `93c17096`),
/// restated here as the oracle: a folded heading hides every entry after it up to the next heading of the
/// same or a higher level, and an embed never ends a section (so it stays hidden with the section it sits
/// in). Restated, not called, because the walk leaves the pane in Task 5.
private func formerWalk(_ rows: [OutlineRow], folded: Set<Int>) -> Set<Int> {
    var hidden: Set<Int> = []
    for index in folded {
        guard rows.indices.contains(index), case .heading(let level) = rows[index].kind else { continue }
        for next in rows.indices where next > index {
            if case .heading(let nextLevel) = rows[next].kind, nextLevel <= level { break }
            hidden.insert(next)
        }
    }
    return hidden
}

private let foldSets: [Set<Int>] = [[], [0], [1], [2], [0, 1], [1, 2], [3], [5], [6], [0, 5], [99], [-1, 1]]

@MainActor
@Suite struct OutlinePaneInputsHiddenByFold {
    @Test(arguments: foldSets)
    func hiddenByFoldIsTheFormerWalk(_ folded: Set<Int>) {
        let rows = OutlineOracle.rows(nested)
        #expect(rows.count == 7)
        let subject = inputs(rows: rows, source: .fresh(TextRevision.next()), folded: folded)
        #expect(subject.hiddenByFold == formerWalk(rows, folded: folded), "folded \(folded.sorted())")
    }

    @Test func foldingASectionHidesItsChildrenAndItsEmbedsButNotTheNextSibling() {
        let rows = OutlineOracle.rows(nested)
        // `## A1` (entry 1) hides `### A11` (2) and the embed (3); `## A2` (4) ends it.
        let subject = inputs(rows: rows, source: .fresh(TextRevision.next()), folded: [1])
        #expect(subject.hiddenByFold == [2, 3])
        // `# A` (0) hides everything up to `# B` (5).
        let top = inputs(rows: rows, source: .fresh(TextRevision.next()), folded: [0])
        #expect(top.hiddenByFold == [1, 2, 3, 4])
    }

    @Test func aFoldedEmbedHidesNothing() {
        let rows = OutlineOracle.rows(nested)
        #expect(rows[3].kind == .embed)
        let subject = inputs(rows: rows, source: .fresh(TextRevision.next()), folded: [3])
        #expect(subject.hiddenByFold.isEmpty)
    }
}
