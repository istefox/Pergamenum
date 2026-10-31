import Foundation
import Testing
@testable import Pergamenum

// ADR-0084 §D2 (the inspector's unresolved links are the open note's own), SPEC R-25, plan
// docs/plans/note-workflow-n3.md Task 1.
//
// `UnresolvedTargets.of` is the one derivation three callers share (the query field, the
// connector read, the snapshot method); `IndexUnresolvedTargetsTests` pins the three together,
// this file pins the derivation.

// MARK: - of(_:resolving:)

@Test func resolvedTargetsAreDroppedAndTheRestKeepTheirOrder() {
    let known: Set<String> = ["Presse", "Forni"]

    let unresolved = UnresolvedTargets.of(
        ["Zeta", "Presse", "Alfa", "Forni", "Beta"],
        resolving: { known.contains($0) ? ["\($0).md"] : [] }
    )

    #expect(unresolved == ["Zeta", "Alfa", "Beta"], "l'ordine è quello di linkTargets, non alfabetico")
}

@Test func duplicatesAreKeptAsGiven() {
    // `linkTargets` already dedupes by exact text; two spellings are two entries, as they were
    // in each of the three places that wrote this out by hand.
    let unresolved = UnresolvedTargets.of(["Ghost", "ghost", "Ghost"], resolving: { _ in [] })

    #expect(unresolved == ["Ghost", "ghost", "Ghost"])
}

@Test func anAmbiguousTargetIsResolvedNotUnresolved() {
    // Two notes with the title: the link is ambiguous (W-07), it is not dangling.
    let unresolved = UnresolvedTargets.of(["Gemello"], resolving: { _ in ["A/Gemello.md", "B/Gemello.md"] })

    #expect(unresolved.isEmpty)
}

@Test func noTargetsGivesNoUnresolvedTargetsAndAsksNothing() {
    let unresolved = UnresolvedTargets.of([], resolving: { _ in
        Issue.record("nessun target: nulla da risolvere")
        return []
    })

    #expect(unresolved.isEmpty)
}

// MARK: - firstLine(linking:in:)

private let sampleNote = """
---
date: 2026-10-07
tags:
  - type-note
---

Intro senza link.

Prima: [[Fantasma|il fantasma]] qui.
Seconda: [[Fantasma]] più sotto.
"""

@Test func theFirstLineHoldingTheLinkIsFoundCountingFromZero() throws {
    let index = try #require(UnresolvedTargets.firstLine(linking: "Fantasma", in: sampleNote))

    // `NoteJump.lineRange` is how the inspector turns this into a caret range, so the number
    // is read the way it reads it: from zero, over the whole text, frontmatter included.
    let range = try #require(NoteJump.lineRange(index, in: sampleNote))
    #expect(String(sampleNote[range]) == "Prima: [[Fantasma|il fantasma]] qui.")
    #expect(index == 8)
}

@Test(arguments: [
    "Qui [[Fantasma]] chiaro.",
    "Qui [[Fantasma|alias]] con alias.",
    "Qui [[Fantasma#Sezione]] con sezione.",
])
func aPlainAnAliasedAndASectionedLinkAreAllFound(line: String) {
    #expect(UnresolvedTargets.firstLine(linking: "Fantasma", in: "Riga zero.\n\(line)\n") == 1)
}

@Test func aLinkInsideACodeFenceOrAnInlineSpanIsSkipped() {
    let text = """
    ```
    [[Fantasma]] nel blocco
    ```
    `[[Fantasma]]` inline
    Solo qui: [[Fantasma]].
    """

    #expect(UnresolvedTargets.firstLine(linking: "Fantasma", in: text) == 4)
}

@Test func aTargetThatIsNotInTheTextHasNoLine() {
    #expect(UnresolvedTargets.firstLine(linking: "Assente", in: sampleNote) == nil)
    #expect(UnresolvedTargets.firstLine(linking: "Fantasma", in: "Niente link.") == nil)
}

// ADR-0097 §D3 (R-06): the target «Vai al link» receives is a resolved title now (the index
// stores `resolvedTitle`), so an emphasised link is found by the title it names.
@Test func anEmphasisedLinkIsFoundByTheTitleItNames() {
    let text = """
    ---
    date: 2026-10-16
    tags:
      - type-note
    ---

    prima
    Vedi [[**Nuova**]].
    """

    // Zero-based over the whole text, frontmatter included: the second body line.
    #expect(UnresolvedTargets.firstLine(linking: "Nuova", in: text) == 7)
}

// (coverage) ADR-0097 §D3: `firstLine` compares `resolvedTitle` exactly, which holds because the
// index stores that same trimmed value. Every unresolved target the note's own `linkTargets` yields,
// spaces inside the emphasis included, is a target «Vai al link» finds, on the line that holds it.
@Test func everyUnresolvedTargetTheIndexDerivesIsFoundOnItsLine() {
    let text = """
    ---
    date: 2026-10-16
    tags:
      - type-note
    ---

    Vedi [[** Nuova **]].
    poi [[~~Altra~~|alias]]
    e [[*Terza*#Sez]].
    """
    let targets = UnresolvedTargets.of(
        NoteStore.linkTargets(in: NoteDocument.parse(text)), resolving: { _ in [] }
    )

    #expect(targets == ["Nuova", "Altra", "Terza"], "l'indice tiene il titolo risolto, senza spazi")
    #expect(targets.map { UnresolvedTargets.firstLine(linking: $0, in: text) } == [6, 7, 8])
}
