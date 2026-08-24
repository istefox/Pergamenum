import Foundation
import Testing
@testable import Pergamenum

// ADR-0021 ("A task carries its Workspace and its place in a project as caret markers in
// its own line, and nothing new is stored anywhere else"), §D11. Plan
// `docs/superpowers/plans/2026-08-24-workspace-tasks-notes-integration.md`, Task 5: the
// two advisory linter rules R-11 (a second `^[[...]].canvas` marker on one task line) and
// R-12 (a `^parent(N)` with no matching `^id(N)` in the same note).
//
// `NoteViolations.taskMarkers` and `TaskMarkerViolation` (`Sources/Core/Conventions/
// NoteViolations.swift`) and `VaultAPI.LintFinding.taskMarkers` (`Sources/Connector/
// VaultPayloads.swift`) are signature-only additions as of this commit: the property
// exists, defaulted to `[]`, and every test below is expected to fail red on its
// assertions rather than to fail to compile. `VaultSession.violations(path:title:text:)`
// (`Sources/Vault/VaultSession+Search.swift:106-131`) does not populate `taskMarkers` yet
// - that detection is the coder's Task 5 job. Two tests are guards rather than
// new-behaviour assertions and are expected to already be green, because the defaulted
// property already answers `[]` for a note with nothing to report: the false-positive
// case (`^parent(2)` with a matching `^id(2)` in the same note) and the conformant note.

@MainActor
private func session(root: URL, stateBase: URL) -> VaultSession {
    VaultSession(
        root: root, stateBase: stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
}

@MainActor
private func openSession(root: URL, stateBase: URL) async -> VaultSession {
    let opened = session(root: root, stateBase: stateBase)
    await opened.rescan()
    return opened
}

/// The same frontmatter `Tests/ConventionsTests.swift`'s `conformantNote` uses: `type-note`
/// is a closed family and needs the bundled vocabulary to validate clean, `topic-*` is an
/// open family and needs only to be present. Kept identical across every test here so a
/// `count` assertion measures only the task-marker findings, not an unrelated frontmatter
/// or tag violation this task did not ask for.
private func note(_ body: String) -> String {
    """
    ---
    date: 2026-08-11
    tags:
      - type-note
      - topic-vibration-isolation
    ---

    \(body)
    """
}

// MARK: - R-11: a second `^[[...]].canvas` marker

@MainActor
@Test func duplicateWorkspaceMarkerProducesExactlyOneFinding() throws {
    let vault = try TemporaryVault()
    let s = session(root: vault.root, stateBase: vault.stateBase)
    let text = note("- [ ] Verifica ^[[vibrofer-emea.canvas]] ^[[altro-progetto.canvas]]")

    let violations = s.violations(path: "Nota.md", title: "Nota", text: text)
    let task = try #require(TaskParser.tasks(in: text, sourcePath: "Nota.md").first)

    #expect(violations.taskMarkers == [
        .duplicateWorkspace(line: task.lineIndex, kept: "vibrofer-emea.canvas", ignored: "altro-progetto.canvas"),
    ])
}

// MARK: - R-12: an orphaned `^parent`

@MainActor
@Test func orphanedParentProducesExactlyOneFinding() throws {
    let vault = try TemporaryVault()
    let s = session(root: vault.root, stateBase: vault.stateBase)
    let text = note("- [ ] Sotto-task ^parent(9)")

    let violations = s.violations(path: "Nota.md", title: "Nota", text: text)
    let task = try #require(TaskParser.tasks(in: text, sourcePath: "Nota.md").first)

    #expect(violations.taskMarkers == [.orphanedParent(line: task.lineIndex, parent: 9)])
}

// MARK: - The false-positive guard, the one that matters most

@MainActor
@Test func aParentWithAMatchingIDInTheSameNoteProducesNoFinding() throws {
    let vault = try TemporaryVault()
    let s = session(root: vault.root, stateBase: vault.stateBase)
    let text = note("""
    - [ ] Padre ^id(2)
    - [ ] Figlio ^parent(2)
    """)

    let violations = s.violations(path: "Nota.md", title: "Nota", text: text)

    #expect(violations.taskMarkers.isEmpty, "\(violations.taskMarkers)")
}

// MARK: - Ids are note-local (ADR-0021 §D2): a matching `^id` in another note does not clear it

@MainActor
@Test func aParentWhoseMatchingIDLivesInADifferentNoteStillProducesAFinding() throws {
    let vault = try TemporaryVault()
    let s = session(root: vault.root, stateBase: vault.stateBase)

    // `^id(1)` exists, but in "Progetto.md" - a different note from the one carrying
    // `^parent(1)`. `violations(path:title:text:)` reads one note's own text and never
    // an index, so this is the same guarantee proven from the other side: the function
    // physically cannot see across notes, and the finding must still fire.
    let parentNoteText = note("- [ ] Padre ^id(1)")
    let childNoteText = note("- [ ] Presunto figlio ^parent(1)")

    let parentViolations = s.violations(path: "Progetto.md", title: "Progetto", text: parentNoteText)
    let childViolations = s.violations(path: "Altro.md", title: "Altro", text: childNoteText)
    let childTask = try #require(TaskParser.tasks(in: childNoteText, sourcePath: "Altro.md").first)

    #expect(parentViolations.taskMarkers.isEmpty)
    #expect(childViolations.taskMarkers == [.orphanedParent(line: childTask.lineIndex, parent: 1)])
}

// MARK: - A conformant note reports nothing, and `isEmpty` stays true

@MainActor
@Test func aConformantNoteHasNoTaskMarkerFindingsAndIsEmptyStaysTrue() throws {
    let vault = try TemporaryVault()
    let s = session(root: vault.root, stateBase: vault.stateBase)
    let text = note("- [ ] Task senza marcatori di alcun tipo")

    let violations = s.violations(path: "Nota.md", title: "Nota", text: text)

    #expect(violations.taskMarkers.isEmpty)
    #expect(violations.isEmpty, "\(violations)")
}

// MARK: - `count` grows by exactly the number of findings

@MainActor
@Test func countGrowsByExactlyTheNumberOfTaskMarkerFindings() throws {
    let vault = try TemporaryVault()
    let s = session(root: vault.root, stateBase: vault.stateBase)
    let text = note("""
    - [ ] Verifica ^[[vibrofer-emea.canvas]] ^[[altro-progetto.canvas]]
    - [ ] Sotto-task ^parent(9)
    """)

    let violations = s.violations(path: "Nota.md", title: "Nota", text: text)

    #expect(violations.taskMarkers.count == 2)
    #expect(violations.count == 2, "\(violations)")
}

// MARK: - Nothing blocks (SPEC §4.7: the linter reports and does not correct)

@MainActor
@Test func aNoteWithBothFindingsStillWritesThroughApplyAndTheVaultStillScans() async throws {
    let vault = try TemporaryVault()
    try vault.write(note("""
    - [ ] Verifica ^[[vibrofer-emea.canvas]] ^[[altro-progetto.canvas]]
    - [ ] Sotto-task ^parent(9)
    """), to: "Nota.md")
    let s = await openSession(root: vault.root, stateBase: vault.stateBase)

    // Confirms the note the write test is about really does carry both findings, so a
    // later relaxation of the note text would not silently make this test meaningless.
    let violations = try #require(s.violations(forRecordAt: "Nota.md"))
    #expect(violations.taskMarkers.count == 2)

    let task = try #require(s.index.allTasks.first { $0.text == "Verifica" })
    guard case .written = s.apply(.state(.done), to: task) else {
        Issue.record("il task non è stato scritto nonostante il linter avesse due segnalazioni avanzate: \(s.problems)")
        return
    }

    // And the vault still scans afterwards - nothing about the findings above blocked
    // either the write or a subsequent rescan.
    await s.rescan()
    #expect(s.index.allTasks.contains { $0.sourcePath == "Nota.md" && $0.state == .done })
}
