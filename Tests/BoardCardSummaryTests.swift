import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// ADR-0053 §D2 #3, plan `docs/plans/ui-suite-replacement.md` Task 5, PR 1: what a board card says
// about itself to VoiceOver (`BoardContentLayer.swift`'s `private func accessibilitySummary(for:)`,
// PG-041/PG-108) becomes a pure `BoardContentLayer.accessibilitySummary(for:isFolder:)`.
//
// Converts `UITests/WorkspaceBoardUITests.swift:100`,
// `testAZoomedOutCardStillHasAReadableAccessibilityLabel`: below `BoardGeometry.placeholderZoom` a
// card draws no `Text`, and its label must still say what it holds ("CARD A"). The predicate that
// switches the placeholder in below that zoom is `BoardInteractionTests:206`'s
// (`drawsPlaceholder(at:)`); that `cardBody` consults it is not asserted in-process. What stays out
// of reach is the label as read from the accessibility tree (R-08), and that `NodeAccessibility`
// attaches it: these tests read the string.
//
// `isFolder` is the seam's departure from the plan's `(CanvasNode) -> String`: the `.file` arm
// reads the disk through `workspace.subfolder(for:)`, so the call site passes
// `workspace.subfolder(for: node) != nil` and the function stays pure.

private func node(_ kind: CanvasNode.Kind, unknown: [String: JSONValue] = [:]) -> CanvasNode {
    CanvasNode(id: "aaaa000000000001", kind: kind, x: 0, y: 0, width: 240, height: 140, unknown: unknown)
}

private func summary(_ node: CanvasNode, isFolder: Bool = false) -> String {
    BoardContentLayer.accessibilitySummary(for: node, isFolder: isFolder)
}

@Test func aTextCardIsSummarisedByItsOwnText() {
    // The fixture of the GUI test: a text card reading "CARD A".
    #expect(summary(node(.text("CARD A"))) == "CARD A")
}

@Test func aTextCardIsSummarisedWithoutItsSurroundingWhitespace() {
    #expect(summary(node(.text("  CARD A\n\n"))) == "CARD A")
}

@Test func aBlankTextCardIsSaidToBeAnEmptyNote() {
    #expect(summary(node(.text(""))) == "nota vuota")
    #expect(summary(node(.text(" \n\t "))) == "nota vuota")
}

@Test func aFileCardIsSummarisedByItsFileNameAlone() {
    let card = node(.file(path: "01 Progetti/Cliente/Nota.md", subpath: nil))

    #expect(summary(card) == "Nota.md")
}

@Test func aFileCardPointingAtAFolderIsSaidToBeAFolder() {
    let card = node(.file(path: "Progetti/Cliente", subpath: nil))

    #expect(summary(card, isFolder: true) == "cartella Cliente")
    #expect(summary(card, isFolder: false) == "Cliente")
}

@Test func aLinkCardIsSummarisedByItsStoredTitleAndElseByItsAddress() {
    let titled = node(.link(url: "https://example.invalid/a"), unknown: [LinkCardTitle.key: .string("Documentazione")])
    let bare = node(.link(url: "https://example.invalid/a"))
    let emptyTitle = node(.link(url: "https://example.invalid/a"), unknown: [LinkCardTitle.key: .string("")])

    #expect(summary(titled) == "Documentazione")
    #expect(summary(bare) == "https://example.invalid/a")
    #expect(summary(emptyTitle) == "https://example.invalid/a")
}

@Test func aGroupIsSummarisedByItsLabelAndElseCalledAGroup() {
    #expect(summary(node(.group(label: "GRUPPO"))) == "GRUPPO")
    #expect(summary(node(.group(label: nil))) == "gruppo")
}

@Test func aNodeOfAnUnknownTypeNamesItsType() {
    #expect(summary(node(.unknown(type: "forms"))) == "nodo «forms»")
}

/// The argument the call site passes is `workspace.subfolder(for: node) != nil`. This composes the
/// two the way `BoardContentLayer` does, so a folder card is a folder because its path is a
/// directory on disk and for no other reason.
@MainActor
@Test func aFileCardIsAFolderCardExactlyWhenItsPathIsADirectoryOnDisk() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("Progetti/Cliente")
    try root.makeFile("Progetti/Nota.md")
    let workspace = OpenStateFixture.attachedWorkspace(in: root.url)
    let folderCard = node(.file(path: "Progetti/Cliente", subpath: nil))
    let noteCard = node(.file(path: "Progetti/Nota.md", subpath: nil))
    let missingCard = node(.file(path: "Progetti/Sparita", subpath: nil))

    func composed(_ card: CanvasNode) -> String {
        BoardContentLayer.accessibilitySummary(for: card, isFolder: workspace.subfolder(for: card) != nil)
    }

    #expect(composed(folderCard) == "cartella Cliente")
    #expect(composed(noteCard) == "Nota.md")
    #expect(composed(missingCard) == "Sparita")
}
