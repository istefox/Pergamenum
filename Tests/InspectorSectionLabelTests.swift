import Foundation
import Testing
@testable import Pergamenum

// PG-380: the note inspector's BACKLINK and LINK NON RISOLTI sections draw through `TraySection`,
// which gives each header an `-header` identifier and a spoken label. The inspector needs a whole
// `VaultController` to host, and a hosted view's accessibility tree is one childless group
// in-process (`HostedViewSupport.swift`), so these tests call the function both sections build
// their `TraySection` arguments from (`VaultBrowser.InspectorSection`), fed the same count the
// view feeds it: zero, one and several.

@Test(arguments: [0, 1, 7])
func theBacklinksSectionFollowsItsCount(count: Int) {
    let section = VaultBrowser.InspectorSection.backlinks(count: count)
    #expect(section.title == "BACKLINK")
    #expect(section.identifier == "inspector-backlinks")
    #expect(section.accessibilityLabel == "Backlink a questa nota: \(count)")
    #expect(section.isEmpty == (count == 0))
    #expect(section.emptyText == "nessuno")
}

@Test(arguments: [0, 1, 10])
func theUnresolvedLinksSectionNamesTheLinksOfTheOpenNote(count: Int) {
    let section = VaultBrowser.InspectorSection.unresolved(count: count)
    #expect(section.title == "LINK NON RISOLTI")
    #expect(section.identifier == "inspector-unresolved-links")
    // ADR-0084 §D2 / plan Task 5: the list is the open note's own, not a capped vault-wide sample.
    #expect(section.accessibilityLabel == "Link non risolti in questa nota: \(count)")
    #expect(section.isEmpty == (count == 0))
    // Plan Task 6: the empty state names the open note, as the section's own scope does.
    #expect(section.emptyText == "nessun link non risolto in questa nota")
}

// ADR-0084 §D6: «Dove compare» is asked for, so its section has a resting state (`found` nil: no
// answer computed yet) and a counted one. The wording of the labels is not fixed by the SPEC or
// the ADR; what is pinned is what any wording has to do.

@Test func theWhereAppearsSectionIsTitledAsTheMockupHasIt() {
    #expect(VaultBrowser.InspectorSection.whereAppears(found: nil).title == "DOVE COMPARE")
    #expect(VaultBrowser.InspectorSection.whereAppears(found: 3).title == "DOVE COMPARE")
}

@Test func theRestingWhereAppearsLabelSaysSomethingAndDoesNotInventACount() {
    let resting = VaultBrowser.InspectorSection.whereAppears(found: nil)
    #expect(!resting.accessibilityLabel.isEmpty)
    #expect(!resting.identifier.isEmpty)
    // A zero before the scan would be a number nobody computed.
    let digits = resting.accessibilityLabel.filter { $0.isNumber }
    #expect(digits.isEmpty)
}

@Test(arguments: [0, 1, 4])
func theCountedWhereAppearsLabelCarriesTheCount(found: Int) {
    let resting = VaultBrowser.InspectorSection.whereAppears(found: nil)
    let counted = VaultBrowser.InspectorSection.whereAppears(found: found)
    #expect(counted.accessibilityLabel.contains("\(found)"))
    #expect(counted.accessibilityLabel != resting.accessibilityLabel)
    #expect(counted.identifier == resting.identifier, "one section, one identifier")
}
