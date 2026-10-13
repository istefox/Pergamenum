import Foundation
import Testing
@testable import Pergamenum

/// Pins the foldable offset the sidebar's chevron and its row's double-click share (PG-double-click-fold):
/// the heading's own UTF-16 offset when the entry can be folded, nil for anything else, so a double-click
/// on a heading row's text toggles fold state exactly like a click on its chevron, without duplicating the
/// `foldable` guard.
///
/// **Restated for ADR-0095 §D7 (PG-406, plan Task 4).** These three cases called
/// `OutlinePane.foldableOffset(for:at:)` on a pane built with the note's text. The pane no longer holds the
/// text (it draws from `OutlinePaneInputs`), so the answer moved to `OutlineStore.foldableOffset(ofEntry:)`,
/// which reads the store's map. The texts, the entries asked about and the expected answers are the ones the
/// cases had; only the object asked changed. Red until the store reads its map (Task 5).
@MainActor
@Test func foldableOffsetMatchesTheChevronsOwnOffsetForAFoldableHeading() {
    // "Uno" has a body line under it ("corpo uno"), so it is foldable - the same
    // condition `chevron(for:at:)` guards with `foldable.contains(index)`.
    let text = "# Uno\ncorpo uno\n\n## Due\ncorpo due\n"
    let entries = NoteOutline.entries(in: text)
    let index = 0
    #expect(entries[index].title == "Uno")

    let expectedOffset = text.utf16.distance(from: text.startIndex, to: entries[index].range.lowerBound)
    let subject = OutlineStore(text: text)

    #expect(subject.foldableOffset(ofEntry: index) == expectedOffset)
}

@MainActor
@Test func foldableOffsetIsNilForAHeadingWithNothingUnderIt() {
    // "Due" is the last line in the note - nothing sits under it, so folding it would
    // fold to nothing and the chevron draws a blank spacer instead of a button.
    let text = "# Uno\ncorpo uno\n\n## Due"
    let entries = NoteOutline.entries(in: text)
    let index = entries.firstIndex { $0.title == "Due" }!

    let subject = OutlineStore(text: text)

    #expect(subject.foldableOffset(ofEntry: index) == nil)
}

@MainActor
@Test func foldableOffsetIsNilForAnEmbedEntry() {
    // An embed has no section of its own to fold - `chevron(for:at:)` never even reaches
    // the offset computation for one, guarded by `case .heading = entry.kind`.
    let text = "# Uno\n![[Mescole per il forno]]\n"
    let entries = NoteOutline.entries(in: text)
    let index = entries.firstIndex { $0.kind == .embed }!
    #expect(entries[index].kind == .embed)

    let subject = OutlineStore(text: text)

    #expect(subject.foldableOffset(ofEntry: index) == nil)
}
