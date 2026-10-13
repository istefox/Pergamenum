import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0091 §D6, plan docs/plans/per-paragraph-restyle.md, Task 3 (R-05).
//
// Every holder keyed by an offset is moved where it lives, by the edit the storage reported. The
// test edits the text above a table, a view block, an embed, a transclusion, a fold and the hidden
// markers, in an editor whose kill switch is on, and without the `didChangeText` that would restyle
// it: the storage reports the edit and nothing else moves. It then calls `shiftDerivedState(by:)`
// with `lastRecordedEdit` and compares the snapshot, outside the edited paragraph, with an editor
// opened on the new text and restyled in full. The grid of the table and the host of the view block
// must be the same objects at their new offsets, not rebuilt ones. Every holder's `shift(by:)` and
// the storage delegate that records the edit are pinned here, apart from the restyle that follows.

private struct Case: Sendable, CustomTestStringConvertible {
    var label: String
    /// Located in `RichNote.text` by `needle`, so the case does not hard-code an offset.
    var needle: String
    var offset: Int
    var length: Int
    var replacement: String

    var testDescription: String { label }

    func range(in text: String) -> NSRange {
        let found = (text as NSString).range(of: needle)
        return NSRange(location: found.location + offset, length: length)
    }
}

private let cases: [Case] = [
    Case(label: "insert three characters", needle: "Intro", offset: 2, length: 0, replacement: "abc"),
    Case(label: "insert a paragraph", needle: "Intro", offset: 2, length: 0, replacement: "\n\nnuovo paragrafo\n"),
    Case(label: "delete five characters", needle: "Intro con", offset: 2, length: 5, replacement: ""),
    Case(label: "replace four with two", needle: "Intro con", offset: 2, length: 4, replacement: "xy"),
    Case(label: "insert at the start of the note", needle: "# Titolo", offset: 0, length: 0, replacement: "z"),
    Case(label: "delete a list item line", needle: "1. uno\n", offset: 0, length: 7, replacement: ""),
]

/// The snapshot less everything at or before `boundary`, the end of the edited paragraph: those keys
/// are the paragraph the edit landed in, which the shift does not claim to restyle. The two reveal
/// sets of paragraph offsets are left out as well, for the reason given at `copy.revealed` below.
private func below(_ snapshot: DerivedStateSnapshot, from boundary: Int) -> DerivedStateSnapshot {
    func keys(_ values: [Int]) -> [Int] { values.filter { $0 >= boundary } }
    func offsets(_ values: Set<Int>) -> Set<Int> { values.filter { $0 >= boundary } }
    func ranges(_ values: [NSRange]) -> [NSRange] { values.filter { $0.location >= boundary } }
    var copy = snapshot
    copy.map = nil
    copy.decorations = DecorationSnapshot(
        hiddenMarkerKeys: keys(snapshot.decorations.hiddenMarkerKeys),
        hiddenLineOffsets: offsets(snapshot.decorations.hiddenLineOffsets),
        foldedHeadings: snapshot.decorations.foldedHeadings.filter { $0.key >= boundary },
        tableRowOffsets: offsets(snapshot.decorations.tableRowOffsets),
        viewBlockLineOffsets: offsets(snapshot.decorations.viewBlockLineOffsets),
        renditionKeys: keys(snapshot.decorations.renditionKeys),
        embedRenditionKeys: keys(snapshot.decorations.embedRenditionKeys),
        // Left out with `revealed`, below.
        revealedParagraphs: [],
        revealedSpanKeys: keys(snapshot.decorations.revealedSpanKeys),
        tableViewKeys: keys(snapshot.decorations.tableViewKeys),
        viewBlockHostKeys: keys(snapshot.decorations.viewBlockHostKeys)
    )
    copy.unspellable = ranges(snapshot.unspellable)
    copy.embedRuns = ranges(snapshot.embedRuns)
    copy.tablesDrawn = keys(snapshot.tablesDrawn)
    copy.tableHiddenRows = offsets(snapshot.tableHiddenRows)
    copy.viewBlocksDrawn = keys(snapshot.viewBlocksDrawn)
    copy.viewBlockHiddenLines = offsets(snapshot.viewBlockHiddenLines)
    copy.embedRenditions = keys(snapshot.embedRenditions)
    copy.transclusionRenditions = keys(snapshot.transclusionRenditions)
    var layout = snapshot.foldLayout
    layout.hiddenLineOffsets = offsets(layout.hiddenLineOffsets)
    layout.foldedHeadings = layout.foldedHeadings.filter { $0.key >= boundary }
    copy.foldLayout = layout
    // The outline map (ADR-0096 §D6, plan Task 4): entries below the edited paragraph only, like every
    // other offset-keyed field here. The edited line's own entry is re-read by the splice, which this
    // test does not run (it calls `shiftDerivedState` by hand), so it is not the shift's to produce.
    copy.outline = snapshot.outline.filter { $0.range.location >= boundary }
    // The two reveal sets that hold paragraph offsets (`revealedParagraphs` above, `revealed`) are
    // left out, and the reason is the test's own setup, not the shift: the raw `replaceCharacters`
    // moves the caret, and the selection change that follows already reruns `applyReveal` over the
    // new text and shifts the sets once. The test then calls `shiftDerivedState` by hand, which
    // shifts them a second time, so they differ from the twin's by twice the delta. In the app the
    // shift runs from the storage delegate before any reveal does (ADR-0091 §D6), so the sets are
    // shifted once and come out right; that order is what `IncrementalRestyleHostedTests` and the
    // property test pin end to end. Every other field, `revealedSpans` and `revealedSpanKeys`
    // included, is still compared, and the non-vacuity check still demands every field but the
    // reveal ones non-empty.
    copy.revealed = []
    copy.revealedSpans = snapshot.revealedSpans.filter { $0.key >= boundary }
    return copy
}

@MainActor
@Suite(.serialized) struct OffsetShift {
    // (R-05) After an edit above them, every offset-keyed holder answers what a full restyle of the
    // new text answers, below the edited paragraph.
    @Test(arguments: cases)
    fileprivate func shiftingByTheRecordedEditEqualsARestyleOfTheNewText(_ edit: Case) async throws {
        let original = try await RestyleTwin.rich()
        defer { original.tearDown() }
        // The kill switch is on in `full`: nothing in the editor shifts by itself.
        let editor = original.full
        #expect(editor.coordinator.forcesFullRestyle)
        let range = edit.range(in: editor.textView.string)
        #expect(range.location != NSNotFound)

        let before = editor.coordinator.derivedStateSnapshot()
        let gridsBefore = editor.coordinator.tables.grids.identities()
        let hostsBefore = editor.coordinator.decorations.viewBlockHosts.mapValues { ObjectIdentifier($0) }
        #expect(!gridsBefore.isEmpty, "no table grid to keep")
        #expect(!hostsBefore.isEmpty, "no view-block host to keep")

        // The storage edit alone: no `didChangeText`, so no pass runs and nothing is restyled.
        let storage = try #require(editor.textView.textStorage)
        storage.replaceCharacters(in: range, with: edit.replacement)
        // Asserted, and then stood in for when missing, so the rest of the test still runs red against
        // the placeholders and shows that its own fixture holds.
        #expect(editor.coordinator.lastRecordedEdit != nil, "the storage reported no edit")
        let recorded = editor.coordinator.lastRecordedEdit ?? StorageEdit(
            range: NSRange(location: range.location, length: (edit.replacement as NSString).length),
            delta: (edit.replacement as NSString).length - range.length
        )
        #expect(recorded.delta == (edit.replacement as NSString).length - range.length)
        #expect(recorded.range.location == range.location)

        editor.coordinator.shiftDerivedState(by: recorded)

        let text = editor.textView.string
        // The edited paragraph is every paragraph the edit touches in the new text, the one its end
        // lands in included: an insert that ends in a newline splits the line it landed in, and the
        // remainder is a line of the dirty range too (a restyle of the touched lines writes its
        // markers), so it is not the shift's to produce.
        let nsText = text as NSString
        let paragraph = nsText.paragraphRange(for: recorded.range)
        let tail = nsText.paragraphRange(for: NSRange(location: min(NSMaxRange(recorded.range), nsText.length), length: 0))
        let boundary = max(NSMaxRange(paragraph), NSMaxRange(tail))
        let expected = try await RestyleTwin.rich(text: text)
        defer { expected.tearDown() }

        let shifted = below(editor.coordinator.derivedStateSnapshot(), from: boundary)
        let reference = below(expected.full.coordinator.derivedStateSnapshot(), from: boundary)

        // Non-vacuity: the reference holds each kind of state below the edit, so equal is not empty.
        let empty = RestyleTwin.emptyFields(of: reference).filter { !$0.lowercased().contains("reveal") }
        #expect(empty.isEmpty, "nothing below the edit to compare in \(empty)")
        #expect(RestyleTwin.snapshotDifferences(shifted, reference).isEmpty,
                "\(RestyleTwin.snapshotDifferences(shifted, reference))")
        // And it moved: the state differs from what it held before the edit, unless nothing moved.
        if recorded.delta != 0 {
            #expect(below(before, from: 0) != below(editor.coordinator.derivedStateSnapshot(), from: 0),
                    "the snapshot did not change with the edit: nothing was shifted")
        }

        // The grid of the table and the host of the view block are the same objects, at their new keys.
        let gridsAfter = editor.coordinator.tables.grids.identities()
        #expect(Set(gridsAfter.values) == Set(gridsBefore.values), "a table grid was rebuilt")
        #expect(Set(gridsAfter.keys) == Set(gridsBefore.keys.map { recorded.shifted($0) }))
        let hostsAfter = editor.coordinator.decorations.viewBlockHosts.mapValues { ObjectIdentifier($0) }
        #expect(Set(hostsAfter.values) == Set(hostsBefore.values), "a view-block host was rebuilt")
        #expect(Set(hostsAfter.keys) == Set(hostsBefore.keys.map { recorded.shifted($0) }))
    }

    // (R-05) A thing whose stretch contains the edit is stretched, not lost: an edit inside the folded
    // section keeps the fold, and the badge's line count follows.
    @Test func anEditInsideAFoldedSectionKeepsTheFold() async throws {
        let original = try await RestyleTwin.rich()
        defer { original.tearDown() }
        let editor = original.full
        let before = editor.coordinator.derivedStateSnapshot()
        #expect(!before.foldLayout.foldedHeadings.isEmpty, "no fold to keep")
        let range = (editor.textView.string as NSString).range(of: "nascosto")
        let storage = try #require(editor.textView.textStorage)

        storage.replaceCharacters(in: NSRange(location: range.location, length: 0), with: "bene ")
        #expect(editor.coordinator.lastRecordedEdit != nil, "the storage reported no edit")
        let recorded = editor.coordinator.lastRecordedEdit ?? StorageEdit(
            range: NSRange(location: range.location, length: 5), delta: 5
        )
        editor.coordinator.shiftDerivedState(by: recorded)

        let after = editor.coordinator.derivedStateSnapshot()
        #expect(after.foldLayout.foldedHeadings == before.foldLayout.foldedHeadings,
                "the heading is above the edit and keeps its offset and its line count")
        #expect(after.foldLayout.hiddenLineOffsets.count == before.foldLayout.hiddenLineOffsets.count)
        #expect(!after.foldLayout.hiddenLineOffsets.isEmpty)
        // The lines after the edit moved by its length; the line it landed in did not.
        let moved = before.foldLayout.hiddenLineOffsets.map { $0 > range.location ? $0 + recorded.delta : $0 }
        #expect(after.foldLayout.hiddenLineOffsets == Set(moved), "\(after.foldLayout.hiddenLineOffsets) against \(Set(moved))")
    }
}
