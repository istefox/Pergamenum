import Foundation
import Testing
@testable import Pergamenum

// Plan docs/plans/pg-147-core-app-shell-structure.md, Task 5 (PG-147, the `ConformanceText` /
// `"\($0)"` follow-up, closed as "do not unify").
//
// `VaultAPI.LintFinding.init` (`Sources/Connector/VaultPayloads.swift`) writes each violation as
// `"\($0)"`: Swift's reflection of the enum case, labels and payload included. Those strings are
// values inside `LintFinding`, which `.claude/protected-interfaces` lists, and they reach external
// callers through `perg lint --json` and the MCP `lint` tool. A rename of a case or of a payload
// label changes that JSON silently, and until this suite only one string was pinned
// (`duplicateKey("tags")`, `FrontmatterDamageLintTests.theLintFindingShapeIsUnchanged`). Each
// expected string below was captured by running today's code, never written by hand.
//
// Each `ordinal` switch is exhaustive on purpose: a new case does not compile here until it has
// a representative value, and the set check below fails until that value has a pinned string.

private let nameCases: [NoteName.Violation] = [
    .empty, .containsForbiddenCharacter(":"), .tooLong(count: 121), .hasVersionSuffix("v2"),
    .hasLeadingOrTrailingWhitespace, .malformedDailyName("2026-09-30"),
]

private let frontmatterCases: [FrontmatterViolation] = [
    .missingBlock, .missingDate, .missingTags, .foreignKey("title"), .inlineTagList,
    .unparsableTag("Topic/X"), .tooManyAliases(count: 6), .unresolvedRelatedLink("Nota assente"),
    .relatedOutOfSyncWithSection(missingInSection: ["A"], missingInFrontmatter: ["B"]),
    .secondFrontmatterBlock, .duplicateKey("tags"), .lineWithoutColon("riga senza due punti"),
]

private let tagCases: [TagViolation] = [
    .malformed("topic/x"), .notInVocabulary(Tag(namespace: .type, value: "memo")),
    .vocabularyUnavailable(.type), .tooMany(count: 8),
    .multipleStatus([Tag(namespace: .status, value: "draft"), Tag(namespace: .status, value: "final")]),
    .dateTag(Tag(namespace: .topic, value: "20260930")),
    .statusNotAllowedOnNote(Tag(namespace: .status, value: "final")), .missingRequiredTag("type-note"),
]

private let taskMarkerCases: [TaskMarkerViolation] = [
    .duplicateWorkspace(line: 3, kept: "A.canvas", ignored: "B.canvas"), .orphanedParent(line: 4, parent: 2),
]

private let categoryCases: [CategoryViolation] = [
    .unknownSlug("av45"), .duplicateHome("av45", home: "Progetti/AV45.md"),
]

private let finding = VaultAPI.LintFinding(path: "Nota.md", NoteViolations(
    name: nameCases,
    frontmatter: frontmatterCases,
    tags: tagCases,
    relatedMissingInSection: [],
    relatedMissingInFrontmatter: [],
    taskMarkers: taskMarkerCases,
    categories: categoryCases
))

@Test func everyNameViolationStringIsPinned() {
    #expect(Set(nameCases.map(ordinal)) == Set(0..<6))
    #expect(finding.name == [
        #"empty"#,
        #"containsForbiddenCharacter(":")"#,
        #"tooLong(count: 121)"#,
        #"hasVersionSuffix("v2")"#,
        #"hasLeadingOrTrailingWhitespace"#,
        #"malformedDailyName("2026-09-30")"#,
    ])
}

@Test func everyFrontmatterViolationStringIsPinned() {
    #expect(Set(frontmatterCases.map(ordinal)) == Set(0..<12))
    #expect(finding.frontmatter == [
        #"missingBlock"#,
        #"missingDate"#,
        #"missingTags"#,
        #"foreignKey("title")"#,
        #"inlineTagList"#,
        #"unparsableTag("Topic/X")"#,
        #"tooManyAliases(count: 6)"#,
        #"unresolvedRelatedLink("Nota assente")"#,
        #"relatedOutOfSyncWithSection(missingInSection: ["A"], missingInFrontmatter: ["B"])"#,
        #"secondFrontmatterBlock"#,
        #"duplicateKey("tags")"#,
        #"lineWithoutColon("riga senza due punti")"#,
    ])
}

@Test func everyTagViolationStringIsPinned() {
    #expect(Set(tagCases.map(ordinal)) == Set(0..<8))
    #expect(finding.tags == [
        #"malformed("topic/x")"#,
        #"notInVocabulary(type-memo)"#,
        // Module-qualified: `TagNamespace` has no `description`, so reflection names the module
        // that compiled it, `Pergamenum` in this test host and each tool's own module in the
        // connectors, which compile the same file (ADR-0007).
        #"vocabularyUnavailable(Pergamenum.TagNamespace.type)"#,
        #"tooMany(count: 8)"#,
        #"multipleStatus([status-draft, status-final])"#,
        #"dateTag(topic-20260930)"#,
        #"statusNotAllowedOnNote(status-final)"#,
        #"missingRequiredTag("type-note")"#,
    ])
}

@Test func everyTaskMarkerViolationStringIsPinned() {
    #expect(Set(taskMarkerCases.map(ordinal)) == Set(0..<2))
    #expect(finding.taskMarkers == [
        #"duplicateWorkspace(line: 3, kept: "A.canvas", ignored: "B.canvas")"#,
        #"orphanedParent(line: 4, parent: 2)"#,
    ])
}

@Test func everyCategoryViolationStringIsPinned() {
    #expect(Set(categoryCases.map(ordinal)) == Set(0..<2))
    #expect(finding.categories == [
        #"unknownSlug("av45")"#,
        #"duplicateHome("av45", home: "Progetti/AV45.md")"#,
    ])
}

private func ordinal(_ violation: NoteName.Violation) -> Int {
    switch violation {
    case .empty: 0
    case .containsForbiddenCharacter: 1
    case .tooLong: 2
    case .hasVersionSuffix: 3
    case .hasLeadingOrTrailingWhitespace: 4
    case .malformedDailyName: 5
    }
}

private func ordinal(_ violation: FrontmatterViolation) -> Int {
    switch violation {
    case .missingBlock: 0
    case .missingDate: 1
    case .missingTags: 2
    case .foreignKey: 3
    case .inlineTagList: 4
    case .unparsableTag: 5
    case .tooManyAliases: 6
    case .unresolvedRelatedLink: 7
    case .relatedOutOfSyncWithSection: 8
    case .secondFrontmatterBlock, .duplicateKey, .lineWithoutColon: damageOrdinal(violation)
    }
}

/// ADR-0065 §D11's three damage findings, apart so the switch above stays one screen of cases.
private func damageOrdinal(_ violation: FrontmatterViolation) -> Int {
    switch violation {
    case .secondFrontmatterBlock: 9
    case .duplicateKey: 10
    case .lineWithoutColon: 11
    default: -1
    }
}

private func ordinal(_ violation: TagViolation) -> Int {
    switch violation {
    case .malformed: 0
    case .notInVocabulary: 1
    case .vocabularyUnavailable: 2
    case .tooMany: 3
    case .multipleStatus: 4
    case .dateTag: 5
    case .statusNotAllowedOnNote: 6
    case .missingRequiredTag: 7
    }
}

private func ordinal(_ violation: TaskMarkerViolation) -> Int {
    switch violation {
    case .duplicateWorkspace: 0
    case .orphanedParent: 1
    }
}

private func ordinal(_ violation: CategoryViolation) -> Int {
    switch violation {
    case .unknownSlug: 0
    case .duplicateHome: 1
    }
}
