import Foundation
import Testing
@testable import Pergamenum

// PG-263 / PG-265 residue (burn-down 2026-10-03, docs/plans/burn-down-2026-10-03-pg-263-residual.md).
//
// What an in-process test can see of the three view-side fixes:
//   - the one weekday list every grid draws (`MonthGrid.weekdayHeaders`),
//   - that `MenuCommands.swift` no longer spells the three Edit menu titles by hand (a text scan
//     of the source, the shape `NoteStoreReadTests.swift` uses), plus a pin on the catalogue
//     titles it now reads,
//   - a pin on the colour names a swatch's accessibility label is built from.
// Which view reads which, and the accessibility tree itself, are not observable here: a hosted
// SwiftUI tree is a single childless group in-process (`HostedViewSupport.swift`). The catalogue
// pins guard the words only; the menu's use of them is the source scan's, and a swatch's use of
// its name is not checked.

// MARK: - One weekday row for every grid (PG-263)

/// The month view and a view block's calendar used to carry their own hand-typed lists («lun» and
/// «lu»). Both now read `MonthGrid.weekdayHeaders`, so what that list says is what both draw. Each
/// abbreviation is checked against the full Italian weekday name `DateEntry` derives independently
/// from a real Monday-first week.
@Test func eachWeekdayAbbreviationStartsTheItalianNameOfItsColumnMondayFirst() throws {
    let monday = try #require(CalendarDate(iso: "2026-06-01"))
    #expect(DateEntry.weekday(of: monday) == 2, "the fixture week must start on a Monday")

    for (column, header) in MonthGrid.weekdayHeaders.enumerated() {
        let day = try #require(CalendarDate(year: 2026, month: 6, day: 1 + column))
        let name = DateEntry.weekdayName(of: day)
        #expect(name.hasPrefix(header.abbreviation), "column \(column): \(header.abbreviation) vs \(name)")
        #expect(header.abbreviation.count == 3)
        #expect(header.id == column)
    }
}

@Test func theInitialIsTheAbbreviationsFirstLetterCapitalised() {
    for header in MonthGrid.weekdayHeaders {
        #expect(header.initial == String(header.abbreviation.prefix(1)).uppercased())
    }
}

@Test func theSevenAbbreviationsAreDistinctUnlikeTheInitials() {
    let headers = MonthGrid.weekdayHeaders
    #expect(Set(headers.map(\.abbreviation)).count == 7)
    #expect(Set(headers.map(\.initial)).count < 7, "Tuesday and Wednesday share «M»; the abbreviation is what tells them apart")
}

// MARK: - Edit menu titles come from the catalogue (PG-263)

/// `EditCommands` used to spell these three by hand. The guard reads `MenuCommands.swift` as text
/// and fails if any hand-typed title comes back, and requires the catalogue reference in its
/// place, so a moved or renamed file fails here instead of passing on an empty scan.
@Test func theEditMenuNoLongerSpellsItsCatalogueTitlesByHand() throws {
    let url = try resolvedRepoRoot().appendingPathComponent("Sources/App/MenuCommands.swift")
    let source = try String(contentsOf: url, encoding: .utf8)

    for literal in ["Incolla come testo puro", "Trova nella nota", "Sostituisci"] {
        #expect(!source.contains("Button(\"\(literal)\""), "MenuCommands.swift spells «\(literal)» by hand again")
    }
    for command in ["pastePlain", "findInNote", "replaceInNote"] {
        #expect(source.contains("Button(ShortcutCommand.\(command).title)"), "MenuCommands.swift no longer reads ShortcutCommand.\(command).title")
    }
}

/// Catalogue pin only: the Italian words these three `ShortcutCommand` cases carry. That the menu
/// shows them is the source guard above, not this test.
@Test func theThreeEditCatalogueTitlesAreTheirItalianWords() {
    #expect(ShortcutCommand.pastePlain.title == "Incolla come testo puro")
    #expect(ShortcutCommand.findInNote.title == "Trova nella nota")
    #expect(ShortcutCommand.replaceInNote.title == "Sostituisci")
}

// MARK: - The names the swatches read (PG-265)

/// Catalogue pin only: the colour names a swatch's accessibility label is built from. Two equal
/// names, or an empty one, would leave VoiceOver unable to tell the dots apart. That a swatch
/// actually passes its name to `.accessibilityLabel` is not observable in-process and is not
/// checked here.
@Test func everyContenitoreColourHasItsOwnNonEmptyName() {
    let names = ContenitoreColour.allCases.map(\.displayName)
    #expect(names.allSatisfy { !$0.isEmpty })
    #expect(Set(names).count == ContenitoreColour.allCases.count)
    #expect(names == ["Rosso", "Arancio", "Giallo", "Verde", "Ciano", "Viola"])
}

@Test func everyDiaryColourHasItsOwnNonEmptyName() {
    let names = DiaryColour.allCases.map(\.label)
    #expect(names.allSatisfy { !$0.isEmpty })
    #expect(Set(names).count == DiaryColour.allCases.count)
    #expect(names == ["Blu", "Verde", "Giallo", "Rosa", "Grigio"])
}
