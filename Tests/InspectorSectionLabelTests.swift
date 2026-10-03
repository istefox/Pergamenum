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
func theUnresolvedLinksSectionNamesTheLinksItShows(shown: Int) {
    let section = VaultBrowser.InspectorSection.unresolved(shown: shown)
    #expect(section.title == "LINK NON RISOLTI")
    #expect(section.identifier == "inspector-unresolved-links")
    #expect(section.accessibilityLabel == "Link non risolti mostrati: \(shown)")
    #expect(section.isEmpty == (shown == 0))
    #expect(section.emptyText == "nessuno")
}
