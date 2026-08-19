import Foundation
import Testing
@testable import Pergamenum

private let note = """
---
date: 2026-08-11
tags:
  - type-note
  - topic-x
---

Corpo della nota.
"""

@Test func addingAStructuralLinkWritesBothPlaces() throws {
    // W-06: `related` and the section must name the same titles, so the app writes
    // both rather than leaving the linter to report a gap it created.
    let updated = try RelatedLink.add(
        target: "Curva di trasmissibilità", reason: "fornisce i dati",
        to: note, selfTitle: "Nota"
    )
    #expect(updated.contains("  - \"[[Curva di trasmissibilità]]\""))
    #expect(updated.contains("## Note correlate"))
    #expect(updated.contains("- [[Curva di trasmissibilità]] — fornisce i dati"))

    let document = NoteDocument.parse(updated)
    let discrepancies = RelatedSection.discrepancies(
        frontmatterRelated: document.frontmatter.related,
        sectionLinks: RelatedSection.parse(from: document.body)
    )
    #expect(discrepancies.missingInSection.isEmpty)
    #expect(discrepancies.missingInFrontmatter.isEmpty)
}

@Test func refusesAStructuralLinkWithoutAReason() {
    // W-04: without a reason it is a citation, which belongs inline in the body.
    #expect(throws: RelatedLink.Error.self) {
        try RelatedLink.add(target: "Altra", reason: "   ", to: note, selfTitle: "Nota")
    }
}

@Test func refusesToLinkANoteToItself() {
    #expect(throws: RelatedLink.Error.self) {
        try RelatedLink.add(target: "Nota", reason: "motivo", to: note, selfTitle: "Nota")
    }
}

@Test func enforcesTheFiveLinkLimit() throws {
    var text = note
    for index in 1...RelatedSection.maximumLinks {
        text = try RelatedLink.add(
            target: "Nota \(index)", reason: "motivo \(index)", to: text, selfTitle: "Origine"
        )
    }
    #expect(RelatedSection.parse(from: text).count == RelatedSection.maximumLinks)

    // W-09: the sixth is refused rather than silently accepted.
    #expect(throws: RelatedLink.Error.self) {
        try RelatedLink.add(target: "Una di troppo", reason: "motivo", to: text, selfTitle: "Origine")
    }
}

@Test func addingTheSameLinkTwiceChangesNothing() throws {
    let once = try RelatedLink.add(target: "Altra", reason: "motivo", to: note, selfTitle: "Nota")
    let twice = try RelatedLink.add(target: "Altra", reason: "altro motivo", to: once, selfTitle: "Nota")
    #expect(once == twice)
}

@Test func keepsBothWritingsInTheSameOrder() throws {
    var text = try RelatedLink.add(target: "Zeta", reason: "z", to: note, selfTitle: "Nota")
    text = try RelatedLink.add(target: "Alfa", reason: "a", to: text, selfTitle: "Nota")

    let document = NoteDocument.parse(text)
    #expect(document.frontmatter.related.first?.contains("Alfa") == true)
    // F-06 and W-06 both ask for alphabetical order, in both writings.
    #expect(RelatedSection.parse(from: document.body).map(\.target) == ["Alfa", "Zeta"])
}

@Test func removingALinkClearsBothWritings() throws {
    var text = try RelatedLink.add(target: "Alfa", reason: "a", to: note, selfTitle: "Nota")
    text = try RelatedLink.add(target: "Beta", reason: "b", to: text, selfTitle: "Nota")

    let removed = RelatedLink.remove(target: "Alfa", from: text)
    #expect(!removed.contains("[[Alfa]]"))
    #expect(removed.contains("[[Beta]]"))

    let document = NoteDocument.parse(removed)
    #expect(document.frontmatter.related.count == 1)
    #expect(RelatedSection.parse(from: document.body).count == 1)
}

@Test func addsTheSectionToANoteThatHasNone() throws {
    let updated = try RelatedLink.add(target: "Altra", reason: "motivo", to: note, selfTitle: "Nota")
    #expect(updated.contains("Corpo della nota."))
    // The existing body survives, and the section lands after it.
    let bodyIndex = updated.range(of: "Corpo della nota.")?.lowerBound
    let headingIndex = updated.range(of: "## Note correlate")?.lowerBound
    #expect(bodyIndex != nil && headingIndex != nil && bodyIndex! < headingIndex!)
}

@Test func leavesAnExistingSectionsOtherContentAlone() throws {
    let withSection = """
    ---
    date: 2026-08-11
    tags:
      - type-note
    related:
      - "[[Prima]]"
    ---

    Corpo.

    ## Note correlate

    - [[Prima]] — motivo iniziale

    ## Task

    - [ ] Un task
    """
    let updated = try RelatedLink.add(
        target: "Seconda", reason: "secondo motivo", to: withSection, selfTitle: "Nota"
    )
    #expect(updated.contains("- [[Prima]] — motivo iniziale"))
    #expect(updated.contains("- [[Seconda]] — secondo motivo"))
    // The next section is untouched.
    #expect(updated.contains("## Task"))
    #expect(updated.contains("- [ ] Un task"))
}

// MARK: - Symmetry across two notes

private struct LinkVault: ~Copyable {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-links-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    func write(_ contents: String, to relativePath: String) throws {
        let url = root.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }
}

@MainActor
@Test func writesTheLinkOnBothNotes() async throws {
    let vault = try LinkVault()
    try vault.write(note, to: "Origine.md")
    try vault.write(note, to: "03 Risorse/Destinazione.md")

    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)

    #expect(controller.addStructuralLink(
        from: "Origine.md", to: "Destinazione",
        reason: "usa i dati", reverseReason: "fornisce i dati"
    ))

    // W-05: the return link is written too, each with its own reason.
    let source = try String(contentsOf: vault.root.appending(path: "Origine.md"), encoding: .utf8)
    let target = try String(contentsOf: vault.root.appending(path: "03 Risorse/Destinazione.md"), encoding: .utf8)
    #expect(source.contains("- [[Destinazione]] — usa i dati"))
    #expect(target.contains("- [[Origine]] — fornisce i dati"))
    #expect(source.contains("\"[[Destinazione]]\""))
    #expect(target.contains("\"[[Origine]]\""))
    controller.close()
}

@MainActor
@Test func writesNeitherNoteWhenTheTargetCannotTakeTheLink() async throws {
    let vault = try LinkVault()
    try vault.write(note, to: "Origine.md")

    // A target already at the five-link limit cannot take another.
    var full = note
    for index in 1...RelatedSection.maximumLinks {
        full = try RelatedLink.add(target: "Nota \(index)", reason: "m\(index)", to: full, selfTitle: "Pieno")
    }
    try vault.write(full, to: "Pieno.md")

    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    #expect(!controller.addStructuralLink(
        from: "Origine.md", to: "Pieno", reason: "a", reverseReason: "b"
    ))

    // Atomic: the source is untouched, so the vault is never left half-linked.
    let source = try String(contentsOf: vault.root.appending(path: "Origine.md"), encoding: .utf8)
    #expect(source == note)
    controller.close()
}

@MainActor
@Test func reportsATargetThatDoesNotExist() async throws {
    let vault = try LinkVault()
    try vault.write(note, to: "Origine.md")

    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    #expect(!controller.addStructuralLink(
        from: "Origine.md", to: "Inesistente", reason: "a", reverseReason: "b"
    ))
    #expect(controller.problems.contains { $0.contains("Inesistente") })
    controller.close()
}
