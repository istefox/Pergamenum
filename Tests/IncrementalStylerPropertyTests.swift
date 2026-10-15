import Foundation
import Testing
@testable import Pergamenum

// ADR-0091 §D4 and §D5, plan docs/plans/per-paragraph-restyle.md, Task 1 (R-02, R-03, R-04), Seam 1.
//
// The highest and cheapest seam: after any sequence of edits, restyling only what `RestyleScope` says
// leaves the same styling as a full restyle of the same text. `IncrementalStylerModel` is the editor's
// styling state without AppKit; the oracle is `spans(in:)` over the whole text.
//
// Every run asserts, after each restyle:
//   1. the spans' coverage, the unspellable ranges and the spacing ranges equal a full recomputation;
//   2. `scope.map == StructureMap(text:)`;
//   3. the decision was not `.full` for the edits that touched only line-local constructs, and some
//      decision was not `.full` at all: a scope that always answers `.full` cannot pass.
// Failures are counted and the first of each kind is named once, so a red run prints a line and not
// four thousand. Texts stay under 4 KB (`EditGenerator.maxBytes`).

private let seeds: [UInt64] = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]
private let editsPerSeed = 200
private let editsPerGoldenInput = 20

// MARK: - Driving a run

private struct Stats {
    var restyles = 0
    var lines = 0
    var full = 0
    var reasons: [String: Int] = [:]
    var stepsWithSpans = 0
    var coverageMismatches = 0
    var unspellableMismatches = 0
    var spacingMismatches = 0
    var mapMismatches = 0
    var emptyMapSteps = 0
    var localEdits = 0
    var localLines = 0
    var maxBytes = 0
    var examples: [String: String] = [:]

    mutating func note(_ kind: String, _ example: @autoclosure () -> String) {
        if examples[kind] == nil { examples[kind] = example() }
    }

    mutating func add(_ other: Stats) {
        restyles += other.restyles
        lines += other.lines
        full += other.full
        reasons.merge(other.reasons, uniquingKeysWith: +)
        stepsWithSpans += other.stepsWithSpans
        coverageMismatches += other.coverageMismatches
        unspellableMismatches += other.unspellableMismatches
        spacingMismatches += other.spacingMismatches
        mapMismatches += other.mapMismatches
        emptyMapSteps += other.emptyMapSteps
        localEdits += other.localEdits
        localLines += other.localLines
        maxBytes = max(maxBytes, other.maxBytes)
        examples.merge(other.examples) { first, _ in first }
    }
}

private func shortened(_ text: String) -> String {
    let head = String(text.prefix(240))
    return head.debugDescription + (text.count > 240 ? "... (\(text.count) characters)" : "")
}

private func sortedByLocation(_ ranges: [NSRange]) -> [NSRange] {
    ranges.sorted { ($0.location, $0.length) < ($1.location, $1.length) }
}

/// Runs `edits` random edits from `start`, restyling after each (after two, one time in five), and
/// compares every restyle with a full one.
private func drive(
    from start: String, seed: UInt64, edits: Int, atoms: [String], tokens: [String], label: String
) -> Stats {
    var model = IncrementalStylerModel(text: start)
    var generator = EditGenerator(seed: seed, atoms: atoms, tokens: tokens)
    var stats = Stats()

    for step in 0..<edits {
        let batch = Int.random(in: 0..<5, using: &generator.generator) == 0 ? 2 : 1
        var wholesale = false
        let before = model.text
        for _ in 0..<batch {
            let edit = generator.next(for: model.text)
            let length = (model.text as NSString).length
            if edit.range.location == 0, edit.range.length == length { wholesale = true }
            model.apply(edit.replacement, over: edit.range)
        }
        guard let decision = model.restyle() else {
            stats.note("nothing taken", "\(label) step \(step): no decision for \(shortened(model.text))")
            continue
        }

        stats.restyles += 1
        stats.maxBytes = max(stats.maxBytes, model.text.utf8.count)
        let expected = IncrementalStylerModel.full(of: model.text)
        let context = "\(label) step \(step): decision \(decision), before \(shortened(before)), after \(shortened(model.text))"

        switch decision {
        case .lines: stats.lines += 1
        case .full(let reason):
            stats.full += 1
            stats.reasons["\(reason)", default: 0] += 1
        }
        if !expected.spans.isEmpty { stats.stepsWithSpans += 1 }

        if IncrementalStylerModel.coverage(model.state.spans) != IncrementalStylerModel.coverage(expected.spans) {
            stats.coverageMismatches += 1
            stats.note("coverage", context)
        }
        if model.state.unspellable != expected.unspellable {
            stats.unspellableMismatches += 1
            stats.note("unspellable", context)
        }
        if sortedByLocation(model.state.spacing) != sortedByLocation(expected.spacing) {
            stats.spacingMismatches += 1
            stats.note("spacing", context)
        }
        let map = model.scope.map
        if map != StructureMap(text: model.text) {
            stats.mapMismatches += 1
            stats.note("map", context)
        }
        if !model.text.isEmpty, map.lines.isEmpty {
            stats.emptyMapSteps += 1
            stats.note("empty map", context)
        }

        if !wholesale, !before.isEmpty {
            stats.localEdits += 1
            if case .lines = decision { stats.localLines += 1 } else { stats.note("local but full", context) }
        }
    }
    return stats
}

/// The assertions every run makes, with the examples of what failed.
private func expectEqualToFullRestyle(_ stats: Stats, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(stats.restyles > 0, "nothing was restyled", sourceLocation: sourceLocation)
    #expect(stats.coverageMismatches == 0, "coverage: \(stats.examples["coverage"] ?? "")", sourceLocation: sourceLocation)
    #expect(stats.unspellableMismatches == 0, "unspellable: \(stats.examples["unspellable"] ?? "")", sourceLocation: sourceLocation)
    #expect(stats.spacingMismatches == 0, "spacing: \(stats.examples["spacing"] ?? "")", sourceLocation: sourceLocation)
    #expect(stats.mapMismatches == 0, "map: \(stats.examples["map"] ?? "")", sourceLocation: sourceLocation)
    #expect(stats.emptyMapSteps == 0, "the map holds no line: \(stats.examples["empty map"] ?? "")", sourceLocation: sourceLocation)
    #expect(stats.maxBytes < 4096, "a text reached \(stats.maxBytes) bytes", sourceLocation: sourceLocation)
    // Non-vacuity: the comparison was made over texts that hold styling.
    #expect(stats.stepsWithSpans * 2 >= stats.restyles, "most texts held no span", sourceLocation: sourceLocation)
}

private let clock = ContinuousClock()

// MARK: - R-02: random edits from the structural alphabet

// (R-02, R-04) Ten fixed seeds, two hundred edits each: inserts, deletes, multi-line pastes, undos and
// edits at the two ends and into an empty text (a wholesale delete empties it). The run starts from
// `structuralStart` and not from "": started empty, the alphabet drifts through dozens of plain-letter
// texts before its first closed span (seed 1 held almost none in its first sixty steps), the same drift
// `proseStart` was written for.
@Test(arguments: seeds)
func randomStructuralEditsStyleLikeAFullRestyle(_ seed: UInt64) {
    var stats = Stats()
    let elapsed = clock.measure {
        stats = drive(
            from: EditGenerator.structuralStart, seed: seed, edits: editsPerSeed,
            atoms: EditGenerator.structuralAtoms, tokens: EditGenerator.structuralTokens, label: "seed \(seed)"
        )
    }
    print(
        "incremental-property structural seed=\(seed) restyles=\(stats.restyles) withSpans=\(stats.stepsWithSpans)"
            + " lines=\(stats.lines) full=\(stats.full) reasons=\(stats.reasons) maxBytes=\(stats.maxBytes)"
            + " time=\(elapsed)"
    )
    expectEqualToFullRestyle(stats)
    // The floor (3): a scope that answers `.full` for everything cannot pass.
    #expect(stats.lines >= 10, "only \(stats.lines) of \(stats.restyles) restyles were .lines; \(stats.reasons)")
    #expect(stats.lines * 20 >= stats.restyles, "fewer than 5% of \(stats.restyles) restyles were .lines")
    #expect(stats.full > 0, "no structural edit fell back to a full restyle")
}

// (R-02, R-04) The same, over prose and line-local constructs only: nothing here opens a fence, a table,
// a link or frontmatter, so no edit may fall back to a full restyle but a wholesale replace.
@Test(arguments: seeds)
func randomLineLocalEditsAreRestyledByLines(_ seed: UInt64) {
    var stats = Stats()
    let elapsed = clock.measure {
        stats = drive(
            from: EditGenerator.proseStart, seed: seed &+ 100, edits: editsPerSeed,
            atoms: EditGenerator.proseAtoms, tokens: EditGenerator.proseTokens, label: "prose seed \(seed)"
        )
    }
    print("incremental-property prose seed=\(seed) restyles=\(stats.restyles) lines=\(stats.lines) full=\(stats.full) localEdits=\(stats.localEdits) localLines=\(stats.localLines) withSpans=\(stats.stepsWithSpans) reasons=\(stats.reasons) maxBytes=\(stats.maxBytes) time=\(elapsed)")
    expectEqualToFullRestyle(stats)
    #expect(stats.localEdits >= 100, "only \(stats.localEdits) edits counted as local")
    #expect(
        stats.localLines * 100 >= stats.localEdits * 95,
        "\(stats.localLines) of \(stats.localEdits) line-local edits were .lines; \(stats.reasons); \(stats.examples["local but full"] ?? "")"
    )
}

// MARK: - Callouts (ADR-0087's amendment of ADR-0091 §D3)

/// Two callouts, one folded with a nested quote, and a plain quote between prose.
private let calloutStart = "intro\n\n> [!note] Titolo\n> uno\n> due\n\n> [!avviso]- Piegato\n> corpo\n> > annidata\n\n"
    + "> citata\n> ancora\n\nfine\n"
/// What makes and breaks a callout: a header typed whole or in pieces, a `>` added or taken from a
/// line, a level, a line break that splits a run.
private let calloutTokens = ["> ", "> [!note] ", "> [!tip]- ", "[!", "]", "\n", ">> ", "\n> ", "==x=="]

// (R-04, N5 R-38) A callout makes a run's lines depend on its first one: an edit that types a header,
// breaks a run or joins two must leave what a full restyle leaves, over every line of every run it
// touches (plan N5, Realignment 3).
@Test(arguments: seeds)
func randomCalloutEditsStyleLikeAFullRestyle(_ seed: UInt64) {
    let stats = drive(
        from: calloutStart, seed: seed &+ 200, edits: editsPerSeed,
        atoms: EditGenerator.proseAtoms, tokens: calloutTokens, label: "callout seed \(seed)"
    )
    print(
        "incremental-property callout seed=\(seed) restyles=\(stats.restyles) lines=\(stats.lines)"
            + " full=\(stats.full) reasons=\(stats.reasons)"
    )
    expectEqualToFullRestyle(stats)
}

// MARK: - R-03: the golden inputs as starting texts

/// A golden input cut to the size every run keeps under, at a character boundary.
private func capped(_ text: String) -> String {
    var result = ""
    for character in text {
        if result.utf8.count + String(character).utf8.count > EditGenerator.maxBytes { break }
        result.append(character)
    }
    return result
}

// (R-03) Each of the golden corpus's inputs as a starting text, twenty edits each.
@Test func editsFromEveryGoldenInputStyleLikeAFullRestyle() {
    let inputs = StylerGoldenCorpus.inputs
    #expect(inputs.count >= 119)
    var total = Stats()
    let elapsed = clock.measure {
        for (index, input) in inputs.enumerated() {
            let stats = drive(
                from: capped(input.markdown), seed: 1_000 &+ UInt64(index), edits: editsPerGoldenInput,
                atoms: EditGenerator.structuralAtoms, tokens: EditGenerator.structuralTokens,
                label: "golden \(input.name)"
            )
            total.add(stats)
        }
    }
    print("incremental-property golden inputs=\(inputs.count) restyles=\(total.restyles) lines=\(total.lines) full=\(total.full) reasons=\(total.reasons) maxBytes=\(total.maxBytes) time=\(elapsed)")
    expectEqualToFullRestyle(total)
    #expect(total.lines * 10 >= total.restyles, "fewer than 10% of \(total.restyles) restyles were .lines; \(total.reasons)")
}

// MARK: - The fragment entry, pinned directly

private func spans(_ text: String, _ styled: [MarkdownStyler.StyledRange]) -> [ModelSpan] {
    styled.map { ModelSpan(range: NSRange($0.range, in: text), span: $0.span) }
}

// (R-03) A fragment that starts the note, with a leading `---` read as frontmatter, is `spans(in:)`:
// the golden corpus is the oracle for the fragment entry, byte for byte and in emission order.
@Test func theFragmentEntryOverTheWholeNoteIsTheFullEntry() {
    var compared = 0
    var withSpans = 0
    for input in StylerGoldenCorpus.inputs {
        let whole = spans(input.markdown, MarkdownStyler.spans(in: input.markdown))
        let context = MarkdownStyler.FragmentContext(listSeed: [], readsFrontmatter: true)
        let fragment = spans(input.markdown, MarkdownStyler.spans(inFragment: input.markdown, context: context))
        #expect(fragment == whole, "\(input.name)")
        compared += 1
        if !whole.isEmpty { withSpans += 1 }
    }
    #expect(compared >= 119)
    #expect(withSpans >= 100, "the corpus's inputs held spans in only \(withSpans) cases")
}

// (R-03) Without `readsFrontmatter` a leading `---` block is not frontmatter, so a fragment never
// takes a block that is not at the top of the note for one.
@Test func aFragmentThatDoesNotStartTheNoteReadsNoFrontmatter() {
    let text = "---\ntitle: a\n---\ncorpo"
    let reads = spans(text, MarkdownStyler.spans(
        inFragment: text, context: MarkdownStyler.FragmentContext(listSeed: [], readsFrontmatter: true)
    ))
    let skips = spans(text, MarkdownStyler.spans(
        inFragment: text, context: MarkdownStyler.FragmentContext(listSeed: [], readsFrontmatter: false)
    ))
    #expect(reads.contains { $0.span == .frontmatter })
    #expect(!skips.isEmpty)
    #expect(!skips.contains { $0.span == .frontmatter })
}

// (R-03) The list seed reaches the markers: an item under an open item of content column 2 is level 2.
@Test func theListSeedDeepensTheMarkersOfAFragment() {
    let fragment = "  - figlio"
    func level(_ seed: [Int]) -> Int? {
        let styled = MarkdownStyler.spans(
            inFragment: fragment, context: MarkdownStyler.FragmentContext(listSeed: seed, readsFrontmatter: false)
        )
        for item in styled {
            if case .listMarker(_, let level) = item.span { return level }
        }
        return nil
    }
    #expect(level([]) == 1)
    #expect(level([2]) == 2)
}

// (R-02) The fragment of a mid-note range, in the note's coordinates, is the slice of the whole note's
// spans that lie in it.
@Test func aMidNoteFragmentsSpansAreTheSliceOfTheWholeNotesSpans() {
    let note = "intro\n# Titolo con **grassetto** e [[Link]]\n- voce #area-training\nfine"
    let start = (note as NSString).range(of: "# Titolo").location
    let end = (note as NSString).range(of: "\nfine").location
    let region = NSRange(location: start, length: end - start)
    let fragment = (note as NSString).substring(with: region)

    let whole = spans(note, MarkdownStyler.spans(in: note)).filter {
        $0.range.location >= region.location && NSMaxRange($0.range) <= NSMaxRange(region)
    }
    let seed = RestyleScope(text: note).listSeed(at: region.location)
    let found = spans(fragment, MarkdownStyler.spans(
        inFragment: fragment, context: MarkdownStyler.FragmentContext(listSeed: seed, readsFrontmatter: false)
    )).map { ModelSpan(range: NSRange(location: $0.range.location + region.location, length: $0.range.length), span: $0.span) }
    #expect(whole.count > 5)
    #expect(found == whole)
}

// MARK: - spliced

/// The list with `dirty` cut out, written for the test and not taken from the code.
private func cut(_ ranges: [NSRange], outside dirty: NSRange) -> [NSRange] {
    var result: [NSRange] = []
    for range in ranges {
        if range.length > 0, range.location < dirty.location {
            let end = min(NSMaxRange(range), dirty.location)
            result.append(NSRange(location: range.location, length: end - range.location))
        }
        if NSMaxRange(range) > NSMaxRange(dirty), range.length > 0 {
            let start = max(range.location, NSMaxRange(dirty))
            result.append(NSRange(location: start, length: NSMaxRange(range) - start))
        }
    }
    return result.filter { $0.length > 0 && !($0.location >= dirty.location && NSMaxRange($0) <= NSMaxRange(dirty)) }
}

// (R-02) The dirty range is cut out, the fragment goes in, and the seams are re-merged.
@Test func splicingCutsTheDirtyRangeAndPutsTheFragmentIn() {
    let current = [NSRange(location: 0, length: 5), NSRange(location: 8, length: 12), NSRange(location: 30, length: 2)]
    let dirty = NSRange(location: 10, length: 5)
    #expect(MarkdownStyler.spliced(current, replacing: dirty, with: [NSRange(location: 11, length: 2)]) == [
        NSRange(location: 0, length: 5), NSRange(location: 8, length: 2), NSRange(location: 11, length: 2),
        NSRange(location: 15, length: 5), NSRange(location: 30, length: 2),
    ])
    // A fragment range that touches both cuts joins what the cut separated.
    #expect(MarkdownStyler.spliced(current, replacing: dirty, with: [NSRange(location: 10, length: 5)]) == [
        NSRange(location: 0, length: 5), NSRange(location: 8, length: 12), NSRange(location: 30, length: 2),
    ])
    // And with nothing in the fragment the range that crossed the dirty range is two.
    #expect(MarkdownStyler.spliced(current, replacing: dirty, with: []) == [
        NSRange(location: 0, length: 5), NSRange(location: 8, length: 2), NSRange(location: 15, length: 5),
        NSRange(location: 30, length: 2),
    ])
}

// (R-02) A range wholly inside the dirty range is dropped; a range that ends where it starts joins it.
@Test func splicingDropsWhatLiesInsideAndJoinsWhatTouches() {
    let current = [NSRange(location: 0, length: 3), NSRange(location: 11, length: 2), NSRange(location: 40, length: 1)]
    #expect(MarkdownStyler.spliced(current, replacing: NSRange(location: 10, length: 5), with: []) == [
        NSRange(location: 0, length: 3), NSRange(location: 40, length: 1),
    ])
    let touching = [NSRange(location: 0, length: 5), NSRange(location: 15, length: 5)]
    #expect(MarkdownStyler.spliced(touching, replacing: NSRange(location: 5, length: 10), with: [NSRange(location: 5, length: 10)]) == [
        NSRange(location: 0, length: 20),
    ])
}

// (R-02) Against a cut-then-merge written here, over random disjoint lists.
@Test(arguments: seeds)
func splicingEqualsCuttingThenMerging(_ seed: UInt64) {
    var generator = SplitMix64(seed: seed)
    var nonTrivial = 0
    for _ in 0..<60 {
        var current: [NSRange] = []
        var cursor = 0
        while cursor < 180 {
            cursor += Int.random(in: 0...6, using: &generator)
            let length = Int.random(in: 1...9, using: &generator)
            current.append(NSRange(location: cursor, length: length))
            cursor += length + Int.random(in: 1...6, using: &generator)
        }
        current = MarkdownStyler.merged(current)
        let from = Int.random(in: 0..<150, using: &generator)
        let dirty = NSRange(location: from, length: Int.random(in: 1...30, using: &generator))
        var fragment: [NSRange] = []
        var inside = dirty.location + Int.random(in: 0...3, using: &generator)
        while inside < NSMaxRange(dirty) {
            let length = min(Int.random(in: 1...5, using: &generator), NSMaxRange(dirty) - inside)
            fragment.append(NSRange(location: inside, length: length))
            inside += length + Int.random(in: 1...4, using: &generator)
        }
        let expected = MarkdownStyler.merged(cut(current, outside: dirty) + fragment)
        let spliced = MarkdownStyler.spliced(current, replacing: dirty, with: fragment)
        #expect(spliced == expected, "current \(current) dirty \(dirty) fragment \(fragment)")
        if !expected.isEmpty, !fragment.isEmpty { nonTrivial += 1 }
    }
    #expect(nonTrivial > 30)
}

// MARK: - Paragraph spacing, ranged

// (R-02) The ranged entry is the existing per-line predicate over the fragment's lines, in the note's
// coordinates.
@Test func paragraphSpacingOverAFragmentIsTheSliceOfTheWholeNotes() {
    let note = "# Titolo\nprima riga di prosa\n- voce\nseconda riga di prosa\n\nfine"
    let start = (note as NSString).range(of: "prima").location
    let region = NSRange(location: start, length: (note as NSString).length - start)
    let fragment = (note as NSString).substring(with: region)

    let whole = ProseParagraphSpacing.paragraphRanges(in: note, spans: MarkdownStyler.spans(in: note))
        .filter { $0.location >= region.location }
    let found = ProseParagraphSpacing.paragraphRanges(
        inFragment: fragment, offset: region.location, spans: MarkdownStyler.spans(in: fragment)
    )
    #expect(whole.count >= 3)
    #expect(found == whole)
}
