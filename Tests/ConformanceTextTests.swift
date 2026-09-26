import Foundation
import Testing
@testable import Pergamenum

/// `ConformanceText` is the one place a violation becomes an Italian sentence, and it
/// has no other test: these pin one sentence per violation family so a reworded or
/// dropped case is a red test, not a silent change in what the person is told.
@Suite struct ConformanceTextTests {
    private func violations(
        name: [NoteName.Violation] = [],
        frontmatter: [FrontmatterViolation] = [],
        tags: [TagViolation] = [],
        taskMarkers: [TaskMarkerViolation] = [],
        categories: [CategoryViolation] = []
    ) -> NoteViolations {
        NoteViolations(
            name: name, frontmatter: frontmatter, tags: tags,
            relatedMissingInSection: [], relatedMissingInFrontmatter: [],
            taskMarkers: taskMarkers, categories: categories
        )
    }

    @Test func aCleanNoteHasNoLines() {
        #expect(ConformanceText.lines(violations()).isEmpty)
    }

    @Test func namesTheTitleViolation() {
        let lines = ConformanceText.lines(violations(name: [.empty]))
        #expect(lines == ["Il titolo è vuoto"])
    }

    @Test func namesTheFrontmatterViolation() {
        let lines = ConformanceText.lines(violations(frontmatter: [.missingDate, .foreignKey("title")]))
        #expect(lines == ["Manca la chiave date", "Chiave fuori schema: title"])
    }

    /// ADR-0065 §D11 (R-22): the three advisory damage findings.
    @Test func conformanceTextNamesTheNewFindings() {
        let lines = ConformanceText.lines(violations(frontmatter: [
            .secondFrontmatterBlock, .duplicateKey("tags"), .lineWithoutColon("solo testo"),
        ]))
        #expect(lines == [
            "Secondo blocco frontmatter all'inizio del corpo",
            "Chiave ripetuta nel frontmatter: tags",
            "Riga del frontmatter senza due punti: solo testo",
        ])
    }

    @Test func namesTheTagViolation() {
        let lines = ConformanceText.lines(violations(tags: [.malformed("Foo")]))
        #expect(lines == ["Tag malformato: Foo"])
    }

    @Test func namesBothRelatedDirections() {
        let named = NoteViolations(
            name: [], frontmatter: [], tags: [],
            relatedMissingInSection: ["A"], relatedMissingInFrontmatter: ["B"]
        )
        #expect(ConformanceText.lines(named) == [
            "A è in related ma non in Note correlate",
            "B è in Note correlate ma non in related",
        ])
    }

    @Test func writesATaskMarkerLineNumberOneBased() {
        let lines = ConformanceText.lines(violations(taskMarkers: [.orphanedParent(line: 0, parent: 3)]))
        #expect(lines == ["Riga 1: ^parent(3) senza ^id(3) in questa nota"])
    }

    @Test func namesTheCategoryViolation() {
        let lines = ConformanceText.lines(violations(categories: [.unknownSlug("acme")]))
        #expect(lines == ["pergamenum-category punta a uno slug non registrato: acme"])
    }

    @Test func keepsTheFamiliesInOrder() {
        let lines = ConformanceText.lines(violations(
            name: [.empty], frontmatter: [.missingBlock], tags: [.malformed("x")]
        ))
        #expect(lines == ["Il titolo è vuoto", "Frontmatter assente", "Tag malformato: x"])
    }

    @Test func describesACreationFailure() {
        #expect(
            ConformanceText.creationFailure(VaultSession.CreationError.alreadyExists("a/b.md"))
                == "Esiste già una nota in a/b.md"
        )
        #expect(
            ConformanceText.creationFailure(VaultSession.CreationError.invalidTitle([.empty]))
                == "Il titolo è vuoto"
        )
    }

    @Test func fallsBackToTheErrorsOwnTextForAnyOtherError() {
        struct Other: Error, CustomStringConvertible { var description: String { "boom" } }
        #expect(ConformanceText.creationFailure(Other()) == "boom")
    }
}
