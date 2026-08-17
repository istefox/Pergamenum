import Foundation
import Testing
@testable import Pergamenum

/// Which lines a fold takes away (M8).
///
/// The rule that matters and is not the obvious one: a section ends at the next heading of
/// the *same or a higher* level. Folding `##` has to carry its `###` along and stop at the
/// next `##`. Everything else here is the hostile half - a note is a note, and half of them
/// end in the middle of a section.

private let note = """
# Uno
corpo uno a
corpo uno b

## Uno punto uno
corpo 1.1

### Uno punto uno punto uno
corpo 1.1.1

## Uno punto due
corpo 1.2

# Due
corpo due
"""

private func hidden(_ entries: Set<Int>, in text: String = note) -> Set<Int> {
    NoteFolding.hiddenParagraphs(in: text, foldedEntries: entries)
}

@Test func aSectionEndsAtTheNextHeadingOfTheSameOrAHigherLevel() {
    // `## Uno punto uno` is entry 1; it ends before `## Uno punto due` (entry 3), so it
    // takes its own body *and* the `###` inside it.
    let lines = hidden([1]).sorted()
    #expect(lines == [5, 6, 7, 8, 9])
    // And stops there: `## Uno punto due` and what follows stay.
    #expect(!lines.contains(10))
}

@Test func foldingALevelOneSectionCarriesEverythingUnderIt() {
    // Entry 0 is `# Uno`: everything down to `# Due`.
    // Down to and including the blank line before `# Due`, which is line 13.
    let lines = hidden([0]).sorted()
    #expect(lines.first == 1)
    #expect(lines.last == 12)
    #expect(!lines.contains(13))   // `# Due`
}

@Test func theHeadingItselfIsNeverHidden() {
    // A folded section that took its own title with it would leave nothing to unfold.
    #expect(!hidden([0]).contains(0))
    #expect(!hidden([1]).contains(4))
}

@Test func theLastSectionRunsToTheEndOfTheNote() {
    // Entry 4 is `# Due` on line 13, the last one. Nothing follows it, so its end is the
    // note's.
    let lines = hidden([4]).sorted()
    #expect(lines == [14])
}

@Test func twoNestedFoldsDoNotFightOverTheSameLines() {
    // Folding a section and one inside it is a thing a person does by clicking twice. The
    // union has to be a set, not a count: a line hidden twice is hidden once.
    let outer = hidden([1])
    let both = hidden([1, 2])
    #expect(both == outer)
}

@Test func aHeadingInsideACodeFenceOpensNoSection() {
    // Inherited from `NoteOutline` rather than re-derived, and asserted here because this
    // is the second feature that would get it wrong on its own.
    let text = """
    # Vero

    ```sh
    # non è un titolo
    perg index
    ```

    corpo
    """
    // One entry only, and folding it takes the fence with it as ordinary body.
    #expect(NoteOutline.entries(in: text).count == 1)
    #expect(hidden([0], in: text).sorted() == [1, 2, 3, 4, 5, 6, 7])
}

@Test func aHeadingWithNothingUnderItFoldsToNothing() {
    // Two headings in a row: there is no body between them, so there is nothing to hide -
    // and the index uses exactly this to decide whether to show a chevron at all.
    let text = "# Uno\n# Due\ncorpo"
    #expect(hidden([0], in: text).isEmpty)
    #expect(hidden([1], in: text) == [2])
}

@Test func foldingNothingOrAnEmbedOrAMissingEntryIsHarmless() {
    // Every one of these reaches the folding code from the interface: no folds yet, a click
    // on an embed row, and an index that has been rebuilt smaller under a stale ordinal.
    #expect(hidden([]).isEmpty)
    #expect(hidden([99]).isEmpty)
    #expect(NoteFolding.hiddenParagraphs(in: "", foldedEntries: [0]).isEmpty)
    let withEmbed = "# Uno\n![[Altra nota]]\n"
    #expect(hidden([1], in: withEmbed).isEmpty)
}

// MARK: - What the editor is handed

@Test func theLayoutCarriesTheHiddenOffsetsAndWhatTheBadgeSays() {
    // Two numbers per fold: the offsets the text view needs to leave lines out, and the
    // count the badge shows - which is the only thing on screen a person could not have
    // worked out for themselves.
    let layout = NoteFolding.layout(in: note, foldedEntries: [1])
    #expect(layout.foldedHeadings.count == 1)
    #expect(layout.foldedHeadings.values.first == 5)
    #expect(layout.hiddenLineOffsets.count == 5)

    // The heading's offset is the one the editor will look up, so it has to be the start of
    // its line in UTF-16 and not in characters.
    let headingOffset = try? #require(layout.foldedHeadings.keys.first)
    let text = note as NSString
    #expect(headingOffset.map { text.substring(from: $0).hasPrefix("## Uno punto uno") } == true)
}

@Test func theOffsetsAreUTF16AndSurviveAnAccentAboveTheFold() {
    // The editor counts in UTF-16 and this file is full of Italian. An offset computed in
    // characters would drift by one for every accented letter above the fold, and the wrong
    // line would disappear.
    let accented = "# Perché\ncorpo à è ì\n## Sotto\ncorpo\n"
    let layout = NoteFolding.layout(in: accented, foldedEntries: [1])
    let text = accented as NSString
    // Six accented letters sit above the fold. Counted as characters, the heading's offset
    // would land six places early, in the middle of the line above.
    let heading = layout.foldedHeadings.keys.first
    #expect(heading.map { text.substring(from: $0).hasPrefix("## Sotto") } == true)
    // And nothing above the heading is hidden.
    let headingOffset = heading ?? 0
    #expect(layout.hiddenLineOffsets.allSatisfy { $0 > headingOffset })
}
