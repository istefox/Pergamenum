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

    // PG-396: `CreationError.invalidTitle` reaches a person through every connector that prints
    // the error, and used to word each violation with `"\($0)"`, which reads as the enum case
    // name (`containsForbiddenCharacter("/")`). It now goes through the one wording.

    @Test func aCreationErrorsTitleSentenceIsConformanceTextsWording() {
        let error = VaultSession.CreationError.invalidTitle([.containsForbiddenCharacter("/")])
        #expect(error.description == "Carattere vietato nel titolo: /")
        #expect(!error.description.contains("containsForbiddenCharacter"))
        #expect(!error.description.contains("Pergamenum."))
    }

    @Test func aCreationErrorJoinsSeveralTitleViolationsOnTheSharedSeparator() {
        let violations: [NoteName.Violation] = [.empty, .hasLeadingOrTrailingWhitespace, .tooLong(count: 200)]
        let error = VaultSession.CreationError.invalidTitle(violations)
        #expect(error.description == [
            "Il titolo è vuoto",
            "Spazi all'inizio o alla fine del titolo",
            "Titolo di 200 caratteri, massimo \(NoteName.maximumLength)",
        ].joined(separator: "; "))
        #expect(!error.description.contains("hasLeadingOrTrailingWhitespace"))
        #expect(!error.description.contains("tooLong"))
    }

    /// The two errors are the same sentence for the same violations: that is what "one wording"
    /// means, and what a third copy drifting would break.
    @Test func aCreationErrorAndAFileOperationErrorWordATitleAlike() {
        let violations: [NoteName.Violation] = [
            .containsForbiddenCharacter(":"), .hasVersionSuffix("v2"), .malformedDailyName("2026-1"),
        ]
        #expect(
            VaultSession.CreationError.invalidTitle(violations).description
                == FileOperationError.invalidTitle(violations).description
        )
        #expect(
            VaultSession.CreationError.invalidTitle(violations).description
                == ConformanceText.creationFailure(VaultSession.CreationError.invalidTitle(violations))
        )
    }

    /// (coverage) The sibling case of the same `description`, which no test read: the
    /// connectors print it as is.
    @Test func aCreationErrorNamesTheTakenPath() {
        #expect(VaultSession.CreationError.alreadyExists("a/b.md").description == "esiste già: a/b.md")
    }

    @Test func fallsBackToTheErrorsOwnTextForAnyOtherError() {
        struct Other: Error, CustomStringConvertible { var description: String { "boom" } }
        #expect(ConformanceText.creationFailure(Other()) == "boom")
    }
}
