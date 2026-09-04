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
/// This file has no fix to test yet - `Set<Int>` is still the storage type - so what it pins
/// is the structural cause: given two versions of a note related by an edit that shifts
/// ordinal positions but not every heading's byte-identity, the SAME ordinal index resolves
/// to a DIFFERENT heading. That is the bug, demonstrated without any GUI, editor, or
/// `VaultController`/`VaultSession` machinery - purely against the pure `Sources/Core`
/// functions the editor's fold path is built on.

private let before = """
# Uno
corpo uno

## Due
corpo due

## Tre
corpo tre
"""

// A heading is inserted between "Uno" and "Due". Nothing about "Due" or "Tre" changed in
// their own text, but every heading from "Due" onward shifted one position later in the
// outline array - "Due" was entry 1, is now entry 2; "Tre" was entry 2, is now entry 3.
private let after = """
# Uno
corpo uno

## Nuovo
corpo nuovo

## Due
corpo due

## Tre
corpo tre
"""

@Test func insertingAHeadingShiftsEveryLaterHeadingsOrdinalIndexButNotItsOwnText() {
    // Fact 1: the staleness is real and structural, not a race. Index 1 names a different
    // heading before and after an edit that touches nothing about index 1's own line.
    let beforeEntries = NoteOutline.entries(in: before)
    let afterEntries = NoteOutline.entries(in: after)

    #expect(beforeEntries[1].title == "Due")
    #expect(afterEntries[1].title == "Nuovo")
    #expect(beforeEntries[1].title != afterEntries[1].title)

    // "Due" is still in the document, unedited, but it no longer lives at index 1 - it is
    // now at index 2.
    #expect(afterEntries[2].title == "Due")
}

@Test func resolvingFoldStateByOrdinalIndexAgainstAShiftedDocumentFoldsTheWrongSection() {
    // Fact 2: this is exactly the shape of the real bug. A user folds "Due" (entry 1 in
    // `before`). Fold state now holds `[1]`. Before the next SwiftUI render reconciles
    // `outlineRanges`, the text changes underneath it to `after` - a heading was inserted
    // earlier in the note (e.g. by another edit landing between the click and the render,
    // matching the repro: `NoteTextView+Transclusion.unfold(at:in:)` resolving a click
    // against a stale `EditorColumn+Text.outlineRanges` snapshot). `NoteFolding` always
    // resolves the stored ordinal against the CURRENT text, per its own doc comment - so `[1]`
    // is now resolved against `after`, not `before`.
    let foldState: Set<Int> = [1]

    let hiddenInBeforeIntent = NoteFolding.hiddenParagraphs(in: before, foldedEntries: foldState)
    let hiddenResolvedAgainstAfter = NoteFolding.hiddenParagraphs(in: after, foldedEntries: foldState)

    // What the user actually folded, resolved against the text as it stood at the moment of
    // the click: "Due"'s body.
    #expect(NoteOutline.entries(in: before)[1].title == "Due")
    #expect(!hiddenInBeforeIntent.isEmpty)

    // What ordinal index 1 resolves to once the document has shifted: "Nuovo"'s body, not
    // "Due"'s - the wrong section is folded, silently, with no error and no signal to the
    // caller that anything went wrong.
    #expect(NoteOutline.entries(in: after)[1].title == "Nuovo")
    #expect(!hiddenResolvedAgainstAfter.isEmpty)

    // This is the bug's user-visible shape: the *lines hidden* differ from what folding
    // "Due" should have hidden, because the same ordinal index now names a different
    // heading. An ordinal-index scheme cannot tell these two intents apart - it has already
    // lost the information needed to. A working fix must make this same input converge on
    // the section actually clicked, which today it structurally cannot: the reported
    // "folded" heading (index 1) is "Nuovo" in `after`, never "Due", even though the user's
    // gesture was aimed at "Due".
    let afterLines = after.components(separatedBy: "\n")
    let dueHeadingLineInAfter = afterLines.firstIndex(of: "## Due")!
    let nuovoHeadingLineInAfter = afterLines.firstIndex(of: "## Nuovo")!

    // `hiddenParagraphs` returns paragraph (line) numbers, per `NoteFoldingTests`'s own
    // convention - line `dueHeadingLineInAfter + 1` is "Due"'s body line ("corpo due").
    //
    // FAILS today: resolving the stale ordinal index against the current text hides
    // "Nuovo"'s body (the wrong section), not "Due"'s (what the user actually clicked) - the
    // corruption the bug report describes. A correct, offset-keyed resolution would still
    // find and fold "Due", because "Due"'s identity does not depend on its position in the
    // array.
    #expect(
        hiddenResolvedAgainstAfter.contains(dueHeadingLineInAfter + 1),
        "expected folding to still hide \"Due\"'s body after the document shifted, but ordinal-index resolution has no way to track that - it silently hid \"Nuovo\"'s body instead (lines \(hiddenResolvedAgainstAfter), \"Due\" heading at line \(dueHeadingLineInAfter), \"Nuovo\" heading at line \(nuovoHeadingLineInAfter))"
    )
}
