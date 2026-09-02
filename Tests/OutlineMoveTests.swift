import Foundation
import Testing
@testable import Pergamenum

/// Dragging a section in the Outline pane to move it (PG-019).
///
/// `OutlineMove.replacements` is the pure core: given a note's text, which entry is being
/// dragged, and which entry it should land before (or `nil` for the end of the note), it
/// returns the two range/text edits that move it - or `nil` when the drop is impossible or
/// a no-op. Applying the edits is `NoteTextView.Coordinator.apply(_:to:)`'s job, already
/// tested for the find/replace-all feature that introduced it; this file tests only what
/// `OutlineMove` itself decides.

/// Applies the replacements `OutlineMove.replacements` returns to `text`, the same way
/// `apply(_:to:)` would: in the given order, each against an `NSMutableString` that the
/// earlier (higher-location) edits have already updated.
private func apply(_ replacements: [(range: NSRange, text: String)], to text: String) -> String {
    let mutable = NSMutableString(string: text)
    for (range, replacement) in replacements {
        mutable.replaceCharacters(in: range, with: replacement)
    }
    return mutable as String
}

private func moved(_ text: String, entry: Int, toPrecede destination: Int?) -> String? {
    guard let replacements = OutlineMove.replacements(in: text, moving: entry, toPrecede: destination)
    else { return nil }
    return apply(replacements, to: text)
}

private func nested(_ text: String, entry: Int, under target: Int) -> String? {
    guard let replacements = OutlineMove.replacements(in: text, moving: entry, nestingUnder: target)
    else { return nil }
    return apply(replacements, to: text)
}

// MARK: - R-01/R-02: extent and level rewrite

@Test func movingATopLevelSectionCarriesItsWholeBodyToTheNewPosition() {
    let note = """
    # A
    testo di A
    # B
    testo di B
    """
    let result = moved(note, entry: 0, toPrecede: nil)
    #expect(result == """
    # B
    testo di B
    # A
    testo di A
    """)
}

@Test func movingANestedSectionShiftsItsOwnHeadingAndEveryHeadingInsideItByTheSameDelta() {
    let note = """
    # A
    ## A.1
    ### A.1.1
    testo
    # B
    """
    // Dropped before "# B": the moved section becomes a sibling of B (level 1), a shift of
    // -1 from its own level 2 - so "### A.1.1" (delta -1) becomes "## A.1.1".
    let result = moved(note, entry: 1, toPrecede: 3)
    #expect(result == """
    # A
    # A.1
    ## A.1.1
    testo
    # B
    """)
}

@Test func movingTheLastSectionToPrecedeAnEarlierOneLeavesNothingBehindAtTheOldPosition() {
    let note = """
    # A
    # B
    testo di B
    """
    let result = moved(note, entry: 1, toPrecede: 0)
    // "# A"'s own trailing newline (which used to separate it from "# B") is untouched by
    // the move and simply becomes the file's trailing newline now that "# A" is last.
    #expect(result == "# B\ntesto di B\n# A\n")
}

@Test func droppingASectionUnderADeeperHeadingDeepensItAndItsChildrenTheSameAmount() {
    let note = """
    # A
    ## A.1
    # B
    ## B.1
    """
    // Dropped before "## B.1": becomes a sibling of B.1 (level 2), a shift of +1 from its
    // own level 1.
    let result = moved(note, entry: 0, toPrecede: 3)
    #expect(result == """
    # B
    ## A
    ### A.1
    ## B.1
    """)
}

@Test func droppingASectionAtTheSameLevelItAlreadyHasRewritesNoHeading() {
    let note = """
    # A
    # B
    ## B.1
    # C
    """
    // Dropped before "# A": B is already level 1, A is level 1 - no level change, just a move.
    let result = moved(note, entry: 1, toPrecede: 0)
    #expect(result == """
    # B
    ## B.1
    # A
    # C
    """)
}

// MARK: - R-04: refused drops

@Test func aSectionCannotBeDroppedOntoItself() {
    let note = "# A\ntesto\n# B"
    #expect(OutlineMove.replacements(in: note, moving: 0, toPrecede: 0) == nil)
}

@Test func aSectionCannotBeDroppedInsideItsOwnNestedSubsection() {
    let note = """
    # A
    ## A.1
    testo
    # B
    """
    // Entry 1 is "## A.1", nested inside entry 0's ("# A") extent.
    #expect(OutlineMove.replacements(in: note, moving: 0, toPrecede: 1) == nil)
}

@Test func droppingASectionRightBackWhereItAlreadyIsIsANoOp() {
    let note = "# A\n# B\n# C"
    // "# B" dropped before "# C" (its current next sibling, same level) changes nothing.
    #expect(OutlineMove.replacements(in: note, moving: 1, toPrecede: 2) == nil)
    // Appending the already-last section at the end, unchanged level, is the same no-op.
    #expect(OutlineMove.replacements(in: note, moving: 2, toPrecede: nil) == nil)
}

@Test func onlyAHeadingCanBeDragged() {
    let note = "# A\n![[nota]]\n"
    // Entry 1 is the embed - not a heading.
    #expect(OutlineMove.replacements(in: note, moving: 1, toPrecede: nil) == nil)
}

// MARK: - R-05: target level source

@Test func theTargetLevelIsTheLevelOfTheFollowingHeading() {
    let note = """
    # A
    ## A.1
    # B
    """
    // Dropped before "## A.1": becomes level 2, its sibling. "## A.1"'s own trailing newline,
    // which used to separate it from "# B", is untouched and becomes the file's trailing
    // newline now that "## A.1" is last - same reasoning as the R-01 "leaves nothing behind" case.
    let result = moved(note, entry: 2, toPrecede: 1)
    #expect(result == "# A\n## B\n## A.1\n")
}

@Test func droppingBeforeAnEmbedTakesTheLevelOfItsEnclosingHeading() {
    let note = """
    # A
    ## A.1
    ![[nota]]
    # B
    """
    // The embed under "## A.1" encloses at level 2; dropping "# B" before it makes B level 2.
    // "![[nota]]"'s own trailing newline, which used to separate it from "# B", is untouched
    // and becomes the file's trailing newline now that it is last - same reasoning as the
    // R-01 "leaves nothing behind" case.
    let result = moved(note, entry: 3, toPrecede: 2)
    #expect(result == "# A\n## A.1\n## B\n![[nota]]\n")
}

@Test func appendingAtTheEndOfTheNoteTakesTheLevelOfTheLastRemainingHeading() {
    let note = """
    # A
    ## A.1
    # B
    """
    // Move "# A" (with its "## A.1" child) to the end: the last remaining heading is "# B"
    // at level 1, so A becomes level 1 too (unchanged) and lands after B.
    let result = moved(note, entry: 0, toPrecede: nil)
    #expect(result == """
    # B
    # A
    ## A.1
    """)
}

@Test func appendingTheOnlySectionAtTheEndOfTheNoteIsANoOp() {
    let note = "# A\ntesto"
    #expect(OutlineMove.replacements(in: note, moving: 0, toPrecede: nil) == nil)
}

// MARK: - Nesting as a child (PG-093)

@Test func nestingASectionUnderAHeadingWithNoExistingChildrenAppendsItAtTheirLevelPlusOne() {
    let note = """
    # A
    ## A.1
    testo
    # B
    """
    let result = nested(note, entry: 2, under: 0)
    #expect(result == """
    # A
    ## A.1
    testo
    ## B
    """)
}

@Test func nestingASectionUnderAHeadingWithExistingChildrenLandsAsTheLastOne() {
    let note = """
    # A
    ## A.1
    testo
    # B
    testo di B
    # C
    """
    let result = nested(note, entry: 3, under: 0)
    #expect(result == "# A\n## A.1\ntesto\n## C\n# B\ntesto di B\n")
}

@Test func aSectionCannotBeNestedUnderItself() {
    let note = "# A\ntesto\n# B"
    #expect(OutlineMove.replacements(in: note, moving: 0, nestingUnder: 0) == nil)
}

@Test func aSectionCannotBeNestedUnderItsOwnDescendant() {
    let note = """
    # A
    ## A.1
    testo
    # B
    """
    #expect(OutlineMove.replacements(in: note, moving: 0, nestingUnder: 1) == nil)
}

@Test func nestingUnderAnEmbedOrANonHeadingTargetIsRefused() {
    let note = "# A\n![[nota]]\n"
    #expect(OutlineMove.replacements(in: note, moving: 0, nestingUnder: 1) == nil)
}

@Test func nestingDepthClampsAtLevelSixInsteadOfOverflowing() {
    let note = """
    ###### F
    # G
    """
    let result = nested(note, entry: 1, under: 0)
    #expect(result == "###### F\n###### G")
}
