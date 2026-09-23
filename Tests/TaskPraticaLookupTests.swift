import Foundation
import Testing
@testable import Pergamenum

// SPEC (task side of ADR-0049's pratica links), plan
// docs/plans/pratiche-links-task-side-and-inspector-summary.md, Task 1 - R-01, R-06, R-07.

@Suite struct TaskPraticaLookupTests {
    // MARK: - Fixtures

    /// A pratica listing `tasks` as its general task links, nothing else.
    private func source(_ id: String, _ tasks: [(String, Int)]) -> TaskPraticaLookup.Source {
        var links = PraticaLinks()
        links.tasks = tasks.map { PraticaLinks.TaskReference(noteTitle: $0.0, localID: $0.1) }
        return TaskPraticaLookup.Source(praticaID: "Clienti/\(id)", praticaTitle: id, links: links)
    }

    private func lookup(
        _ pratiche: [TaskPraticaLookup.Source],
        titles: [String: [String]] = ["Follow-up": ["Follow-up.md"]],
        ids: [String: [Int]] = ["Follow-up.md": [1, 3, 5]]
    ) -> TaskPraticaLookup {
        TaskPraticaLookup(
            pratiche: pratiche,
            noteCandidates: { titles[$0] ?? [] },
            localIDsInNote: { ids[$0] ?? [] }
        )
    }

    // MARK: - R-07's five cases

    @Test func oneMatchingPraticaYieldsExactlyThatLink() {
        let result = lookup([source("Rossi", [("Follow-up", 3)])])
            .praticheLinking(taskSourcePath: "Follow-up.md", taskLocalID: 3)
        #expect(result == [TaskPraticaLink(praticaID: "Clienti/Rossi", praticaTitle: "Rossi")])
    }

    @Test func twoMatchingPraticheKeepTheirInputOrder() {
        let result = lookup([
            source("Zeta", [("Follow-up", 3)]),
            source("Alfa", [("Follow-up", 3)]),
        ]).praticheLinking(taskSourcePath: "Follow-up.md", taskLocalID: 3)
        #expect(result == [
            TaskPraticaLink(praticaID: "Clienti/Zeta", praticaTitle: "Zeta"),
            TaskPraticaLink(praticaID: "Clienti/Alfa", praticaTitle: "Alfa"),
        ])
    }

    @Test func noMatchingPraticaYieldsNothing() {
        let result = lookup([source("Rossi", [("Follow-up", 1)])])
            .praticheLinking(taskSourcePath: "Follow-up.md", taskLocalID: 3)
        #expect(result.isEmpty)
    }

    @Test func anAmbiguousNoteTitleYieldsNoLinkForEitherPath() {
        let lookup = lookup(
            [source("Rossi", [("Follow-up", 3)])],
            titles: ["Follow-up": ["A/Follow-up.md", "B/Follow-up.md"]],
            ids: ["A/Follow-up.md": [3], "B/Follow-up.md": [3]]
        )
        #expect(lookup.praticheLinking(taskSourcePath: "A/Follow-up.md", taskLocalID: 3).isEmpty)
        #expect(lookup.praticheLinking(taskSourcePath: "B/Follow-up.md", taskLocalID: 3).isEmpty)
    }

    @Test func aCaretIDBelongingToAnotherTaskInTheSameNoteYieldsNothing() {
        let result = lookup([source("Rossi", [("Follow-up", 3)])])
            .praticheLinking(taskSourcePath: "Follow-up.md", taskLocalID: 5)
        #expect(result.isEmpty)
    }

    // MARK: - The ways a body can go wrong

    @Test func aMissingNoteYieldsNothing() {
        let result = lookup([source("Rossi", [("Sparita", 3)])])
            .praticheLinking(taskSourcePath: "Sparita.md", taskLocalID: 3)
        #expect(result.isEmpty)
    }

    /// Pins the reuse of `PraticaLinkResolver.task`'s own `^id` check (R-03): a body that
    /// keyed on `(path, ref.localID)` without asking the resolver would answer `[Rossi]`.
    @Test func aCaretIDTheNoteNoLongerCarriesYieldsNothing() {
        let result = lookup(
            [source("Rossi", [("Follow-up", 9)])],
            ids: ["Follow-up.md": [1, 3]]
        ).praticheLinking(taskSourcePath: "Follow-up.md", taskLocalID: 9)
        #expect(result.isEmpty)
    }

    @Test func aPraticaListingTheSameTaskTwiceYieldsOneLink() {
        let result = lookup([source("Rossi", [("Follow-up", 3), ("Follow-up", 3)])])
            .praticheLinking(taskSourcePath: "Follow-up.md", taskLocalID: 3)
        #expect(result == [TaskPraticaLink(praticaID: "Clienti/Rossi", praticaTitle: "Rossi")])
    }

    /// A task with no `^id` cannot be referenced at all (ADR-0049 §D3).
    @Test func aTaskWithoutACaretIDYieldsNothing() {
        let result = lookup([source("Rossi", [("Follow-up", 3)])])
            .praticheLinking(taskSourcePath: "Follow-up.md", taskLocalID: nil)
        #expect(result.isEmpty)
    }
}
