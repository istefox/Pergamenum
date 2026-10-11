import Foundation
import Testing
@testable import Pergamenum

// ADR-0083 §D5 (the catalogue of a choice) and §D6 (the «Crea «X»» row), SPEC R-22 and R-23,
// plan docs/plans/note-workflow-n3.md Task 1.
//
// `LinkChoice.entries(for:)` is rendered on two surfaces, a menu at the click and a sheet; the
// rows are the same value on both, so they are pinned once, here.

// MARK: - folderLabel

@Test func aNoteInAFolderIsLabelledByThatFolder() {
    #expect(LinkChoice.folderLabel(of: "Clienti/Rossi/Offerta.md") == "Clienti/Rossi")
}

@Test func aNoteAtTheVaultRootIsLabelledByTheRootLabel() {
    #expect(LinkChoice.rootLabel == "radice del vault")
    #expect(LinkChoice.folderLabel(of: "Offerta.md") == LinkChoice.rootLabel)
}

// MARK: - An ambiguous title is one row per path

@Test func anAmbiguousDestinationGivesOneRowPerPathLabelledByItsFolder() {
    let entries = LinkChoice.entries(for: .ambiguous(
        title: "Curva", paths: ["Tecnica/Curva.md", "Curva.md", "Archivio/2025/Curva.md"]
    ))

    #expect(entries.map(\.label) == ["Tecnica", LinkChoice.rootLabel, "Archivio/2025"])
    #expect(entries.map(\.detail) == ["Tecnica/Curva.md", "Curva.md", "Archivio/2025/Curva.md"])
    #expect(entries.map(\.action) == [
        .open(path: "Tecnica/Curva.md"), .open(path: "Curva.md"), .open(path: "Archivio/2025/Curva.md"),
    ])
}

@Test func theRowsOfAChoiceHaveUniqueIDs() {
    let entries = LinkChoice.entries(for: .ambiguous(
        title: "Curva", paths: ["A/Curva.md", "B/Curva.md", "Curva.md"]
    ))

    #expect(entries.count == 3)
    #expect(Set(entries.map(\.id)).count == 3, "ogni riga ha il proprio id: la scelta è una List")
}

// MARK: - A creatable dangling link is one «Crea» row

@Test func aCreatableMissingDestinationGivesTheCreateRow() {
    let entries = LinkChoice.entries(for: .missing(title: "Bozza", creatable: true))

    #expect(entries.count == 1)
    #expect(entries.first?.label == "Crea «Bozza»")
    #expect(entries.first?.action == .create(title: "Bozza"))
}

// MARK: - Every other destination offers no choice

@Test func destinationsThatAreNotAChoiceGiveNoRows() {
    #expect(LinkChoice.entries(for: .missing(title: "TRUST.md", creatable: false)).isEmpty)
    #expect(LinkChoice.entries(for: .note(path: "Curva.md")).isEmpty)
    #expect(LinkChoice.entries(for: .board(path: "Q4.canvas")).isEmpty)
    #expect(LinkChoice.entries(for: .missingBoard(name: "Q4.canvas")).isEmpty)
}
