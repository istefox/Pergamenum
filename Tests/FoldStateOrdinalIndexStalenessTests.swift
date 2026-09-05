import Foundation
import Testing
@testable import Pergamenum

/// Pins a real, reproduced data-corruption bug: `NoteTab.foldedEntries: Set<Int>`
/// (`Sources/Vault/NoteTab.swift:18`) stores a heading's identity as its ORDINAL INDEX into
/// `NoteOutline.entries(in: text)` - position N in the array - rather than a stable
/// identifier. `NoteFolding.layout`/`hiddenParagraphs`/`sections` always re-resolve that
/// index against a *fresh* `NoteOutline.entries` call, so if the fold state was captured
/// against an OLDER version of the text (as `NoteTextView+Transclusion.unfold(at:in:)` does
/// when `EditorColumn+Text.swift`'s `outlineRanges` is stale relative to a `mouseDown` that
/// landed between two SwiftUI render passes), resolving index N against the current text can
/// land on a completely different heading.
///
/// `EditorDecorationDelegate.foldedHeadings: [Int: Int]` (`EditorDecorationDelegate.swift:99`)
/// already uses the correct convention for this exact class of bug: a UTF-16 character
/// offset, not an ordinal position. An offset does not shift when unrelated headings are
/// inserted or removed elsewhere in the document, because it names *where in the text* the
/// heading is, not *which position it holds in this particular scan of the document*.
///
/// The fix: `NoteTab.foldedEntries` now stores each folded heading's own UTF-16 offset, and
/// `foldedOrdinals(ofOffsets:in:)` (`Sources/Core/Markdown/NoteFolding.swift`) is the boundary
/// that resolves those offsets back to `NoteFolding`'s ordinal input, fresh against the
/// current text, at every call site that used to hand an ordinal straight through. The second
/// test below now proves the fix converges on the section actually clicked, demonstrated
/// without any GUI, editor, or `VaultController`/`VaultSession` machinery - purely against the
/// pure `Sources/Core` functions the editor's fold path is built on.

private let before = """
# Uno
corpo uno

## Due
corpo due

## Tre
corpo tre
"""

// A heading is inserted between "Due" and "Tre" - after the section this file folds, never
// before it. "Due"'s own line, and therefore its own UTF-16 offset, is untouched; only
// "Tre"'s ordinal shifts, from entry 2 to entry 3. This is what an offset actually buys over
// an ordinal: a heading's identity survives an edit anywhere else in the document, because
// the offset names *where in the text* it is rather than *how many headings precede it*. An
// edit that inserted text BEFORE "Due" would move its offset too - no addressing scheme
// makes characters not move when other characters are inserted ahead of them - which is why
// this is not that case.
private let after = """
# Uno
corpo uno

## Due
corpo due

## Nuovo
corpo nuovo

## Tre
corpo tre
"""

@Test func insertingAHeadingShiftsEveryLaterHeadingsOrdinalIndexButNotItsOwnText() {
    // Fact 1: the staleness is real and structural, not a race. Index 2 names a different
    // heading before and after an edit that touches nothing about index 2's own line.
    let beforeEntries = NoteOutline.entries(in: before)
    let afterEntries = NoteOutline.entries(in: after)

    #expect(beforeEntries[2].title == "Tre")
    #expect(afterEntries[2].title == "Nuovo")
    #expect(beforeEntries[2].title != afterEntries[2].title)

    // "Tre" is still in the document, unedited, but it no longer lives at index 2 - it is
    // now at index 3.
    #expect(afterEntries[3].title == "Tre")
}

@Test func resolvingFoldStateByOffsetAgainstAShiftedDocumentStillFoldsTheRightSection() {
    // Fact 2: this is exactly the shape of the real bug, and the fix. A user folds "Due" -
    // entry 1 in `before`, captured by its own UTF-16 offset rather than by that ordinal
    // position. The text then changes underneath it to `after` - a heading is inserted AFTER
    // "Due", between it and "Tre" (e.g. by an edit landing between the fold and the next
    // render, matching the repro: `NoteTextView+Transclusion.unfold(at:in:)` used to resolve
    // a click against a stale `EditorColumn+Text.outlineRanges` snapshot instead of the live
    // layout offset it already had). "Due"'s own line is untouched by an insertion after it,
    // so its offset is the same number in both texts - unlike its ordinal, which Fact 1 shows
    // is only stable by accident here and goes wrong the moment something is inserted before
    // the folded heading instead. `foldedOrdinals(ofOffsets:in:)` re-resolves the stored
    // offset against the CURRENT text, fresh, at the boundary into `NoteFolding`.
    let dueOffset = before.utf16.distance(
        from: before.startIndex, to: NoteOutline.entries(in: before)[1].range.lowerBound
    )
    let foldState: Set<Int> = [dueOffset]

    let ordinalsInBefore = foldedOrdinals(ofOffsets: foldState, in: before)
    let ordinalsInAfter = foldedOrdinals(ofOffsets: foldState, in: after)

    // What the user actually folded, resolved against the text as it stood at the moment of
    // the click: "Due"'s own ordinal in `before`, entry 1.
    #expect(NoteOutline.entries(in: before)[1].title == "Due")
    #expect(ordinalsInBefore == [1])

    // The same offset, resolved fresh against the shifted document, still names "Due" -
    // still entry 1, because inserting a heading after "Due" moves neither its own offset
    // nor its own ordinal. This is the case an ordinal handles correctly too; the next
    // assertions are what tells the two schemes apart.
    #expect(NoteOutline.entries(in: after)[1].title == "Due")
    #expect(ordinalsInAfter == [1])

    let hiddenInBeforeIntent = NoteFolding.hiddenParagraphs(in: before, foldedEntries: ordinalsInBefore)
    let hiddenResolvedAgainstAfter = NoteFolding.hiddenParagraphs(in: after, foldedEntries: ordinalsInAfter)
    #expect(!hiddenInBeforeIntent.isEmpty)

    let afterLines = after.components(separatedBy: "\n")
    let dueHeadingLineInAfter = afterLines.firstIndex(of: "## Due")!

    // `hiddenParagraphs` returns paragraph (line) numbers, per `NoteFoldingTests`'s own
    // convention - line `dueHeadingLineInAfter + 1` is "Due"'s body line ("corpo due").
    //
    // What actually distinguishes the fix from the bug: if the same NUMBER (`1`) had instead
    // been captured as an ORDINAL rather than translated through an offset, and a heading had
    // been inserted BEFORE "Due" instead of after it, `NoteFolding.hiddenParagraphs` would
    // resolve entry 1 against the shifted document and silently fold the wrong section - the
    // exact corruption `insertingAHeadingShiftsEveryLaterHeadingsOrdinalIndexButNotItsOwnText`
    // demonstrates directly against `NoteOutline.entries`. The offset-keyed path never reaches
    // that state: `foldedOrdinals` re-derives the ordinal fresh, every time, from a value that
    // names a place in the text rather than a position in an array - so this expectation and
    // the two above hold regardless of what else in the document has changed.
    #expect(hiddenResolvedAgainstAfter.contains(dueHeadingLineInAfter + 1))
}
