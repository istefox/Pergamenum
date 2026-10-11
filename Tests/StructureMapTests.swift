import Foundation
import Testing
@testable import Pergamenum

// ADR-0091 §D2 and §D5, plan docs/plans/per-paragraph-restyle.md, Task 1 (R-02, R-04).
//
// `StorageEdit`'s three rules, and `StructureMap`: what it holds for a text, how `apply` keeps it
// current through an edit that changes no run, and how `splice` replaces the runs inside a dirty range
// with the ones the fragment produced. The oracle for a map is `StructureMap(text:)` of the text it
// describes, and the oracles for its runs are the full styler's `.tableRun` and `.viewBlockRun` spans
// and `CodeFence.regions`. Every comparison of two maps also asserts that the expected one holds
// something, so that the placeholder, whose maps are all empty and all equal, cannot pass.

// MARK: - StorageEdit

/// Typing five characters over three at 10: the old range is 10..<13, the new one 10..<15.
private let replacing = StorageEdit(range: NSRange(location: 10, length: 5), delta: 2)
/// Deleting three characters at 10: the old range is 10..<13, the new one empty.
private let deleting = StorageEdit(range: NSRange(location: 10, length: 0), delta: -3)

// (R-06, platform pin's consumer) The replaced range is the edited range less the change in length.
@Test func theOldRangeIsTheEditedRangeLessTheDelta() {
    #expect(replacing.oldRange == NSRange(location: 10, length: 3))
    #expect(deleting.oldRange == NSRange(location: 10, length: 3))
    #expect(StorageEdit(range: NSRange(location: 10, length: 1), delta: 1).oldRange == NSRange(location: 10, length: 0))
    #expect(StorageEdit(range: NSRange(location: 4, length: 2), delta: 0).oldRange == NSRange(location: 4, length: 2))
}

// (R-05) An offset before the old range stays; one after it moves by the delta.
@Test func anOffsetBeforeStaysAndAnOffsetAfterMoves() {
    #expect(replacing.shifted(4) == 4)
    #expect(replacing.shifted(13) == 15)
    #expect(replacing.shifted(40) == 42)
    #expect(deleting.shifted(3) == 3)
    #expect(deleting.shifted(13) == 10)
    #expect(deleting.shifted(20) == 17)
    let typing = StorageEdit(range: NSRange(location: 10, length: 1), delta: 1)
    #expect(typing.shifted(5) == 5)
    #expect(typing.shifted(20) == 21)
}

// (R-05) A range before the old range stays, one after it moves, one that contains it stretches.
@Test func aRangeBeforeStaysAfterMovesAndContainingStretches() {
    #expect(replacing.shifted(NSRange(location: 2, length: 5)) == NSRange(location: 2, length: 5))
    #expect(replacing.shifted(NSRange(location: 5, length: 5)) == NSRange(location: 5, length: 5))
    #expect(replacing.shifted(NSRange(location: 20, length: 4)) == NSRange(location: 22, length: 4))
    #expect(replacing.shifted(NSRange(location: 13, length: 4)) == NSRange(location: 15, length: 4))
    #expect(replacing.shifted(NSRange(location: 5, length: 20)) == NSRange(location: 5, length: 22))
    #expect(deleting.shifted(NSRange(location: 5, length: 20)) == NSRange(location: 5, length: 17))
    #expect(deleting.shifted(NSRange(location: 20, length: 4)) == NSRange(location: 17, length: 4))
}

// (R-05) A range that lies partly or wholly inside the old range is lost to `shifted`.
@Test func aRangePartlyOrWhollyInsideTheOldRangeShiftsToNothing() {
    #expect(replacing.shifted(NSRange(location: 5, length: 6)) == nil)
    #expect(replacing.shifted(NSRange(location: 12, length: 6)) == nil)
    #expect(replacing.shifted(NSRange(location: 11, length: 1)) == nil)
    #expect(deleting.shifted(NSRange(location: 8, length: 4)) == nil)
    #expect(deleting.shifted(NSRange(location: 11, length: 6)) == nil)
}

// (R-05) `clipped` moves and stretches the way `shifted` does.
@Test func clippingAWholeRangeIsShiftingIt() {
    #expect(replacing.clipped(NSRange(location: 2, length: 5)) == [NSRange(location: 2, length: 5)])
    #expect(replacing.clipped(NSRange(location: 22, length: 4)) == [NSRange(location: 24, length: 4)])
    #expect(replacing.clipped(NSRange(location: 5, length: 20)) == [NSRange(location: 5, length: 22)])
}

// (R-05) One inside the old range is dropped; one crossing an end is cut down to its outside part.
@Test func clippingCutsACrossingRangeToItsOutsidePart() {
    #expect(replacing.clipped(NSRange(location: 11, length: 1)).isEmpty)
    // 5..<11 crosses the start of 10..<13: what is left is 5..<10, where it was.
    #expect(replacing.clipped(NSRange(location: 5, length: 6)) == [NSRange(location: 5, length: 5)])
    // 12..<18 crosses the end: what is left is 13..<18, moved by the delta to 15..<20.
    #expect(replacing.clipped(NSRange(location: 12, length: 6)) == [NSRange(location: 15, length: 5)])
    // The same two against a deletion of 10..<13.
    #expect(deleting.clipped(NSRange(location: 8, length: 4)) == [NSRange(location: 8, length: 2)])
    #expect(deleting.clipped(NSRange(location: 11, length: 6)) == [NSRange(location: 10, length: 4)])
}

// MARK: - What a map holds

private let sampleNote = """
# Titolo

intro con [[Link]] e `codice`

```swift
let a = 1
```

| a | b |
| - | - |
| 1 | 2 |

- uno
  - due

```pergamenum-view
select: x
```

fine
"""

/// The UTF-16 offset of each "\n"-split line of `text`.
private func lineStarts(_ text: String) -> [Int] {
    var starts = [0]
    var offset = 0
    for unit in text.utf16 {
        offset += 1
        if unit == 10 { starts.append(offset) }
    }
    return starts
}

/// The lines of `text` as the styler reads them: a "\r\n" or "\n" ends one, and the line is without it.
private func lineContents(_ text: String) -> [String] {
    var result: [String] = []
    var current = ""
    for character in text {
        if LineBreak.isTerminator(character) {
            result.append(current)
            current = ""
        } else {
            current.append(character)
        }
    }
    result.append(current)
    return result
}

private func range(of needle: String, in text: String) -> NSRange {
    let found = (text as NSString).range(of: needle)
    guard found.location != NSNotFound else {
        Issue.record("\(needle) is not in the text")
        return NSRange(location: 0, length: 0)
    }
    return found
}

private func spanRanges(_ text: String, where matches: (MarkdownStyler.Span) -> Bool) -> [NSRange] {
    MarkdownStyler.spans(in: text).filter { matches($0.span) }.map { NSRange($0.range, in: text) }
}

// (R-04) One signature per styler line, with the line's start offset.
@Test(arguments: [sampleNote, sampleNote.replacingOccurrences(of: "\n", with: "\r\n")])
func theMapHoldsOneSignaturePerLine(_ text: String) {
    let map = StructureMap(text: text)
    let contents = lineContents(text)
    let starts = lineStarts(text)
    #expect(contents.count > 10)
    #expect(map.lines.count == contents.count)
    #expect(map.lines.map(\.start) == starts)
    for (line, content) in zip(map.lines, contents) {
        #expect(line.signature == MarkdownLineSignature.of(Substring(content)), "\(content.debugDescription)")
    }
}

// (R-04) The signatures the sample note must show, so that a map of the right shape and the wrong
// content cannot pass.
@Test func theSampleNotesLinesCarryTheirKinds() {
    let map = StructureMap(text: sampleNote)
    let contents = lineContents(sampleNote)
    // Safe against a map with no lines: a trap would end the whole run, and the stub's map is empty.
    func signature(of content: String) -> MarkdownLineSignature {
        guard let index = contents.firstIndex(of: content), map.lines.indices.contains(index) else {
            Issue.record("no line \(content.debugDescription) in a map of \(map.lines.count) lines")
            return MarkdownLineSignature.of("")
        }
        return map.lines[index].signature
    }
    #expect(signature(of: "```swift").fenceMark)
    #expect(signature(of: "| - | - |").tableCapable)
    #expect(signature(of: "  - due").listRole == .item(indent: 2, contentColumn: 4))
    #expect(signature(of: "intro con [[Link]] e `codice`").brackets.count == 2)
    #expect(signature(of: "fine").listRole == .reset)
}

// (R-04) The fence regions are `CodeFence`'s: the whole block, the language, and whether it closed.
@Test func theMapHoldsTheFenceRegions() {
    let map = StructureMap(text: sampleNote)
    let regions = CodeFence.regions(in: sampleNote)
    #expect(regions.count == 2)
    #expect(map.fences.count == regions.count)
    for (fence, region) in zip(map.fences, regions) {
        #expect(fence.range == NSRange(region.range, in: sampleNote))
        #expect(fence.language == region.language)
        #expect(fence.isClosed)
    }
    #expect(map.fences.map(\.language) == ["swift", "pergamenum-view"])
}

// (R-04) An unclosed fence runs to the end of the note and says it did not close.
@Test func anUnclosedFenceRunsToTheEnd() {
    let text = "intro\n```swift\nlet a = 1\nlet b = 2"
    let map = StructureMap(text: text)
    #expect(map.fences.count == 1)
    #expect(map.fences.first?.range == NSRange(location: 6, length: (text as NSString).length - 6))
    #expect(map.fences.first?.isClosed == false)
    #expect(map.fences.first?.language == "swift")
}

// (R-04) The table runs and the view-block runs are the ones the full styler spans.
@Test func theMapHoldsTheTableAndViewBlockRuns() {
    let map = StructureMap(text: sampleNote)
    let tables = spanRanges(sampleNote) { $0 == .tableRun }
    let views = spanRanges(sampleNote) { $0 == .viewBlockRun }
    #expect(tables.count == 1)
    #expect(views.count == 1)
    #expect(map.tableRuns == tables)
    #expect(map.viewBlockRuns == views)
    #expect(map.tableRuns.first == range(of: "| a | b |\n| - | - |\n| 1 | 2 |", in: sampleNote))
}

// (R-04) A table inside a fence is no table, and an unclosed view-block fence is no view block.
@Test func aTableInsideAFenceAndAnUnclosedViewBlockAreNoRuns() {
    let tableInFence = "```\n| a | b |\n| - | - |\n```\nfine"
    let map = StructureMap(text: tableInFence)
    #expect(map.fences.count == 1)
    #expect(map.tableRuns.isEmpty)

    let unclosedView = "intro\n```pergamenum-view\nselect: x"
    let unclosedMap = StructureMap(text: unclosedView)
    #expect(unclosedMap.fences.count == 1)
    #expect(unclosedMap.viewBlockRuns.isEmpty)
}

// (R-04) The frontmatter zone is absent without a leading `---`, spans the block when it closes, and
// is the whole text when it does not.
@Test func theFrontmatterZone() {
    #expect(StructureMap(text: "titolo\nbody").frontmatterZoneEnd == nil)
    #expect(StructureMap(text: "intro\n---\nnot frontmatter\n---\n").frontmatterZoneEnd == nil)

    let closed = "---\ntitle: a\n---\nbody"
    let closing = range(of: "---\nbody", in: closed).location
    // The zone reaches the closing `---`: the two parsers differ only on where on that line it ends.
    let end = StructureMap(text: closed).frontmatterZoneEnd
    #expect(end != nil)
    #expect((end ?? -1) >= closing + 3)
    #expect((end ?? Int.max) <= closing + 4)

    let unclosed = "---\ntitle: a\nbody"
    #expect(StructureMap(text: unclosed).frontmatterZoneEnd == (unclosed as NSString).length)
}

// MARK: - apply

/// An edit as a text storage reports it: `range` in the new text, `delta` the change in length.
private func edited(_ text: String, replacing old: NSRange, with replacement: String) -> (text: String, edit: StorageEdit) {
    let new = (text as NSString).replacingCharacters(in: old, with: replacement)
    let length = (replacement as NSString).length
    return (new, StorageEdit(range: NSRange(location: old.location, length: length), delta: length - old.length))
}

/// Edits that change no run: `apply` alone leaves the map equal to the one built from the new text.
private let runPreservingEdits: [(name: String, old: NSRange, replacement: String)] = [
    ("prose above everything", range(of: "intro", in: sampleNote), "intro, e di più,"),
    ("a split paragraph", NSRange(location: range(of: "intro", in: sampleNote).location + 3, length: 0), "\n\n"),
    ("a deleted word", range(of: " con", in: sampleNote), ""),
    ("the first character", NSRange(location: 0, length: 0), "x"),
    ("the heading marker", NSRange(location: 0, length: 2), ""),
    ("inside a fence body", range(of: "let a = 1", in: sampleNote), "let a = 100"),
    ("inside a table cell", range(of: "1 | 2", in: sampleNote), "10 | 2"),
    ("inside a view block body", range(of: "select: x", in: sampleNote), "select: xy"),
    ("a list item's text", range(of: "uno", in: sampleNote), "uno e mezzo"),
    ("the last line", range(of: "fine", in: sampleNote), "fine!"),
]

// (R-02, R-05) After an edit that changes no run, `apply` leaves the map equal to `StructureMap(text:)`
// of the new text: lines after the edit moved, lines it touched recomputed, runs shifted or stretched.
@Test(arguments: runPreservingEdits.indices)
func applyKeepsTheMapEqualToOneBuiltFromTheNewText(_ index: Int) {
    let item = runPreservingEdits[index]
    var map = StructureMap(text: sampleNote)
    let result = edited(sampleNote, replacing: item.old, with: item.replacement)
    map.apply(result.edit, in: result.text as NSString)

    let expected = StructureMap(text: result.text)
    #expect(map == expected, "\(item.name)")
    // Non-vacuity: the expected map is the full one, with every kind of run in it.
    #expect(expected.lines.count > 10)
    #expect(expected.fences.count == 2)
    #expect(expected.tableRuns.count == 1)
    #expect(expected.viewBlockRuns.count == 1)
}

// (R-05) A run after the edit moves by the delta and keeps its length.
@Test func applyShiftsTheRunsBelowTheEdit() {
    var map = StructureMap(text: sampleNote)
    let before = map.tableRuns
    let result = edited(sampleNote, replacing: range(of: "intro", in: sampleNote), with: "introduzione")
    map.apply(result.edit, in: result.text as NSString)
    #expect(before.count == 1)
    #expect(map.tableRuns == before.map { NSRange(location: $0.location + 7, length: $0.length) })
    #expect(map.fences.map(\.range.location) == StructureMap(text: sampleNote).fences.map { $0.range.location + 7 })
}

// MARK: - splice

/// Applies `edit`, then splices the map of `dirty`'s text (in the new text) over it.
private func spliced(_ text: String, replacing old: NSRange, with replacement: String, dirty: (String) -> NSRange)
    -> (map: StructureMap, text: String)
{
    var map = StructureMap(text: text)
    let result = edited(text, replacing: old, with: replacement)
    map.apply(result.edit, in: result.text as NSString)
    let range = dirty(result.text)
    let fragment = (result.text as NSString).substring(with: range)
    map.splice(StructureMap(text: fragment), at: range.location, replacing: range)
    return (map, result.text)
}

// (R-02, R-04) A paragraph that becomes a table: `apply` cannot know a table has appeared, and the
// fragment's map brings its run.
@Test func spliceBringsTheRunOfATableTheEditCreated() {
    let text = "intro\n| a | b |\nriga\nfine"
    let result = spliced(text, replacing: range(of: "riga", in: text), with: "| - | - |") { new in
        let start = range(of: "| a | b |", in: new).location
        let end = NSMaxRange(range(of: "| - | - |", in: new))
        return NSRange(location: start, length: end - start)
    }
    let expected = StructureMap(text: result.text)
    #expect(result.map == expected)
    #expect(expected.tableRuns == [range(of: "| a | b |\n| - | - |", in: result.text)])
}

// (R-02, R-04) A table that loses a row to a blank line: the run the fragment brings is the shorter one.
@Test func spliceReplacesTheRunOfATableTheEditSplit() {
    let text = "intro\n| a | b |\n| - | - |\n| 1 | 2 |\n| 3 | 4 |\nfine"
    let result = spliced(text, replacing: range(of: "| 1 | 2 |", in: text), with: "") { new in
        let start = range(of: "| a | b |", in: new).location
        let end = NSMaxRange(range(of: "| 3 | 4 |", in: new))
        return NSRange(location: start, length: end - start)
    }
    let expected = StructureMap(text: result.text)
    #expect(result.map == expected)
    #expect(expected.tableRuns == [range(of: "| a | b |\n| - | - |", in: result.text)])
}

// (R-02) A fragment with no run takes the dirty range's old runs away and leaves the others where they are.
@Test func spliceLeavesTheRunsOutsideTheDirtyRangeAlone() {
    let text = sampleNote
    let result = spliced(text, replacing: range(of: "fine", in: text), with: "fine e basta") { new in
        range(of: "fine e basta", in: new)
    }
    let expected = StructureMap(text: result.text)
    #expect(result.map == expected)
    #expect(expected.fences.count == 2)
    #expect(expected.tableRuns.count == 1)
    #expect(expected.viewBlockRuns.count == 1)
}
