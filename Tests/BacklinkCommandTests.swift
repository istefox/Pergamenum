import Foundation
import Testing
@testable import Pergamenum

// ADR-0084 §D1 (the row menu is one catalogue, rendered twice), SPEC R-24 and R-27, plan
// docs/plans/note-workflow-n3.md Task 5.
//
// `BacklinkCommand` is a pure value: which commands a row offers, and what they are called. The
// context menu and the accessibility actions both read it (ADR-0023 §D1), so a test of the
// catalogue is a test of both.

private func row(structural: Bool) -> BacklinkRow {
    BacklinkRow(
        title: "Origine", path: "Origine.md", firstLine: "Vedi [[Curva]].", count: 1, isStructural: structural
    )
}

@Test func aPlainRowOffersOpenOpenInTheOtherColumnAndMakeStructural() {
    #expect(BacklinkCommand.available(for: row(structural: false)) == [
        .open, .openInOtherColumn, .makeStructural,
    ])
}

@Test func aStructuralRowOffersOpenOpenInTheOtherColumnAndUnlink() {
    #expect(BacklinkCommand.available(for: row(structural: true)) == [
        .open, .openInOtherColumn, .unlink,
    ])
}

@Test func theTitlesAreTheSpecsItalian() {
    #expect(BacklinkCommand.open.title == "Apri")
    #expect(BacklinkCommand.openInOtherColumn.title == "Apri nell'altra colonna")
    #expect(BacklinkCommand.makeStructural.title == "Rendi strutturale")
    #expect(BacklinkCommand.unlink.title == "Scollega")
}

@Test func theCatalogueHasTheFourCommandsAndEachIsItsOwnIdentity() {
    #expect(BacklinkCommand.allCases.count == 4)
    #expect(Set(BacklinkCommand.allCases.map(\.id)).count == 4)
    #expect(Set(BacklinkCommand.allCases.map(\.title)).count == 4, "four commands, four different words")
}

@Test func noRowOffersBothMakeStructuralAndUnlink() {
    for structural in [false, true] {
        let offered = BacklinkCommand.available(for: row(structural: structural))
        #expect(offered.contains(.makeStructural) != offered.contains(.unlink))
    }
}
