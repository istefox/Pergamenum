import Foundation
import Testing
@testable import Pergamenum

// ADR-0064 §D11, plan docs/plans/format-edge-hardening.md, Task 7 - R-22.
//
// Frontmatter damage the lossless serializer now keeps verbatim becomes an advisory finding:
// a second block at the head of the body, a repeated key, a line with no colon. Nothing blocks
// on them. `CategoryLintTests.swift`'s shape: every test goes through
// `VaultSession.violations(path:title:text:)`.

@MainActor
private func session(root: URL, stateBase: URL) -> VaultSession {
    VaultSession(
        root: root, stateBase: stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
}

private func damageFindings(_ violations: NoteViolations) -> [FrontmatterViolation] {
    violations.frontmatter.filter {
        switch $0 {
        case .secondFrontmatterBlock, .duplicateKey, .lineWithoutColon: true
        default: false
        }
    }
}

/// A note carrying all three damages, with a task line and a tag a drop can move.
private let damagedNote = "---\ndate: 2026-08-17\ncssclass: a\ncssclass: b\nsolo testo\ntags:\n"
    + "  - type-note\n  - topic-gomma\n---\n---\ndate: 2026-01-01\n---\n\n## Lavoro\n\n"
    + "- [ ] Collaudo pressa >2026-08-17 09:00\n"

@MainActor
@Test func aSecondBlockIsReported() throws {
    let vault = try TemporaryVault()
    let s = session(root: vault.root, stateBase: vault.stateBase)
    let violations = s.violations(path: "Nota.md", title: "Nota", text: FormatEdgeCorpus.damagedDoubleBlock.text)
    #expect(damageFindings(violations) == [.secondFrontmatterBlock])
}

@MainActor
@Test func aSecondBlockAfterATextBorneBOMIsReported() throws {
    let vault = try TemporaryVault()
    let s = session(root: vault.root, stateBase: vault.stateBase)
    let text = "---\n---\n\u{FEFF}---\r\ndate: 2026-01-01\r\ntags: [type-note]\r\n---\r\nCorpo.\r\n"
    let violations = s.violations(path: "Nota.md", title: "Nota", text: text)
    #expect(damageFindings(violations) == [.secondFrontmatterBlock])
}

@MainActor
@Test func aHorizontalRuleIsNotASecondBlock() throws {
    let vault = try TemporaryVault()
    let s = session(root: vault.root, stateBase: vault.stateBase)
    let text = "---\ndate: 2026-09-26\ntags:\n  - type-note\n---\n---\nUna riga di testo.\n---\nCorpo.\n"
    #expect(damageFindings(s.violations(path: "Nota.md", title: "Nota", text: text)).isEmpty)
}

@MainActor
@Test func aDuplicatedKeyIsReportedOnce() throws {
    let vault = try TemporaryVault()
    let s = session(root: vault.root, stateBase: vault.stateBase)
    let tags = s.violations(path: "Nota.md", title: "Nota", text: FormatEdgeCorpus.duplicateTags.text)
    #expect(damageFindings(tags) == [.duplicateKey("tags")])
    let foreign = s.violations(path: "Nota.md", title: "Nota", text: FormatEdgeCorpus.duplicateForeign.text)
    #expect(damageFindings(foreign) == [.duplicateKey("cssclass")])
}

@MainActor
@Test func aColonlessLineIsReportedAndABlankLineIsNot() throws {
    let vault = try TemporaryVault()
    let s = session(root: vault.root, stateBase: vault.stateBase)
    let colonless = s.violations(path: "Nota.md", title: "Nota", text: FormatEdgeCorpus.colonlessAndBlankLines.text)
    #expect(damageFindings(colonless) == [.lineWithoutColon("solo testo")])
    let comment = s.violations(path: "Nota.md", title: "Nota", text: FormatEdgeCorpus.yamlComment.text)
    #expect(damageFindings(comment) == [.lineWithoutColon("# importato da Plaud")])
}

@MainActor
@Test func aConformantNoteHasNoDamageFindings() throws {
    let vault = try TemporaryVault()
    let s = session(root: vault.root, stateBase: vault.stateBase)
    #expect(damageFindings(s.violations(path: "Nota.md", title: "Nota", text: FormatEdgeCorpus.lfConformant.text)).isEmpty)
}

@MainActor
@Test func theLintFindingShapeIsUnchanged() throws {
    let vault = try TemporaryVault()
    let s = session(root: vault.root, stateBase: vault.stateBase)
    let damaged = VaultAPI.LintFinding(
        path: "Nota.md", s.violations(path: "Nota.md", title: "Nota", text: FormatEdgeCorpus.duplicateTags.text)
    )
    let clean = VaultAPI.LintFinding(
        path: "Nota.md", s.violations(path: "Nota.md", title: "Nota", text: FormatEdgeCorpus.lfConformant.text)
    )

    func object(_ finding: VaultAPI.LintFinding) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(finding)) as? [String: Any])
    }
    let damagedObject = try object(damaged)
    #expect(Set(damagedObject.keys) == Set(try object(clean).keys))
    let frontmatter = try #require(damagedObject["frontmatter"] as? [String])
    #expect(frontmatter.contains(#"duplicateKey("tags")"#))
}

@MainActor
@Test func aDamagedNoteDoesNotBlockADrop() async throws {
    let vault = try TemporaryVault()
    try vault.write(damagedNote, to: "Lavoro.md")
    let s = session(root: vault.root, stateBase: vault.stateBase)
    await s.rescan()
    #expect(damageFindings(s.violations(path: "Lavoro.md", title: "Lavoro", text: damagedNote)).count == 3)

    let task = try #require(s.index.allTasks.first { $0.text.contains("Collaudo") })
    let thursday = try #require(CalendarDate(iso: "2026-08-20"))
    let taskOutcome = await s.moveTask(task, to: thursday)
    #expect(taskOutcome.introduced.isEmpty)
    #expect(taskOutcome.problem == nil)
    #expect(taskOutcome.didWrite)

    let boardOutcome = await s.moveOnBoard(
        "Lavoro.md", from: try #require(Pergamenum.Tag("topic-gomma")), to: try #require(Pergamenum.Tag("topic-fune"))
    )
    #expect(boardOutcome.introduced.isEmpty)
    #expect(boardOutcome.problem == nil)
    #expect(boardOutcome.didWrite)
}
