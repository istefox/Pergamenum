import Foundation
import Testing
@testable import Pergamenum

// The sidebar's rows (M12). The list is written by hand, three sections at a time, so
// the thing worth checking is that hand-writing it did not lose or double a pane.

@Test func everyPaneHasExactlyOneRow() {
    let rows = SidebarItem.Group.allCases.flatMap(\.items)
    let panes = rows.compactMap { row -> Navigation.Pane? in
        if case .pane(let pane) = row { return pane }
        return nil
    }

    #expect(Set(panes) == Set(Navigation.Pane.allCases), "un pannello non ha una riga, o ne ha due")
    #expect(panes.count == Navigation.Pane.allCases.count)
}

@Test func nothingInTheSidebarIsAnActionThatLandsElsewhere() {
    // «Preferite» was one for an evening: it opened a section of the note list, so the
    // highlight jumped to «Note» and the click read as one that had done nothing. Every
    // row is now a place, and the day's note is the day scale with that note open.
    let rows = SidebarItem.Group.allCases.flatMap(\.items)
    #expect(rows.contains(.pane(.starred)))
    #expect(rows.contains(.dailyNote))
}

@Test func theRowsAreAllDistinct() {
    let rows = SidebarItem.Group.allCases.flatMap(\.items)
    #expect(Set(rows.map(\.id)).count == rows.count)
}

@Test func theDayScalesAreRowsAndTheDayItselfIsThePane() {
    let day = SidebarItem.Group.day.items

    // Giorno is `pane(.today)` and not `scale(.day)`: two rows for one place would be
    // two rows the selection could sit on with nothing to tell them apart.
    #expect(day.contains(.pane(.today)))
    #expect(!day.contains(.scale(.day)))
    #expect(day.contains(.scale(.week)))
    #expect(day.contains(.scale(.month)))
}

@Test func everyPaneStillCarriesARemappableShortcut() {
    // The Vista menu builds itself from this, so a pane added without one would be a
    // menu entry with no key rather than a compile error.
    let commands = Navigation.Pane.allCases.map(\.shortcut)
    #expect(Set(commands).count == Navigation.Pane.allCases.count)
    #expect(Navigation.Pane.views.shortcut == .paneViews)
}

// ADR-0036 (Pratiche), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 6 -
// R-33: «Pratiche» sits in LAVORO, immediately before «Registrazioni» (UX-BLUEPRINT.md
// "Sidebar (column 1, existing)": "new row «Pratiche» in the LAVORO group, immediately
// before «Registrazioni»"). Red until the coder adds `.pane(.pratiche)` to
// `SidebarItem.Group.work.items` - the tester declares the placement fact, not the row.
@Test func praticheSitsInLavoroImmediatelyBeforeRecordings() {
    let work = SidebarItem.Group.work.items
    #expect(work.contains(.pane(.pratiche)), "«Pratiche» non è nel gruppo LAVORO")

    let praticheIndex = work.firstIndex(of: .pane(.pratiche))
    let recordingsIndex = work.firstIndex(of: .pane(.recordings))
    if let praticheIndex, let recordingsIndex {
        #expect(
            recordingsIndex == praticheIndex + 1,
            "«Pratiche» deve precedere immediatamente «Registrazioni» in LAVORO"
        )
    }
}

// MARK: - Il catalogo delle viste

private let catalogueNote = """
---
date: 2026-08-20
tags:
  - type-note
---

# Viste di prova

## Note di produzione

```pergamenum-view
where: tag("topic-produzione")
render: table
```

Prosa in mezzo.

## Tutto

```pergamenum-view
render: list
```
"""

@Test func aViewIsFoundWithTheHeadingAboveItAndTheLineItIsOn() {
    let found = ViewCatalogue.locations(in: catalogueNote)

    #expect(found.count == 2)
    #expect(found[0].heading == "Note di produzione")
    #expect(found[1].heading == "Tutto")
    // The line is the opening fence, counted over the whole file: it is what the jump
    // takes, and a body-relative number would land in the frontmatter's neighbourhood.
    let lines = catalogueNote.components(separatedBy: "\n")
    #expect(lines[found[0].lineIndex] == "```pergamenum-view")
    #expect(lines[found[1].lineIndex] == "```pergamenum-view")
}

@Test func aViewFenceQuotedInsideAnotherBlockIsNotAView() {
    let note = """
    # Come si scrive una vista

    ```markdown
    ```pergamenum-view
    render: table
    ```
    ```

    ## Quella vera

    ```pergamenum-view
    render: list
    ```
    """

    let found = ViewCatalogue.locations(in: note)
    #expect(found.count == 1)
    #expect(found[0].heading == "Quella vera")
}

@Test func anUnnamedSecondViewIsStillItsOwnRow() {
    // Two views in one note with no headings would both be called after the note, which
    // is what the pane looked like before it had names at all.
    let first = ViewEntry(path: "Note/x.md", noteTitle: "x", ordinal: 0, lineIndex: 3,
                          heading: nil, block: nil, error: "rotta", matches: nil)
    let second = ViewEntry(path: "Note/x.md", noteTitle: "x", ordinal: 1, lineIndex: 9,
                           heading: nil, block: nil, error: "rotta", matches: nil)

    #expect(first.name == "x")
    #expect(second.name == "x · vista 2")
    #expect(first.id != second.id)
}

@Test func aFilterIsSaidInWordsRatherThanInGrammar() {
    #expect(ViewFilterText.describe(.all) == "nessun filtro")
    #expect(ViewFilterText.describe(.tag("topic-produzione")) == "topic-produzione")
    #expect(ViewFilterText.describe(.and(.tag("client-*"), .not(.task(.done))))
        == "client-* e non task completati")
    #expect(ViewFilterText.describe(.text("frequenza")) == "testo «frequenza»")
}
