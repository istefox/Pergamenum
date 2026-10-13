import Foundation
import Testing
@testable import Pergamenum

// ADR-0096 §D6, plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 4 (PG-406, R-06).
//
// The outline map, driven the way the coordinator drives it, against the parse as the oracle. Seeded random
// edit sequences from the same generator and the same seeds `IncrementalStylerPropertyTests` runs, with the
// structural atoms that matter to an outline added (opening and closing a backtick, a tilde and a
// `pergamenum-view` fence, frontmatter delimiters, setext underlines, `#` at a line start). Each edit is
// handled as `applyIncrementalStyling` handles it:
//
//   1. the edit reaches `StorageEdit`, is recorded on the `RestyleScope` and shifts the map (`apply`);
//   2. the scope takes its decision: `.lines(dirty)` absorbs the fragment's structure map and splices the
//      outline with the absorbed map's fences; `.full` rebuilds the map and the scope.
//
// After every restyle the map's items equal the converted `NoteOutline.entries(in:)`, and the three
// equalities `OutlineMapTests` makes (ordinals, foldable, last entry) hold. A second pass runs the kill
// switch's shape (rebuild on every edit, no shift). A failure prints the seed and the edit. Red until
// Task 5: the red-phase map is empty.

private let seeds: [UInt64] = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]
private let editsPerSeed = 200
private let editsPerGoldenInput = 20

/// The structural atoms plus the ones that open and close what an outline skips or reads. Whole heading
/// and embed lines are atoms, so that entries keep being typed against the deletions that remove them: with
/// the styler's alphabet alone a random run settles on 1% to 40% of its steps holding any entry, which would
/// leave most of the comparison to compare two empty lists.
private let outlineAtoms = EditGenerator.structuralAtoms + [
    "#", "#", " ", "\n", "\n", "=", "!", "[", "]",
    "# t\n", "# t\n", "## u\n", "### v\n", "![[a.png]]\n",
]
/// The prose alphabet plus whole heading lines: line-local, so no edit opens a fence or a block.
private let outlineProseAtoms = EditGenerator.proseAtoms + ["# t\n", "## u\n", "![[a.png]]\n"]
private let outlineTokens = EditGenerator.structuralTokens + [
    "# ", "## ", "### ", "```", "~~~", "```pergamenum-view\n", "---\n", "\n===\n", "\n---\n", "![[a.png]]\n", "\n# ",
]

private let outlineStart = """
---
date: 2026-10-13
---
# Titolo

intro

## Sezione uno
corpo
![[foto.png]]

```
# non un titolo
```

### Sotto
fine

"""

private struct Failures {
    var steps = 0
    var linesSteps = 0
    var fullSteps = 0
    var stepsWithEntries = 0
    var itemMismatches = 0
    var ordinalMismatches = 0
    var foldableMismatches = 0
    var lastEntryMismatches = 0
    var examples: [String: String] = [:]

    mutating func note(_ kind: String, _ example: @autoclosure () -> String) {
        if examples[kind] == nil { examples[kind] = example() }
    }

    mutating func add(_ other: Failures) {
        steps += other.steps
        linesSteps += other.linesSteps
        fullSteps += other.fullSteps
        stepsWithEntries += other.stepsWithEntries
        itemMismatches += other.itemMismatches
        ordinalMismatches += other.ordinalMismatches
        foldableMismatches += other.foldableMismatches
        lastEntryMismatches += other.lastEntryMismatches
        examples.merge(other.examples) { first, _ in first }
    }
}

private func shortened(_ text: String) -> String {
    let head = String(text.prefix(200))
    return head.debugDescription + (text.count > 200 ? "... (\(text.count) characters)" : "")
}

/// The assertions of one step, against the parse of `text`.
private func check(_ map: OutlineMap, against text: String, into stats: inout Failures, context: @autoclosure () -> String) {
    let expected = OutlineOracle.items(text)
    if !expected.isEmpty { stats.stepsWithEntries += 1 }
    if map.items != expected {
        stats.itemMismatches += 1
        stats.note("items", "\(context()): map \(map.items.map(\.title)) against parse \(expected.map(\.title))")
        return
    }

    var offsets = Set(expected.map(\.range.location))
    offsets.insert((text as NSString).length + 3)
    if let first = expected.first { offsets.insert(first.range.location + 1) }
    if map.ordinals(ofOffsets: offsets) != foldedOrdinals(ofOffsets: offsets, in: text) {
        stats.ordinalMismatches += 1
        stats.note("ordinals", context())
    }

    let foldable = NoteFolding.foldableEntries(in: text)
    if !expected.indices.allSatisfy({ map.isFoldable($0) == foldable.contains($0) }) {
        stats.foldableMismatches += 1
        stats.note("foldable", context())
    }

    // Around every entry, and every eleventh position between them.
    let length = (text as NSString).length
    var carets = Set(stride(from: 0, through: length, by: 11))
    for item in expected {
        carets.formUnion([item.range.location - 1, item.range.location, NSMaxRange(item.range), NSMaxRange(item.range) + 1])
    }
    let locations = expected.map(\.range.location)
    for caret in carets where (0...length).contains(caret) {
        if map.lastEntry(atOrBefore: caret) != locations.lastIndex(where: { $0 <= caret }) {
            stats.lastEntryMismatches += 1
            stats.note("lastEntry", "\(context()) caret \(caret)")
            break
        }
    }
}

/// Runs `edits` random edits from `start`. With `killSwitch` the map is rebuilt on every edit and never
/// shifted: the shape `-editorFullRestyle YES` gives the coordinator.
private func drive(
    from start: String, seed: UInt64, edits: Int, atoms: [String], tokens: [String], label: String,
    killSwitch: Bool = false
) -> Failures {
    var text = start
    var scope = RestyleScope(text: start)
    var map = OutlineMap(text: start)
    var generator = EditGenerator(seed: seed, atoms: atoms, tokens: tokens)
    var stats = Failures()

    // The map as built from the start text is already right, or nothing after it can be.
    check(map, against: text, into: &stats, context: "\(label) start \(shortened(text))")

    for step in 0..<edits {
        let batch = Int.random(in: 0..<5, using: &generator.generator) == 0 ? 2 : 1
        let before = text
        var applied: [String] = []
        for _ in 0..<batch {
            let edit = generator.next(for: text)
            let new = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
            let length = (edit.replacement as NSString).length
            let storage = StorageEdit(
                range: NSRange(location: edit.range.location, length: length), delta: length - edit.range.length
            )
            scope.record(storage, in: new as NSString)
            if !killSwitch { map.apply(storage) }
            text = new
            applied.append("\(edit.range) -> \(edit.replacement.debugDescription)")
        }

        guard let decision = scope.take() else { continue }
        stats.steps += 1
        switch decision {
        case .full:
            stats.fullSteps += 1
            map.rebuild(text: text)
            scope = RestyleScope(text: text)
        case .lines(let dirty):
            if killSwitch {
                // The kill switch never takes this branch in the app: `forcesFullRestyle` keeps no scope.
                map.rebuild(text: text)
            } else {
                stats.linesSteps += 1
                let fragment = (text as NSString).substring(with: dirty)
                scope.absorb(StructureMap(text: fragment), at: dirty.location, replacing: dirty)
                map.splice(text as NSString, in: dirty, fences: scope.map.fences)
            }
        }
        check(
            map, against: text, into: &stats,
            context: "\(label) step \(step): decision \(decision), edits \(applied), before \(shortened(before)), after \(shortened(text))"
        )
    }
    return stats
}

private func expectAgreesWithTheParse(_ stats: Failures, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(stats.steps > 0, "nothing was restyled", sourceLocation: sourceLocation)
    #expect(stats.itemMismatches == 0, "items: \(stats.examples["items"] ?? "")", sourceLocation: sourceLocation)
    #expect(stats.ordinalMismatches == 0, "ordinals: \(stats.examples["ordinals"] ?? "")", sourceLocation: sourceLocation)
    #expect(stats.foldableMismatches == 0, "foldable: \(stats.examples["foldable"] ?? "")", sourceLocation: sourceLocation)
    #expect(stats.lastEntryMismatches == 0, "last entry: \(stats.examples["lastEntry"] ?? "")", sourceLocation: sourceLocation)
    // Non-vacuity: the comparison was made over texts that hold entries.
    // Non-vacuity floor: measured 15% to 100% of the steps holding an entry; 10% leaves room and still fails an
    // alphabet that stops typing entries.
    #expect(stats.stepsWithEntries * 10 >= stats.steps, "too few texts held an entry (\(stats.stepsWithEntries) of \(stats.steps))", sourceLocation: sourceLocation)
}

// MARK: - The sequences

// (R-06) The ten seeds of the styler's own property test, two hundred edits each, from an empty note.
@Test(arguments: seeds)
func randomStructuralEditsKeepTheOutlineMapEqualToTheParse(_ seed: UInt64) {
    let stats = drive(
        from: "", seed: seed, edits: editsPerSeed,
        atoms: outlineAtoms, tokens: outlineTokens, label: "seed \(seed)"
    )
    print("outline-property structural seed=\(seed) steps=\(stats.steps) lines=\(stats.linesSteps) full=\(stats.fullSteps) withEntries=\(stats.stepsWithEntries)")
    expectAgreesWithTheParse(stats)
    #expect(stats.linesSteps >= 10, "only \(stats.linesSteps) of \(stats.steps) restyles were .lines, so the splice was barely run")
    #expect(stats.fullSteps > 0, "no edit fell back to a rebuild")
}

// (R-06) The same from a note that already holds a frontmatter block, headings, an embed and a fence, so
// the edits land among entries from the first one.
@Test(arguments: seeds)
func randomEditsFromAnOutlineRichNoteKeepTheMapEqualToTheParse(_ seed: UInt64) {
    let stats = drive(
        from: outlineStart, seed: seed &+ 200, edits: editsPerSeed,
        atoms: outlineAtoms, tokens: outlineTokens, label: "rich seed \(seed)"
    )
    print("outline-property rich seed=\(seed) steps=\(stats.steps) lines=\(stats.linesSteps) full=\(stats.fullSteps) withEntries=\(stats.stepsWithEntries)")
    expectAgreesWithTheParse(stats)
    #expect(stats.linesSteps >= 10, "only \(stats.linesSteps) of \(stats.steps) restyles were .lines")
}

// (R-06) Prose and line-local constructs only: nothing opens a fence or a block of frontmatter, so almost
// every edit is a splice and the shift is exercised without a rebuild to hide behind.
@Test(arguments: seeds)
func randomLineLocalEditsAreSplicedAndNeverRebuilt(_ seed: UInt64) {
    let stats = drive(
        from: EditGenerator.proseStart, seed: seed &+ 100, edits: editsPerSeed,
        atoms: outlineProseAtoms, tokens: EditGenerator.proseTokens, label: "prose seed \(seed)"
    )
    print("outline-property prose seed=\(seed) steps=\(stats.steps) lines=\(stats.linesSteps) full=\(stats.fullSteps) withEntries=\(stats.stepsWithEntries)")
    expectAgreesWithTheParse(stats)
    // Measured 68% to 98% (the restyler itself widens an edit that crosses a line to .full); half is the floor.
    #expect(stats.linesSteps * 2 >= stats.steps, "\(stats.linesSteps) of \(stats.steps) restyles were .lines")
}

// (R-06) Each of the golden corpus's inputs as a starting text, twenty edits each.
@Test func editsFromEveryGoldenInputKeepTheMapEqualToTheParse() {
    let inputs = StylerGoldenCorpus.inputs
    #expect(inputs.count >= 119)
    var total = Failures()
    for (index, input) in inputs.enumerated() {
        var capped = ""
        for character in input.markdown {
            if capped.utf8.count + String(character).utf8.count > EditGenerator.maxBytes { break }
            capped.append(character)
        }
        total.add(drive(
            from: capped, seed: 1_000 &+ UInt64(index), edits: editsPerGoldenInput,
            atoms: outlineAtoms, tokens: outlineTokens, label: "golden \(input.name)"
        ))
    }
    print("outline-property golden inputs=\(inputs.count) steps=\(total.steps) lines=\(total.linesSteps) full=\(total.fullSteps) withEntries=\(total.stepsWithEntries)")
    expectAgreesWithTheParse(total)
}

// MARK: - The kill switch

// (R-06) `-editorFullRestyle YES` keeps no scope: the coordinator rebuilds on every pass and shifts
// nothing, and the map still equals the parse.
@Test(arguments: seeds)
func underTheKillSwitchTheMapIsRebuiltOnEveryEditAndEqualsTheParse(_ seed: UInt64) {
    let stats = drive(
        from: outlineStart, seed: seed &+ 300, edits: editsPerSeed,
        atoms: outlineAtoms, tokens: outlineTokens, label: "kill switch seed \(seed)", killSwitch: true
    )
    print("outline-property killswitch seed=\(seed) steps=\(stats.steps) withEntries=\(stats.stepsWithEntries)")
    expectAgreesWithTheParse(stats)
}
