import Foundation
import Testing
@testable import Pergamenum

/// Pins `OutlinePane.foldableOffset(for:at:)` (PG-double-click-fold), the helper the plan
/// extracts from `chevron(for:at:)`'s existing inline computation
/// (`OutlinePane.swift:142-147`) so a double-click on a heading row's text can toggle fold
/// state exactly like a click on its chevron, without duplicating the `foldable` guard.
///
/// `OutlinePane` needs no `VaultController` to answer this: `foldableOffset` reads only
/// `entry`, `index`, `text` and the private `foldable` set, none of which touch
/// `@Environment(VaultController.self)`. A plain memberwise `OutlinePane(...)` is enough -
/// no environment injection, no view render pass, matching how `NoteListPane+Footer.swift`
/// constructs one for the real UI.
private func pane(text: String) -> OutlinePane {
    OutlinePane(
        entries: NoteOutline.entries(in: text),
        onSelect: { _, _ in },
        text: text,
        notePath: "nota.md",
        onMove: { _ in }
    )
}

@Test func foldableOffsetMatchesTheChevronsOwnOffsetForAFoldableHeading() {
    // "Uno" has a body line under it ("corpo uno"), so it is foldable - the same
    // condition `chevron(for:at:)` guards with `foldable.contains(index)`.
    let text = "# Uno\ncorpo uno\n\n## Due\ncorpo due\n"
    let entries = NoteOutline.entries(in: text)
    let index = 0
    #expect(entries[index].title == "Uno")

    let expectedOffset = text.utf16.distance(from: text.startIndex, to: entries[index].range.lowerBound)
    let subject = pane(text: text)

    #expect(subject.foldableOffset(for: entries[index], at: index) == expectedOffset)
}

@Test func foldableOffsetIsNilForAHeadingWithNothingUnderIt() {
    // "Due" is the last line in the note - nothing sits under it, so folding it would
    // fold to nothing and the chevron draws a blank spacer instead of a button.
    let text = "# Uno\ncorpo uno\n\n## Due"
    let entries = NoteOutline.entries(in: text)
    let index = entries.firstIndex { $0.title == "Due" }!

    let subject = pane(text: text)

    #expect(subject.foldableOffset(for: entries[index], at: index) == nil)
}

@Test func foldableOffsetIsNilForAnEmbedEntry() {
    // An embed has no section of its own to fold - `chevron(for:at:)` never even reaches
    // the offset computation for one, guarded by `case .heading = entry.kind`.
    let text = "# Uno\n![[Mescole per il forno]]\n"
    let entries = NoteOutline.entries(in: text)
    let index = entries.firstIndex { $0.kind == .embed }!
    #expect(entries[index].kind == .embed)

    let subject = pane(text: text)

    #expect(subject.foldableOffset(for: entries[index], at: index) == nil)
}
